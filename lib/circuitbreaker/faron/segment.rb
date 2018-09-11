module CircuitBreaker
  module Faron
    module Elf
      class Segment
        def initialize(file, phdr)
          @file = file
          @phdr = phdr
        end

        def type
          @phdr[:p_type]
        end

        def vaddr
          @phdr[:p_vaddr]
        end

        def paddr
          @phdr[:p_paddr]
        end

        def filesz
          @phdr[:p_filesz]
        end

        def memsz
          @phdr[:p_memsz]
        end

        def flags
          @phdr[:p_flags]
        end

        def align
          @phdr[:p_align]
        end

        def contains?(addr)
          return addr >= vaddr && ((addr - vaddr) < memsz)
        end
        
        def read(offset, size)
          if offset >= filesz then
            return 0.chr * size
          else
            @file.pos = @phdr[:p_offset] + offset
            unsafe_size = offset + size - filesz
            if unsafe_size > 0 then
              return @file.read(filesz - offset) + (0.chr * unsafe_size)
            else
              return @file.read(size)
            end
          end
        end
      end
    end
  end
end
