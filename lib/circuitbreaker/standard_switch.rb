require_relative "./result.rb"
require_relative "./dsl.rb"

module CircuitBreaker
  module Types
    Handle = Types::Uint32.typedef("Handle")
    SessionHandle = Types::Handle.typedef("SessionHandle")
    ModuleHeader = StructType.new("ModuleHeader")

    ModuleHeader.def_fields do
      field Types::Uint32, :magic
      field Types::Uint32, :dynamic_offset
      field Types::Uint32, :bss_start_offset
      field Types::Uint32, :bss_end_offset
      field Types::Uint32, :eh_frame_hdr_start_offset
      field Types::Uint32, :eh_frame_hdr_end_offset
      field Types::Uint32, :runtime_module
    end
  end
end
