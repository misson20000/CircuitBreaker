require "stringio"

require_relative "binary_file.rb"
require_relative "segment.rb"
require_relative "note.rb"
require_relative "dynamic.rb"

module CircuitBreaker
  module Faron
    module Elf
      module PT
        NULL = 0
        LOAD = 1
        DYNAMIC = 2
        INTERP = 3
        NOTE = 4
        SHLIB = 5
        PHDR = 6
      end
      
      class ElfView  
        def initialize(path)
          @bf = BinaryFile.new(File.open(path, "rb"))
          
          magic = @bf.read(4)
          if magic != "\x7fELF" then
            raise "Invalid ELF magic number"
          end
          
          @ehdr = {}
          
          @ehdr[:ei_class] = @bf.read_u8
          @bf.word_size = [nil, :u32, :u64][@ehdr[:ei_class]]
          
          @ehdr[:ei_data] = @bf.read_u8
          @bf.endianness = [nil, :little, :big][@ehdr[:ei_data]]
          
          @ehdr[:ei_version] = @bf.read_u8
          @ehdr[:ei_osabi] = @bf.read_u8
          @ehdr[:ei_abiversion] = @bf.read_u8
          @bf.read(7) # skip padding
          @ehdr[:e_type] = @bf.read_u16
          @ehdr[:e_machine] = @bf.read_u16
          @ehdr[:e_version] = @bf.read_u32
          @ehdr[:e_entry] = @bf.read_uword
          @ehdr[:e_phoff] = @bf.read_uword
          @ehdr[:e_shoff] = @bf.read_uword
          @ehdr[:e_flags] = @bf.read_u32
          @ehdr[:e_ehsize] = @bf.read_u16
          @ehdr[:e_phentsize] = @bf.read_u16
          @ehdr[:e_phnum] = @bf.read_u16
          @ehdr[:e_shentsize] = @bf.read_u16
          @ehdr[:e_shnum] = @bf.read_u16
          @ehdr[:e_shstrndx] = @bf.read_u16
          
          if @bf.pos != @ehdr[:e_ehsize] then
            raise "Invalid EHDR size: expected #{@bf.pos}, got #{@ehdr[:e_ehsize]}"
          end
          
          @bf.pos = @ehdr[:e_phoff]
          @segments = @ehdr[:e_phnum].times.map do
            phdr = {}
            phdr[:p_type] = @bf.read_u32
            phdr[:p_flags] = @bf.read_u32 if @ehdr[:ei_class] == 2
            phdr[:p_offset] = @bf.read_uword
            phdr[:p_vaddr] = @bf.read_uword
            phdr[:p_paddr] = @bf.read_uword
            phdr[:p_filesz] = @bf.read_uword
            phdr[:p_memsz] = @bf.read_uword
            phdr[:p_flags] = @bf.read_u32 if @ehdr[:ei_class] == 1
            phdr[:p_align] = @bf.read_uword
            next Elf::Segment.new(@bf.file, phdr)
          end
          
          @notes = []
          @segments.each do |seg|
            if seg.type != PT::NOTE then
              next
            end
            io = StringIO.new(seg.read(0, seg.filesz))
            while io.pos < seg.filesz do
              namesz = io.read(4).unpack("L<")[0]
              descsz = io.read(4).unpack("L<")[0]
              type = io.read(4).unpack("L<")[0]
              name = io.read(namesz)
              io.read((4 - (namesz % 4)) % 4) # align to 4 bytes
              desc = io.read(descsz)
              io.read((4 - (descsz % 4)) % 4) # align to 4 bytes
              
              @notes.push(Elf::Note.new(type, name, desc))
            end
          end
        end

        def read(addr, size)
          @segments.each do |seg|
            if seg.type != PT::LOAD then
              next
            end
            if seg.contains?(addr) then
              offset = addr - seg.vaddr
              available_size = seg.memsz - offset
              safe_size = [size, available_size].min
              str = seg.read(offset, safe_size)
              if safe_size < size then
                return str + read(addr + safe_size, size - safe_size)
              else
                return str
              end
            end
          end
          raise "no segment contains address: 0x#{addr.to_s(16)}"
        end

        def read_u8(addr)
          read(addr, 1).unpack("C")[0]
        end

        def read_u16(addr)
          read(addr, 2).unpack("S<")[0]
        end
        
        def read_u32(addr)
          read(addr, 4).unpack("L<")[0]
        end

        def read_u64(addr)
          read(addr, 8).unpack("Q<")[0]
        end

        def search(string, alignment, flags=nil, type=PT::LOAD)
          hits = []
          @segments.each do |seg|
            if type && seg.type != type then
              next
            end
            if flags && seg.flags != flags then
              next
            end
            (0...seg.memsz).step(alignment) do |off|
              if seg.read(off, string.length) == string then
                hits.push seg.vaddr + off
              end
            end
          end
          return hits
        end

        def hexdump(prefix, addr, size)
          data = read(addr, size).bytes
          (0...size).step(0x10) do |row_offset|
            string = prefix + "0x#{(addr + row_offset).to_s(16)} "
            (row_offset...[row_offset+0x10,size].min).each do |offset|
              if (offset % 8) == 0 then
                string+= " "
              end
              string+= data[offset].to_s(16).rjust(2, "0") + " "
            end
            puts string
          end
        end
        
        attr_reader :notes, :segments
      end
    end
  end
end
