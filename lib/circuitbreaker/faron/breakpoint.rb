require_relative "../standard_switch.rb"

module CircuitBreaker
  module Faron
    class Breakpoint
      def initialize(ptr)
        @ptr = ptr.cast(Types::Uint32)
        @orig_insn = @ptr.deref
        install
      end
      def install
        @ptr.deref = 0xd4200000
      end
      def uninstall
        @ptr.deref = @orig_insn
      end
    end
  end
end
