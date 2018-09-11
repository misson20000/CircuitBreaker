module Visual
  class MiniBufferPanel
    def initialize(visual)
      @visual = visual
      @window = Curses::Window.new(0, 0, 0, 0)
      @window.keypad = true
    end

    attr_reader :window
    
    def redo_layout(miny, minx, maxy, maxx, parent=nil)
      @window.resize(maxy-miny, maxx-minx)
      @window.move(miny, minx)
      @width = maxx-minx
    end

    def refresh
      @window.setpos(0, 0)
      @window.addstr((@controller ? @controller.content : "").ljust(@width))
      @window.setpos(0, @controller ? @controller.cursor : 0)
      @window.refresh
    end

    def edit_comment(comment)
      last_panel = @visual.active_panel
      self.controller = TextEditorController.new(self, "; ", comment.content) do |content|
        @visual.active_panel = last_panel
        self.controller = nil
        if content != nil && content != "" then
          comment.content = content
          comment.save
        end
        if comment.content == "" then
          comment.delete
        end
        @visual.disassembly_panel.refresh
      end
    end
    
    def edit_flag(flag)
      last_panel = @visual.active_panel
      self.controller = TextEditorController.new(self, ": ", flag.name) do |content|
        @visual.active_panel = last_panel
        self.controller = nil
        if content != nil && content != "" then
          flag.name = content
          flag.save
        end
        if flag.name == "" then
          flag.delete
        end
        @visual.disassembly_panel.refresh
      end
    end

    def get_location(message)
      last_panel = @visual.active_panel
      self.controller = TextEditorController.new(self, message, "") do |content|
        @visual.active_panel = last_panel
        self.controller = nil
        if content != nil && content != "" then
          yield @visual.debugger_dsl.instance_eval(content).to_i
        end
      end
    end
    
    def are_you_sure(message, confirm=["y", "Y"])
      last_panel = @visual.active_panel
      self.controller = AreYouSureController.new(message, confirm) do |result|
        @visual.active_panel = last_panel
        self.controller = nil
        yield result
      end
    end

    def show_message(message)
      # don't grab focus
      @controller = MessageController.new(message, self) do
        self.controller = nil
      end
      refresh
      return @controller
    end

    def grab_focus(message)
      last_panel = @visual.active_panel
      self.controller = MessageController.new(message, self) do
        @visual.active_panel = last_panel
        self.controller = nil
      end
      return @controller
    end
    
    def controller=(controller)
      @controller = controller
      if controller != nil then
        @visual.active_panel = self
      end
      refresh
    end

    def handle_key(key)
      @controller.handle_key(key)
    end
  end

  class MessageController
    def initialize(message, minibuffer, &close_proc)
      @message = message
      @minibuffer = minibuffer
      @close_proc = close_proc
    end

    def content
      @message
    end

    def content=(msg)
      @message = msg
      @minibuffer.refresh
    end

    def cursor
      @message.length + 1
    end
    
    def close
      @close_proc.call
    end
  end
  
  class AreYouSureController
    def initialize(message, confirm, &result_proc)
      @message = message
      @confirm = confirm
      @result_proc = result_proc
    end

    def content
      @message + " "
    end

    def cursor
      @message.length + 1
    end

    def handle_key(key)
      @result_proc.call @confirm.include? key
    end
  end

  class TextEditorController
    def initialize(panel, prompt, initial_content="", &result_proc)
      @panel = panel
      @prompt = prompt
      @content = initial_content
      @result_proc = result_proc
      @cursor_pos = @content.length
    end

    @@kill_ring = ""
    
    def content
      @prompt + @content
    end

    def cursor
      @cursor_pos + @prompt.length
    end

    def handle_key(key)
      case key
      when 1 # ^A
        @cursor_pos = 0
      when 5 # ^E
        @cursor_pos = @content.length
      when 11 # ^K
        @@kill_ring = @content[@cursor_pos, @content.length]
        @content = @content[0, @cursor_pos]
      when 25 # ^Y
        @content = @content[0, @cursor_pos] + @@kill_ring + @content[@cursor_pos, @content.length]
        @cursor_pos+= @@kill_ring.length
      when 3 # ^C
        @result_proc.call(nil)
        return true
      when 127 # backspace
        if @cursor_pos > 0 then
          @content = @content[0, @cursor_pos-1] + @content[@cursor_pos, @content.length]
          @cursor_pos-= 1
        end
      when 330
        if @cursor_pos < @content.length then
          @content = @content[0, @cursor_pos] + @content[@cursor_pos+1, @content.length]
        end          
      when Curses::KEY_LEFT
        if @cursor_pos > 0 then
          @cursor_pos-= 1
        end
      when Curses::KEY_RIGHT
        if @cursor_pos < @content.length then
          @cursor_pos+= 1
        end
      when Curses::KEY_ENTER, 13
        @result_proc.call(@content)
        return true
      else
        if (32..126).include?(key.ord) then
          @content = @content[0, @cursor_pos] + key + @content[@cursor_pos, @content.length]
          @cursor_pos+= 1
        else
          return false
        end
      end
      @panel.refresh
      return true
    end
  end
end
