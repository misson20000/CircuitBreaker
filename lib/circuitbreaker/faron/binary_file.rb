module CircuitBreaker
  module Faron
    class BinaryFile
      def initialize(file)
        @file = file
        @endianness = :little
        @word_size = :u8
      end

      attr_reader :file
      attr_accessor :endianness, :word_size
      
      def endian_suffix
        {:little => "<", :big => ">"}[@endianness]
      end

      def read_u8
        @file.read(1).unpack("C")[0]
      end

      def read_u16
        @file.read(2).unpack("S" + endian_suffix)[0]
      end

      def read_u32
        @file.read(4).unpack("L" + endian_suffix)[0]
      end

      def read_u64
        @file.read(8).unpack("Q" + endian_suffix)[0]
      end

      def read_uword
        case @word_size
        when :u8
          read_u8
        when :u16
          read_u16
        when :u32
          read_u32
        when :u64
          read_u64
        end
      end

      def read(n)
        @file.read(n)
      end

      def pos
        @file.pos
      end

      def pos=(n)
        @file.pos = n
      end
    end
  end
end
