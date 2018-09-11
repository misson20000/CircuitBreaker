require_relative "border_panel.rb"

module Visual
  class BSPLayout
    def initialize(options, a, b)
      @options = options
      if !options[:dir] then
        raise "no direction specified"
      end
      
      @mode = nil
      if @options[:fixed_item] then
        if @mode != nil then
          raise "multiple mode specifiers"
        end
        @mode = :fixed
      end
      if @mode == nil then
        raise "must specify a mode"
      end
      
      @a = a
      @b = b
      @border = BorderPanel.new({:horiz => :vert, :vert => :horiz}[options[:dir]])
    end

    def border_content
      if @options[:dir] == :vert then
        return @b.border_content
      else
        return (@a.border_content.ljust(a_width, "-") + "|" + @b.border_content).ljust(@maxx-@minx, "-")
      end
    end

    def a_width
      if @mode == :fixed then
        if @options[:fixed_item] == :a then
          return @options[:fixed_size]
        else
          return @maxx-@options[:fixed_size]-1-@minx
        end
      end
    end

    def a_height
      if @mode == :fixed then
        if @options[:fixed_item] == :a then
          return @options[:fixed_size]
        else
          return @maxy-@options[:fixed_size]-1-@miny
        end
      end
    end

    def redo_layout(miny, minx, maxy, maxx, parent=nil)
      @miny = miny
      @minx = minx
      @maxy = maxy
      @maxx = maxx
      @parent = parent
      if @options[:dir] == :vert then
        @border.redo_layout(miny+a_height, minx, miny+a_height+1, maxx)
        @a.redo_layout(miny, minx, miny+a_height, maxx, self)
        @b.redo_layout(miny+a_height+1, minx, maxy, maxx, self)
      elsif @options[:dir] == :horiz then
        @border.redo_layout(miny, minx+a_width, maxy, minx+a_width+1)
        @a.redo_layout(miny, minx, maxy, minx+a_width, self)
        @b.redo_layout(miny, minx+a_width+1, maxy, maxx, self)
      end
    end

    def update_border
      if @options[:dir] == :vert then
        @border.content = @a.border_content.ljust(@maxx-@minx, "-")
      else
        if @parent then
          @parent.update_border
        end
      end
    end
    
    def refresh
      @a.refresh
      @b.refresh
      @border.refresh
    end
  end
end
