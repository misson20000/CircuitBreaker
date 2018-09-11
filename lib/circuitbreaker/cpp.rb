require "cxxfilt"

module Types
  VTable = StructType.new("VTable")
  RTTI = StructType.new("RuntimeTypeInfo")
  
  VTable.def_fields do
    field RTTI.pointer, "rtti"
    field Types::Uint64, "this_offset"
    address_point
  end  
  RTTI.def_fields do
    field VTable.pointer, "vtable"
    field Types::Char.pointer, :name
  end
end
