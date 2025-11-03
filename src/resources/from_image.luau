local types = require("../types")
local deserializer = require("./deserializer")

type Image = types.Image
type ResourceNode = types.ResourceNode

local function from_image(image: Image): ResourceNode?
	local resource_dir = image.data_directories.resource_table
	
	if not resource_dir then
		return nil
	end
	
	if resource_dir.size == 0 then
		return nil
	end
	
	local source = image.source
	if not source then
		error("Image must have source buffer to extract resources")
	end
	
	return deserializer(source, resource_dir.virtual_address, resource_dir.size, image.sections)
end

return from_image
