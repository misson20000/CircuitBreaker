module CircuitBreaker
  class FunctionPointer
    def initialize(switch, pointer, return_type, argument_types)
      @switch = switch
      @pointer = pointer
      @return_type = return_type
      @argument_types = argument_types

      if !@return_type.is_supported_return_type? then
        raise "unsupported return type '" + @return_type.name + "'"
      end

      @argument_types.each do |type|
        if type.argument_mode == :unsupported then
          raise "unsupported argument type '" + type.name + "'"
        end
      end

      @argument_names = []
    end

    def inspect
      @return_type.name + " (*)(" + @argument_types.map do |arg|
        arg.name
      end.join(", ") + ") = 0x" + @pointer.value.to_s(16)
    end
    
    def call(*args)
      _call(args, true)
    end

    def start(*args)
      _call(args, false)
    end

    def _call(args, start_immediately)
      if args.length != @argument_types.length then
        raise "argument length mismatch (expected #{@argument_types.length}, got #{args.length}"
      end

      puts "call"
      
      finalizers = []
      
      values = @argument_types.zip(args).map do |pair|
        puts "coerce a"
        [pair[0], pair[0].coerce_to_argument(@switch, pair[1], finalizers)]
      end.group_by do |pair|
        pair[0].argument_mode
      end
      puts "done coercing"
      
      int_values = (values[:integer] || []).map do |v| v[1] end
      float_values = (values[:float] || []).map do |v| v[1] end

      if start_immediately then
        retV = @switch.call(@pointer, int_values, [], float_values)
      else
        retV = @switch.start(@pointer, int_values, [], float_values)
      end
      
      finalizers.each do |f|
        f.call
      end
      
      return @return_type.coerce_from_return(@switch, retV)
    end

    def set_names(*names)
      @argument_names = names
      return self
    end

    def doc
      @return_type.name + " (*)(" + @argument_types.zip(@argument_names).map do |arg|
        arg[0].name + " " + arg[1]
      end.join(", ") + ")"
    end
    
    def to_ptr
      @pointer
    end
  end
end
