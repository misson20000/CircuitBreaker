module CircuitBreaker
  class Type
    def pointer
      @pointerType||= PointerType.new(self)
    end
  end

  class PointerType < Type
    def initialize(pointedType)
      super(pointedType.name + "*", 8)
      @pointedType = pointedType
    end
    
    def decode(switch, val)
      Pointer.new(switch, val.unpack("Q<")[0], @pointedType)
    end

    def encode(val)
      [val.to_i].pack("Q<")
    end

    def is_pointer
      true
    end

    def is_supported_return_type?
      true
    end

    def argument_mode
      :integer
    end

    def coerce_to_argument(switch, value, finalizer_list)
      if @pointedType == Types::Char && value.is_a?(String) then
        puts "malloc"
        buf = switch.malloc(value.length + 1)
        puts "done"
        buf.cast! Types::Char
        buf.write(value + 0.chr)
        puts "wrote"
        finalizer_list.push(proc do
                              switch.free buf
                            end)
        return buf.value
      end
      if value.is_a? Array then
        buf = switch.malloc(value.length * @pointedType.size)

        buf.cast! @pointedType
        value.each_with_index do |item, i|
          buf[i] = item
        end
        finalizer_list.push(proc do
                              value.length.times do |i|
                                value[i] = buf[i]
                              end
                              @switch.free buf
                            end)
        return buf.value
      end
      if value == nil then
        return 0
      end
      value.value
    end

    def coerce_from_return(switch, value)
      Pointer.new(switch, value).cast!(@pointedType)
    end
  end

  class Pointer
    def initialize(switch, value, targetType = Types::Void)
      @switch = switch
      @value = value
      @targetType = targetType
    end

    attr_accessor :switch
    attr_accessor :value
    
    def self.from_switch(switch, arr)
      puts "deprecated"
      return self.new(switch, arr.pack("L<L<").unpack("Q<")[0])
    end
    
    def to_switch(offset=0)
      puts "deprecated"
      [@value + offset].pack("Q<").unpack("L<L<")
    end

    def read(length, offset=0, &block)
      @switch.read(self, offset, length, &block)
    end

    def write(data, offset=0)
      @switch.write(self, offset, data)
      nil
    end

    def io
      return PointerIO.new(self)
    end
    
    def cast(targetType)
      return Pointer.new(@switch, @value, targetType)
    end

    def cast!(targetType)
      @targetType = targetType
      return self
    end
    
    def [](i)
      if @targetType.size > 0 then
        return @targetType.decode(@switch, read(@targetType.size, (i * @targetType.size) - @targetType.address_point))
      else
        raise "Cannot index void*"
      end
    end

    def []=(i, val)
      if @targetType != nil then
        write(@targetType.encode(val), (i * @targetType.size) - @targetType.address_point)
      else
        raise "Cannot index void*"
      end
    end

    def member_ptr(memberName)
      if @targetType.is_a? StructType then
        field = @targetType.fields.find do |f|
          f.name == memberName
        end
        if !field then
          raise "No such field in target " + @targetType.inspect
        end
        return Pointer.new(@switch, @value + field.offset - @targetType.address_point, field.type)
      else
        raise "Not a struct pointer"
      end
    end

    def arrow(memberName)
      member_ptr(memberName).deref
    end

    def assign(member, value)
      member_ptr(member).deref = value
    end

    def deref
      self[0]
    end
    
    def deref=(num)
      self[0] = num
    end
    
    # create function pointer
    def bridge(return_type, *argument_types)
      return FunctionPointer.new(@switch, self, return_type, argument_types)
    end

    def to_i
      @value
    end
    
    def +(off)
      return Pointer.new(@switch, @value + (off * (@targetType.size == 0 ? 1 : @targetType.size)), @targetType)
    end

    def -(off)
      if off.is_a? Pointer then
        return @value - off.value
      else
        return self + (-off)
      end
    end

    include Comparable
    
    def <=>(other)
      self.to_i <=> other.to_i
    end
    
    def succ
      return self + (@targetType.size == 0 ? 1 : @targetType.size)
    end
    
    def inspect
      result = @targetType.name + "* (#{@switch.name}) = 0x" + @value.to_s(16)
      if @targetType == Types::Char && @switch.arb_reads_safe then
        if @value != 0 then
          begin
            str = read(512)
            if str.include?(0.chr) then
              result+= " \"" + str.unpack("Z*")[0] + "\""
            end
          rescue
          end
        end
      end
      return result
    end

    def is_null_ptr?
      @value == 0
    end

    def free
      @switch.free self
      nil
    end

    def hexedit
      @switch.hexedit self
    end
    
    attr_reader :targetType
  end

  class PointerIO
    def initialize(pointer)
      @pos = pointer.value
      @switch = pointer.switch
      @mut_ptr = Pointer.new(@switch, 0)
    end
    
    def read(num)
      @mut_ptr.value = @pos
      @pos+= num
      return @mut_ptr.read(num)
    end

    def write(str)
      @mut_ptr.value = @pos
      @pos+= str.length
      return @mut_ptr.write(str)
    end

    attr_accessor :pos
  end
end
