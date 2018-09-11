require "cxxfilt"

module CircuitBreaker
  module Faron
    module Elf
      module DT
        NULL = 0
        NEEDED = 1
        PLTRELSZ = 2
        PLTGOT = 3
        HASH = 4
        STRTAB = 5
        SYMTAB = 6
        RELA = 7
        RELASZ = 8
        RELAENT = 9
        STRSZ = 10
        SYMENT = 11
        # 12-15
        SYMBOLIC = 16
        REL = 17
        RELSZ = 18
        RELENT = 19
        PLTREL = 20
        # 21-22
        JMPREL = 23
        # 24
        INIT_ARRAY = 25
        FINI_ARRAY = 26
        INIT_ARRAYSZ = 27
        FINI_ARRAYSZ = 28
        FLAGS = 30
        GNU_HASH = 0x6ffffef5
        RELACOUNT = 0x6ffffff9
      end

      class DynamicSegment
        EntryStruct = StructType.new("Elf_Dyn")
        EntryStruct.def_fields do
          field Types::Uint64, :tag
          field Types::Uint64, :value
        end
        class Entry
          def initialize(seg, struct)
            @seg = seg
            @struct = struct
          end
          def value
            @struct.value
          end
          def ptr
            @seg.module_base + value
          end
        end

        SymbolStruct = StructType.new("Elf_Symbol")
        SymbolStruct.def_fields do
          field Types::Uint32, :st_name
          field Types::Uint8, :st_info
          field Types::Uint8, :st_other
          field Types::Uint16, :st_shndx
          field Types::Uint64, :st_value
          field Types::Uint64, :st_size
        end
        class Symbol
          def initialize(seg, info)
            @seg = seg
            @info = info
          end
          def name
            (@seg[Elf::DT::STRTAB].ptr + @info.st_name).read(1024).unpack("Z1024")[0]
          end
          def demangled_name
            CXXFilt::demangle(name)
          end
          def pointer
            @seg.module_base + @info.st_value
          end
          def addr
            @seg.module_base.to_i + @info.st_value
          end
        end

        RelaStruct = StructType.new("Elf_Rela")
        RelaStruct.def_fields do
          field Types::Uint64, :offset
          field Types::Uint32, :unimportant1
          field Types::Uint32, :unimportant2
          field Types::Uint64, :addend
        end
        
        def initialize(module_base, dynamic)
          @module_base = module_base
          @dynamic = dynamic
          @entries = []

          ptr = dynamic.cast(EntryStruct)
          loop do
            dyn = ptr.deref
            if dyn.tag == Elf::DT::NULL then
              break
            end
            @entries.push(dyn)
            ptr+= 1
          end
        end

        attr_reader :module_base, :entries
        
        def [](tag)
          return Entry.new(self, @entries.find do |entry|
                             entry.tag == tag
                           end)
        end

        def nchain
          return self[Elf::DT::HASH].ptr.cast(Types::Uint32)[1]
        end

        def sym(i)
          info = self[Elf::DT::SYMTAB].ptr.cast(SymbolStruct)[i]
          return Symbol.new(self, info)
        end
      end
    end
  end
end
