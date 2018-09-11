require "curses"

module Visual
  class Panel
    def initialize
      @window = Curses::Window.new(0, 0, 0, 0)
      @window.keypad = true
    end

    attr_reader :window
    
    def redo_layout(miny, minx, maxy, maxx, parent=nil)
      @window.resize(maxy-miny, maxx-minx)
      @window.move(miny, minx)
      @width = maxx-minx
      @height = maxy-miny
      @parent = parent
    end

    def border_content
      ""
    end

    def handle_key(key)
    end
    
    def refresh
      @window.refresh
      if @parent then
        @parent.update_border
      end
    end
  end
end
