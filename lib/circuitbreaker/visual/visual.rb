require "curses"

require_relative "panel.rb"
require_relative "bsp_layout.rb"
require_relative "minibuffer_panel.rb"
require_relative "memory_editor.rb"

module Visual
  module ColorPairs
    IDAllocator = 1.upto(Float::INFINITY)
    PC = IDAllocator.next
    Border = IDAllocator.next
    PostIDAllocator = IDAllocator.next.upto(Float::INFINITY)
  end
  
  class Mode
    def self.standalone
      Mode.new.open do |vism|
        yield vism
      end
    end

    def initialize
    end
    
    attr_reader :minibuffer_panel
    attr_accessor :active_panel
    
    def open
      Curses.init_screen
      begin
        Curses.start_color
        Curses.nonl
        Curses.raw
        Curses.noecho
        Curses.init_pair(ColorPairs::PC, Curses::COLOR_BLACK, Curses::COLOR_GREEN)
        Curses.init_pair(ColorPairs::Border, Curses::COLOR_BLACK, Curses::COLOR_WHITE)
        ColorPairs::PostIDAllocator.rewind
        
        running = true
        screen = Curses.stdscr

        @minibuffer_panel = MiniBufferPanel.new(self)
        @active_panel = nil
        @panel = yield self
        @active_panel||= @panel
        
        root = BSPLayout.new(
          {:dir => :vert, :fixed_item => :b, :fixed_size => 1},
          @panel, @minibuffer_panel)
        
        root.redo_layout(0, 0, Curses.lines, Curses.cols)
        root.refresh

        while running do
          @active_panel.window.refresh
          chr = @active_panel.window.getch
          if chr == Curses::KEY_RESIZE then
            root.redo_layout(0, 0, Curses.lines, Curses.cols)
            root.refresh
            next
          end
          if(!@active_panel.handle_key(chr)) then
            case chr
            when "q", 3
              running = false
            when 26 # ^Z
              Process.kill("TSTP", Process.pid)
            else
              self.handle_key(chr)
            end
          end
        end
      ensure
        Curses.close_screen
      end
    end

    def handle_key(chr)
    end
  end
end
