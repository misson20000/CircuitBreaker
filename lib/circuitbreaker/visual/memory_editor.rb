require "set"

require_relative "panel.rb"

module Visual
  class MemoryEditorPanel < Panel
    PAGE_SIZE = 0x1000
    
    def initialize(vism, initial_cursor, highlighters, memio)
      super()
      @vism = vism
      @highlighters = highlighters
      @memio = memio
      @cursor = initial_cursor
      @@color_mgr||= begin
                       color_mgr = HighlightColorManager.new
                       color_mgr.add_color(:fg, Curses::COLOR_WHITE)
                       color_mgr.add_color(:bg, Curses::COLOR_BLACK)
                       color_mgr.add_color(:pc, Curses::COLOR_GREEN)
                       color_mgr.add_color(:reg, Curses::COLOR_BLUE)
                       color_mgr.add_color(:cursor, Curses::COLOR_RED)
                       color_mgr
                     end
      @cache = {}
      @mod_blocks = Set.new
      @nibble = false

      @highlighters.push(
        lambda do
          addr = (@cursor.to_i/8)*8
          entry = @cache[addr/PAGE_SIZE]
          if entry && entry.has_data? then
            [Highlight.new("*", entry.get(addr, 8).unpack("Q<")[0], :cursor, false)]
          else
            []
          end
        end)

      @cursor_history = []
    end

    attr_accessor :cursor
    
    Highlight = Struct.new("Highlight", :name, :value, :color, :match_data)

    class HighlightColorManager
      def initialize
        @colors = []
        @color_map = {}
        @color_pairs = []
      end
      
      def add_color(name, color)
        if name == nil then raise "name is nil" end
        if color == nil then raise "color is nil" end
        id = @colors.size
        @color_map[name] = id
        @color_pairs.each_with_index do |map, i|
          pair_id = ColorPairs::PostIDAllocator.next
          fg = @colors[i]
          Curses.init_pair(pair_id, fg, color)
          map[id] = [pair_id, fg, color]
        end
        @colors[id] = color
        @color_pairs[id] = @colors.map do |bg|
          pair_id = ColorPairs::PostIDAllocator.next
          Curses.init_pair(pair_id, color, bg)
          next [pair_id, color, bg]
        end
      end
      
      def get_pair(fg, bg)
        @color_pairs[@color_map[fg]][@color_map[bg]][0]
      end
    end
    
    def redo_layout(miny, minx, maxy, maxx, parent=nil)
      super
      self.recenter
      self.refresh
    end

    def recenter
      @center = (@cursor/16).floor * 16
      self.refresh
    end

    def show_addrs?
      @width > 16 * 4
    end

    # -1: no permission
    # -2: downloading
    def get_line(addr)
      entry = @cache[addr.to_i/PAGE_SIZE]
      if entry then
        entry.get_line(addr)
      else
        @@loading_line||= Array.new(16, -2)
      end
    end

    def get_edits(addr)
      entry = @cache[addr.to_i/PAGE_SIZE]
      if entry then
        entry.get_edits_for_line(addr)
      else
        @@empty_arr||= []
      end
    end

    class CacheEntry
      def initialize(addr)
        @addr = addr
        @mode = :loading
        @can_write = false
        @first_edit = nil
      end

      def load(bytes, can_write, perms)
        @bytes = bytes
        @mode = :loaded
        @can_write = can_write
        @perms = perms
      end

      attr_reader :perms
      
      def each
        walker = @first_edit
        while walker != nil do
          yield walker
          walker = walker.next_edit
        end
      end

      include Enumerable
      
      def get_line(addr)
        case @mode
        when :loading
          @@loading_line||= Array.new(16, -2)
        when :loaded
          self.inject(@bytes[addr-@addr, 16]) do |line, edit|
            edit.apply(line, addr)
          end.bytes
        when :noperm
          @@noperm_line||= Array.new(16, -1)
        end
      end

      def get(addr, length)
        if !has_data? then
          raise "no data"
        end
        self.inject(@bytes[addr-@addr, length]) do |line, edit|
          edit.apply(line, addr)
        end
      end

      def get_byte(addr)
        if @mode != :loaded then
          raise "no data"
        end
        self.inject(@bytes[addr-@addr]) do |b, edit|
          edit.apply(b, addr)
        end.unpack("C")[0]
      end
      
      def get_edits_for_line(addr)
        self.select do |edit|
          edit.overlaps?(addr, 16)
        end
      end
      
      def has_data?
        @mode == :loaded
      end

      def can_write?
        @can_write
      end

      def is_loading?
        @mode == :loading
      end

      def make_edit(addr, value)
        if !@can_write then
          raise "can't write"
        end
        edit = Edit.new(addr, [value].pack("C"))
        prev = self.select do |e|
          e.base <= addr
        end.last
        if prev then
          prev.insert_next(edit)
        else
          edit.insert_next(@first_edit)
          @first_edit = edit
        end
      end

      def commit_edits(memio)
        each do |e|
          memio.write_sync(e.base, e.patch)
          @bytes = e.apply(@bytes, @addr)
          @first_edit = e
          yield e
        end
        @first_edit = nil
      end

      def fetch(memio, panel)
        memio.permissions(@addr) do |perms|
          if perms & 1 > 0 then # if we have READ
            memio.read(@addr, PAGE_SIZE) do |data|
              @bytes = data
              @can_write = perms & 2 > 0
              @perms = perms
              @mode = :loaded
              if !block_given? || yield then
                panel.refresh
              end
            end
          else
            @mode = :noperm
            if !block_given? || yield then
              panel.refresh
            end
          end
        end
      end
      
      class Edit
        def initialize(base, patch)
          @base = base
          @patch = patch
          @next_edit = nil
        end

        attr_reader :base
        attr_reader :patch
        attr_accessor :next_edit

        def insert_next(edit)
          if edit == nil then
            @next_edit = nil
          else
            edit.next_edit = @next_edit
            @next_edit = edit
            attempt_merge_next
          end
        end

        def attempt_merge_next
          if @next_edit.base < @base then
            raise "next base < @base"
          end
          if @next_edit.base > @base + @patch.length then
            return # can't merge
          end
          @patch[@next_edit.base-@base, @next_edit.patch.length] = @next_edit.patch
          @next_edit = @next_edit.next_edit
        end

        def overlaps?(addr, length)
          return @base+@patch.length > addr && @base < addr+length
        end

        def apply(data, addr)
          if @base+@patch.length <= addr || @base >= addr+data.length then
            return data
          end
          length = [[addr+data.length, @base+@patch.length].min-@base, 0].max
          cut_beg = [addr-@base, 0].max
          data[[@base-addr,0].max, length-cut_beg] = @patch[cut_beg, length-cut_beg]
          return data
        end
      end
    end

    def attempt_data_fetch(start, length)
      finished = false
      addr = (start.to_i/PAGE_SIZE)*PAGE_SIZE
      while addr < start + length do
        if !@cache[addr/PAGE_SIZE] then
          lambda do |entry| # get a new scope because while doesn't make one for us
            @cache[addr/PAGE_SIZE] = entry
            entry.fetch(@memio, self) do
              finished
            end
          end.call(CacheEntry.new(addr))
        end

        addr+= PAGE_SIZE
      end
      finished = true
    end

    def refresh
      @window.clear
      @window.setpos(0, 0)
      @window.attron(Curses::color_pair(ColorPairs::Border))
      @window.addstr("Memory Viewer".ljust(@width))
      @window.attroff(Curses::color_pair(ColorPairs::Border))

      registers = @highlighters.map do |h|
        h.call
      end.flatten(1)
      
      start = @center - (@height/2).floor * 16 # 16 bytes per line

      attempt_data_fetch(start, (@height-1)*16)
      
      (@height-1).times do |i|
        line_start = start + i * 16
        line_end = start + (i+1) * 16

        @window.attroff(Curses::A_UNDERLINE)
        @window.setpos(i+1, 0)

        if show_addrs? then
          @window.addstr(" ")
          @window.attron(Curses::A_DIM)
          addr_s = line_start.to_s(16)
          @window.addstr("0" * (16-addr_s.length))
          @window.addstr(addr_s + " ")
          @window.attroff(Curses::A_DIM)
        end
        
        content = get_line(line_start)
        edits = get_edits(line_start)

        next_content = get_line(line_start + 16)
        if !(next_content.find do |b| b < 0 end) then
          words = next_content.pack("C*").unpack("Q<Q<")
          registers.each do |reg|
            if reg.match_data then
              if reg.value == words[0] then
                registers.push Highlight.new(reg.name, line_start + 16, reg.color, false)
              end
              if reg.value == words[1] then
                registers.push Highlight.new(reg.name, line_start + 24, reg.color, false)
              end
            end
          end
        end
        
        content.each_with_index do |b, j|
          b_str = b >= 0 ? b.to_s(16) : (b == -1 ? "  " : "..")
          
          addr = line_start + j
          space_width = j == 8 ? 2 : 1
          next_space_width = j == 7 ? 2 : 1

          reg_next_line = registers.find do |r|
            r.value <= (addr+16) && r.value >= (line_start+16)
          end

          reg_at_space = registers.find do |r|
            r.value/8 == addr/8 && r.value != addr
          end
          
          if reg_next_line then
            space_bg = reg_at_space ? reg_at_space.color : :bg
            next_underline_fg = reg_next_line.color
            
            color = @@color_mgr.get_pair(next_underline_fg, space_bg)
            
            @window.attron(Curses::color_pair(color))
            @window.attron(Curses::A_BOLD)
            @window.addstr(" " * space_width) # for some reason, the unicode underscores inherit the foreground color but not the background color?
            @window.attroff(Curses::A_BOLD)
            @window.attroff(Curses::color_pair(color))
            @window.addstr("\u0332" * (2+next_space_width)) # unicode combining underscore
          else
            color = @@color_mgr.get_pair(reg_at_space ? :bg : :fg, reg_at_space ? reg_at_space.color : :bg)
            @window.attron(Curses::color_pair(color))
            @window.addstr(" " * space_width)
            @window.attroff(Curses::color_pair(color))
          end

          reg = registers.find do |r|
            r.value/8 == addr/8
          end

          color = @@color_mgr.get_pair(reg ? :bg : :fg, reg ? reg.color : :bg)
          uncommitted = edits.any? do |e|
            e.overlaps?(addr, 1)
          end
          @window.attron(Curses::color_pair(color))
          @window.attron(Curses::A_BOLD) if uncommitted
          @window.addstr(b_str.rjust(2, "0"))
          @window.attroff(Curses::A_BOLD)
          @window.attroff(Curses::color_pair(color))
        end

        regs_next_line = registers.select do |r|
          r.value >= (line_start+16) && r.value < (line_end+16)
        end

        regs_next_line_sort = regs_next_line.sort_by do |r| r.value end

        regs_next_line_sort.each_with_index do |r, i|
          reg_effecting_color = regs_next_line.find do |r2|
            regs_next_line_sort.find_index(r2) >= i
          end
          
          color = @@color_mgr.get_pair(reg_effecting_color.color, :bg)
          @window.attron(Curses::A_BOLD)
          @window.attron(Curses::color_pair(color))
          @window.addstr(i == 0 ? " " : (regs_next_line_sort[i-1].value == r.value ? "\u0332&" : "\u005f")) # receives underline from previous iteration
          @window.attroff(Curses::color_pair(color))

          color = @@color_mgr.get_pair(r.color, :bg)
          @window.attron(Curses::color_pair(color))
          @window.addstr("\u0332" * (r.name.length) + r.name) # unicode combining underscore
          @window.attroff(Curses::color_pair(color))
          @window.attroff(Curses::A_BOLD)
        end
      end
      
      @window.setpos(
        (@cursor - start)/16 + 1,
        (show_addrs? ? 19 : 1) +
        ((@cursor%16)*3) +
        ((@cursor%16)>=8 ? 1 : 0) +
        (@nibble ? 1 : 0))

      super()
    end

    def enter_digit(d)
      block = @cache[@cursor/PAGE_SIZE]
      if block && block.has_data? then
        current = block.get_byte(@cursor)
        new = @nibble ? (current & 0xF0) | d : (current & 0x0F) | (d<<4)
        if block.can_write? then
          block.make_edit(@cursor, new)
          @mod_blocks.add block
          advance_cursor
          self.refresh
          return
        else
          @mb_message = @vism.minibuffer_panel.show_message("Memory is write-protected")
          Curses::beep
        end
      else
        Curses::beep
        if block then
          if block.is_loading?
            @mb_message = @vism.minibuffer_panel.show_message("Memory is being downloaded")
          else
            @mb_message = @vism.minibuffer_panel.show_message("No memory is mapped here")
          end
        else
          @mb_message = @vism.minibuffer_panel.show_message("This is a bug")
        end
      end
    end

    def cursor_moved
      self.refresh
    end

    def advance_cursor
      if @nibble then
        @cursor+=1
        @nibble = false
      else
        @nibble = true
      end
    end

    def handle_key(key)
      old_cursor = @cursor
      old_nibble = @nibble
      if @mb_message then
        @mb_message.close
        @mb_message = nil
      end
      case key
      when "n"
        advance_cursor
      when "p"
        if @nibble then
          @nibble = false
        else
          @cursor-= 1
          @nibble = true
        end
      when Curses::KEY_RIGHT
        @cursor+= 1
        @nibble = false
      when Curses::KEY_LEFT
        if @nibble then
          @nibble = false
        else
          @cursor-= 1
        end
      when Curses::KEY_UP
        @cursor-= 16
        @nibble = false
      when Curses::KEY_DOWN
        @cursor+= 16
        @nibble = false
      when Curses::KEY_ENTER, 13
        entry = @cache[@cursor/PAGE_SIZE]
        if entry && entry.has_data? then
          @cursor_history.push @cursor
          @cursor = entry.get(@cursor, 8).unpack("Q<")[0]
          self.recenter
          self.refresh
        end
      when 27
        @cursor = @cursor_history.pop
        self.recenter
      when "L"
        self.recenter
        self.refresh
      when "C"
        count = get_uncommitted_edits.length
        msg = @vism.minibuffer_panel.grab_focus(count.to_s + " change" + (count != 1 ? "s" : "") + " remain...")
        @mod_blocks.each do |en|
          en.commit_edits(@memio) do |e|
            count-= 1
            msg.content = count.to_s + " change" + (count != 1 ? "s" : "") + " remain..."
          end
          en.fetch(@memio, self)
        end
        @mod_blocks.clear
        msg.close
      when "a".."f"
        enter_digit(0x0A + key.ord - "a".ord)
      when "0".."9"
        enter_digit(0x00 + key.ord - "0".ord)
      else
        return false
      end
      if @cursor != old_cursor || @nibble != old_nibble then
        cursor_moved
      end
      return true
    end

    def get_uncommitted_edits
      @mod_blocks.map do |en|
        en.to_a
      end.flatten
    end
    
    def border_content
      uncommitted = get_uncommitted_edits.map do |e|
        e.patch.length
      end.inject(0, :+)
      entry = @cache[@cursor/PAGE_SIZE]
      [
        "-", # for looks
        (entry ? [
                   (entry.perms.to_i & 0b001) > 0 ? "R" : "-",
                   (entry.perms.to_i & 0b010) > 0 ? "W" : "-",
                   (entry.perms.to_i & 0b100) > 0 ? "X" : "-"
                 ].join : "loading").ljust(8, "-"),
        "0x" + @cursor.to_s(16).rjust(16, "0"),
        "---",
        uncommitted.to_s + " uncommitted byte" + (uncommitted != 1 ? "s" : "")].join
    end
  end
end

class SynchronousMemoryInterface
  def initialize(dsl)
    @dsl = dsl
  end

  def read(addr, size)
    yield @dsl.read(addr, 0, size)
  end

  def read_sync(addr, size)
    read(addr, size) do |val|
      return val
    end
  end
  
  def write(addr, value)
    @dsl.write(addr, 0, value)
    yield
  end

  def permissions(addr)
    yield @dsl.memory_permissions(addr)
  end

  def open
    yield self
  end
end

require "thread"

class AsynchronousMemoryInterface
  def initialize(dsl)
    @dsl = dsl
    @io_queue = Queue.new
  end

  def read(addr, size, &block)
    @io_queue.push({:type => :read, :addr => addr.to_i, :size => size.to_i, :block => block})
  end

  def write(addr, data, &block)
    @io_queue.push({:type => :write, :addr => addr.to_i, :data => data, :block => block})
  end

  def write_sync(addr, data)
    m = Mutex.new
    m.synchronize do
      v = ConditionVariable.new
      write(addr, data) do
        v.signal
      end
      v.wait(m)
    end
  end
  
  def permissions(addr, &block)
    @io_queue.push({:type => :permissions, :addr => addr.to_i, :block => block})
  end
  
  def open
    thread = Thread.new do
      begin
        yield self
        @io_queue.push({:type => :exit})
      rescue => e
        @io_queue.push({:type => :exit, :error => e})
      end
    end
    
    job = @io_queue.pop
    while job[:type] != :exit do
      case job[:type]
      when :read
        job[:block].call(@dsl.read(job[:addr], 0, job[:size]))
      when :write
        @dsl.write(job[:addr], 0, job[:data])
        job[:block].call
      when :permissions
        job[:block].call(@dsl.memory_permissions(@dsl.make_pointer(job[:addr])))
      end
      job = @io_queue.pop
    end

    if job[:error] then # propogate exceptions
      raise job[:error]
    end
  end
end
