local deserializer = require("@self/deserializer")
local serializer = require("@self/serializer")

return {
	parse = deserializer,
	serialize = serializer.serialize,
    
	relocate_sections = serializer.relocate_sections,
	align = serializer.align,
	calculate_headers_size = serializer.calculate_headers_size,
}