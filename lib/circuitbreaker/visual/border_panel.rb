module Visual
  class BorderPanel
    def initialize(dir)
      @window = Curses::Window.new(0, 0, 0, 0)
      @dir = dir
    end

    attr_reader :content

    def content=(content)
      @content = content
      self.refresh
    end
    
    def redo_layout(miny, minx, maxy, maxx)
      @window.resize(maxy-miny, maxx-minx)
      @window.move(miny, minx)
      @width = maxx-minx
      @height = maxy-miny
      self.refresh
    end

    def refresh
      @window.attron(Curses::color_pair(ColorPairs::Border))
      @height.times do |y|
        @window.setpos(y, 0)
        @window.addstr(@content || {:horiz => "-", :vert => "|"}[@dir] * (@width))
      end
      @window.attroff(Curses::color_pair(ColorPairs::Border))
      @window.refresh
    end
  end
end
