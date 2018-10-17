require_relative "elf.rb"
require_relative "breakpoint.rb"
require_relative "../standard_switch.rb"

require "crabstone"

module CircuitBreaker
  module Faron
    class Backend
      def initialize(filename)
        @elf = Elf::ElfView.new(filename)
      end

      def read(pointer, offset, length, &block)
        @elf.read(pointer.to_i + offset, length)
      end

      def write(pointer, offset, data)
        raise "read-only backend"
      end

      def memory_permissions(pointer)
      end

      def malloc(size)
        raise "read-only backend"
      end

      def free(pointer)
        raise "read-only backend"
      end

      def name
        "faron"
      end

      def memory_permissions(addr)
        @elf.segments.each do |seg|
          if seg.type != Elf::PT::LOAD then
            next
          end
          if seg.contains?(addr) then
            p = 0
            if seg.flags & 0x4 then
              p|= 1
            end
            if seg.flags & 0x2 then
              p|= 2
            end
            if seg.flags & 0x1 then
              p|= 4
            end
            return p
          end
        end
        return 0
      end

      def nsos(dsl)
        @nsos ||= 
          @elf.notes.select do |note|
          note.name == "Twili" && note.type == 6482
        end.map do |note|
          addr, size = note.desc.unpack("Q<Q<")
          Nso.new(dsl.make_pointer(addr), size, note.desc[16, note.desc.size-16])
        end
      end

      def threads
        []
      end
      
      attr_reader :elf
    end

    class Nso
      S_TABLE_REGEX = /nn::sf::cmif::server::detail::CmifProcessFunctionTableGetter<([a-zA-Z0-9:]+), void>::s_Table/

      def initialize(base, size, build_id)
        @base = base
        @size = size
        @build_id = build_id

        mod_ptr = base + base.cast(Types::Uint32)[1]
        @mod_header = mod_ptr.cast(Types::ModuleHeader).deref
        if @mod_header.magic != "MOD0".unpack("L<")[0] then
          raise "invalid module header"
        end
        @dynamic = Elf::DynamicSegment.new(base, mod_ptr + @mod_header.dynamic_offset)

        @symbols = {}
        @reverse_symbols = {}
        @s_tables = {}
        @relocation_targets = []
        @dynamic.nchain.times do |i|
          sym = @dynamic.sym(i)
          if sym.demangled_name != nil then
            @symbols[sym.demangled_name] = sym
            @reverse_symbols[sym.addr] = sym
          end
          S_TABLE_REGEX.match(sym.demangled_name) do |m|
            @s_tables[m[1]] = sym.pointer
          end
        end
        (0...@dynamic[Elf::DT::RELASZ].value).step(0x18) do |offset|
          rela = (@dynamic[Elf::DT::RELA].ptr + offset).cast(Elf::DynamicSegment::RelaStruct).deref
          @relocation_targets.push(base + rela.offset)
        end
      end

      def service_object_info
        @service_object_info||= find_service_object_info
      end

      class ServiceObject
        def initialize(object_ptr, s_table_name)
          @object_ptr = object_ptr
          @s_table_name = s_table_name
        end
        attr_reader :object_ptr, :s_table_name
      end
      
      def find_service_object_info
        hits = []
        if @base.switch.backend.name == "faron" then # we subvert circuitbreaker APIs here for speed...
          @base.switch.backend.elf.segments.each do |seg|
            if seg.type != Elf::PT::LOAD then
              next
            end
            if seg.flags != 0x6 then # only RW
              next
            end
            (0...seg.memsz).step(8) do |off|
              compare = seg.read(off, 8).unpack("Q<")[0]
              ptr = @base.switch.make_pointer(seg.vaddr + off)
              @s_tables.each_pair do |name, s_table|
                if compare != s_table then next end
                if @relocation_targets.include?(ptr) then
                  next # we're in .got
                end
                if !ptr.between?(base, base + size) then
                  next # we're not interested in hits outside of .bss
                end
                server_object_info = (ptr-8).read(16).unpack("Q<Q<")
                hits.push(ServiceObject.new((ptr-8).cast(Types::Void.pointer).deref, name))
              end
            end
          end
        else
          raise "nyi"
        end
        return hits
      end
      
      attr_reader :base
      attr_reader :size
      attr_reader :dynamic
      attr_reader :relocation_targets
      attr_reader :symbols
      attr_reader :reverse_symbols
      attr_reader :s_tables
      attr_reader :build_id
    end
    
    class InteractiveDSL < InteractiveDSL
      def initialize(backend)
        super(backend)
        @cs = Crabstone::Disassembler.new(Crabstone::ARCH_ARM64, Crabstone::MODE_ARM)
      end
      
      def nsos
        backend.nsos(self)
      end

      def symbols
      end

      def hexedit_highlighters
        return [
          lambda do
            nsos.map do |nso|
              nso.symbols.each_pair.select do |pair|
                pair[0].start_with? "vtable"
              end.map do |pair|
                Visual::MemoryEditorPanel::Highlight.new(pair[0], pair[1].addr + 16, :reg, true)
              end
            end.flatten(1)
          end
        ]
      end

      def list_threads
        backend.threads.each_pair do |id, thread|
          ctx = thread.context
          tls_ctx = (make_pointer(thread.tls) + 0x1f8).cast(Types::Void.pointer).deref
          if tls_ctx != 0 then
            name_ptr = (tls_ctx + 0x1a8).cast(Types::Char.pointer).deref
            if name_ptr != 0 then
              name = name_ptr.read(0x20).unpack("Z*")[0]
            else
              name = (tls_ctx + 0x188).read(0x20).unpack("Z*")[0]
            end
          else
            name = ""
          end
          insn = @cs.disasm(make_pointer(ctx.pc).read(4), ctx.pc)[0]
          insn_str = "#{insn.mnemonic} #{insn.op_str}"
          puts "[#{id.to_s(16).ljust(8)}] Thread #{("'" + name + "'").ljust(0x22)}: 0x#{ctx.pc.to_s(16).rjust(16, "0")}: #{insn_str}"
        end
        nil
      end

      def breakpoint(ptr)
        Breakpoint.new(make_pointer(ptr))
      end
      
      attr_reader :backend
    end
  end
end
