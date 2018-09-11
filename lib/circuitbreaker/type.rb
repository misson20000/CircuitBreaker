module CircuitBreaker
  class Type
    def initialize(name, size)
      @name = name
      @size = size
      @address_point = 0
    end

    attr_accessor :name
    attr_reader :size
    attr_reader :address_point
    
    def is_pointer
      false
    end

    def is_supported_return_type?
      false
    end

    def argument_mode
      :unsupported
    end

    def typedef(name)
      td = self.dup
      td.name = name
      return td
    end

    def inspect
      name
    end

    def doc(indent=0)
      "#{name}(#{size} bytes)"
    end
  end

  class StructType < Type
    def initialize(name, &block)
      @name = "struct " + name.to_s
      @struct_name = name
      if block_given? then
        def_fields(&block)
      end
    end

    def def_fields(&block)
      dsl = StructDSL.new
      dsl.instance_eval &block
      
      @fields = dsl.fields
      @size = dsl.offset
      @address_point = dsl.get_address_point
      
      @class = Struct.new(*(@fields.map do |f|
                              f.name
                            end))
    end

    class Field
      def initialize(offset, type, name)
        @type = type
        @name = name
        @offset = offset
      end

      attr_reader :offset
      attr_reader :type
      attr_reader :name
    end
    
    class StructDSL
      def initialize
        @fields = []
        @offset = 0
        @address_point = @offset
      end

      def inherit(base)
        @fields += base.fields
        @offset = base.size
      end
      
      def field(type, name=nil)
        if name == nil then
          name = "field_" + @offset.to_s(16)
        end
        @fields.push Field.new(@offset, type, name)
        @offset+= type.size
      end
      
      def seek(offset)
        if offset < @offset then
          raise "can't seek backwards in struct"
        end
        @offset = offset
      end
      
      def address_point
        @address_point = @offset
      end
      
      attr_reader :fields
      attr_reader :offset
      
      def get_address_point
        @address_point
      end
    end

    def doc(indent=0)
      "struct #{name} {\n" + @fields.map do |f|
        ("  " * (indent+1)) + f.type.doc(indent+1) + " " + f.name + ";\n"
      end.join() + ("  " * indent) + "}"
    end

    def encode(value)
      @fields.map do |f|
        f.type.encode(value[f.name])
      end.join
    end

    def decode(switch, string)
      @class.new(
        *(@fields.map do |f|
            f.type.decode(switch, string[f.offset, f.offset + f.type.size])
          end))
    end

    attr_reader :fields
    attr_reader :class
  end

  class NumericType < Type
    def initialize(name, packing, size)
      super(name, size)
      @packing = packing
      @size = size
    end

    def encode(value)
      [value.to_i].pack(@packing)
    end

    def decode(switch, string)
      string.unpack(@packing)[0]
    end
    
    def coerce_to_argument(switch, value, finalizers)
      value
    end

    def coerce_from_return(switch, value)
      value
    end

    def argument_mode
      :integer
    end
    
    def is_supported_return_type?
      true
    end
  end

  class BooleanType < Type
    def initialize()
      super("bool", 1)
    end

    def encode(value)
      [value ? 1 : 0].pack("C")
    end

    def decode(switch, string)
      string.unpack("C")[0] > 0
    end

    def coerce_to_argument(switch, value, finalizers)
      value ? 1 : 0
    end

    def coerce_from_return(switch, value)
      value != 0
    end
    
    def is_supported_return_type?
      true
    end
    
    def argument_mode
      :integer
    end
  end
end
