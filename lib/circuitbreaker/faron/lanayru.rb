require "twib"

module CircuitBreaker
  module Lanayru
    class Thread
      class Context
        class GPRAccessor
          def initialize(ctx)
            @ctx = ctx
          end
          def [](index)
            @ctx.registers[index]
          end
          def []=(index, value)
            @ctx.registers[index] = value.to_i
          end
        end
        def initialize(registers)
          @registers = registers
        end

        {"fp" => 29, "lr" => 30, "sp" => 31, "pc" => 32, "psr" => 31}.each_pair do |name, index|
          define_method(name) do
            @registers[index]
          end
          define_method(name + "=") do |value|
            @registers[index] = value.to_i
          end
        end
        
        def x
          GPRAccessor.new(self)
        end
      end
      
      def initialize(backend, id, tls, entrypoint)
        @backend = backend
        @id = id
        @tls = tls
        @entrypoint = entrypoint
      end

      attr_reader :id, :tls, :entrypoint
      
      def context
        Context.new(@backend.debugger.get_thread_context(@id).unpack("Q<*"))
      end
    end
    
    class Backend
      def initialize(pid)
        @pid = pid
        tc = Twib::TwibConnection.connect_unix
        itdi = tc.open_device(tc.list_devices[0]["device_id"])
        @debugger = itdi.open_active_debugger(pid)
        @threads = {}
        @continue_required = false
        
        event_loop
      end

      def event_loop
        while event = @debugger.get_debug_event do
          handle_event(event)
        end
        #@debugger.continue_debug_event(7)
        @debugger.wait_event_async do
          event_loop
        end
      end

      def handle_event(event)
        if (event.flags & 1) != 0 then
          @continue_required = true
        end
        case event.event_type
        when :attach_process
          puts "Attach Process:"
          puts "  Title ID: " + event.title_id.to_s(16).rjust(16, "0")
          puts "  Process ID: 0x" + event.process_id.to_s(16)
          puts "  Process Name: " + event.process_name
          puts "  MMU Flags: 0x" + event.mmu_flags.to_s(16)
        when :attach_thread
          puts "Attach Thread:"
          puts "  Thread ID: 0x" + event.thread_id.to_s(16)
          puts "  TLS: 0x" + event.tls.to_s(16)
          puts "  Entrypoint: 0x" + event.entrypoint.to_s(16)
          @threads[event.thread_id] = Thread.new(self, event.thread_id, event.tls, event.entrypoint)
        when :exit_process
          puts "Exit Process"
        when :exit_thread
          puts "Exit Thread"
          @threads.delete(event.thread_id)
        when :exception
          puts "Exception"
        end
      end

      def read(pointer, offset, length, &block)
        @debugger.read_memory(pointer.to_i + offset, length)
      end

      def write(pointer, offset, data)
        @debugger.write_memory(pointer.to_i + offset, data)
      end

      def memory_permissions(addr)
        @debugger.query_memory(addr)[:permission]
      end

      def malloc(size)
        raise "unsupported op: malloc"
      end

      def free(pointer)
        raise "unsupported op: free"
      end

      def name
        "lanayru"
      end

      def nsos(dsl)
        @nsos||= @debugger.get_nso_infos.map do |info|
          Faron::Nso.new(dsl.make_pointer(info[:base]), info[:size], info[:build_id])
        end
      end

      attr_reader :debugger
      attr_reader :threads
    end
  end
end
