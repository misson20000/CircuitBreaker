require_relative "type.rb"
require_relative "pointer.rb"
require_relative "functionpointer.rb"

module CircuitBreaker
  module Types
    Void		= NumericType.new("void",    "C",  1)
    Char		= NumericType.new("char",    "C",  1)
    Uint8		= NumericType.new("uint8",   "C",  1)
    Uint16	= NumericType.new("uint16",  "S<", 2)
    Uint32	= NumericType.new("uint32",  "L<", 4)
    Uint64	= NumericType.new("uint64",  "Q<", 8)
    Int8		= NumericType.new("int8",    "c",  1)
    Int16		= NumericType.new("int16",   "s<", 2)
    Int32		= NumericType.new("int32",   "l<", 4)
    Int64		= NumericType.new("int64",   "q<", 8)
    Float64	= NumericType.new("float32", "E",  8)
    Bool		= BooleanType.new

    class << Float64
      def coerce_to_argument(value)
        [value].pack("E").unpack("L<L<")
      end
      
      def coerce_from_return(switch, pair)
        pair.pack("L<L<").unpack("E")[0]
      end
    end
    
    class << Void
      def is_supported_return_type?
        true
      end
    end
  end

  class InteractiveDSL
    def initialize(backend)
      @backend = backend
    end
        
    def malloc(size)
      @backend.malloc(size)
    end

    def read(pointer, offset, length, &block)
      @backend.read(pointer, offset, length, &block)
    end

    def write(pointer, offset, data)
      @backend.write(pointer, offset, data)
    end

    def name
      @backend.name
    end

    def memory_permissions(addr)
      @backend.memory_permissions(addr)
    end
    
    def new(type, count=1)
      @backend.malloc(type.size * count).cast!(type)
    end

    def make_pointer(addr)
      Pointer.new(self, addr)
    end
    
    def nullptr
      make_pointer(0)
    end
    
    def string_buf(string)
      buf = malloc(string.length + 1)
      buf.cast! Types::Char
      buf.write(string)
      buf[string.length] = 0
      return buf
    end
    
    def free(pointer)
      @backend.free(pointer)
    end

    def hexedit(loc)
      require_relative "visual/visual.rb"
      memio = SynchronousMemoryInterface.new(self)
      memio.open do
        Visual::Mode.standalone do |vism|
          Visual::MemoryEditorPanel.new(vism, loc.to_i, hexedit_highlighters, memio)
        end
      end
    end

    def hexedit_highlighters
      []
    end
  end
end
