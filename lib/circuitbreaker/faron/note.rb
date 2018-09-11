module CircuitBreaker
  module Faron
    module Elf
      class Note
        def initialize(type, name, desc)
          @type = type
          @name = name
          @desc = desc
        end
        
        attr_reader :type, :name, :desc
      end
    end
  end
end
