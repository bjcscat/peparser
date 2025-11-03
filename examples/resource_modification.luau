local fs = require("@lute/fs")
local peparser = require("@peparser")

local file = buffer.fromstring(fs.readasync("myapp.exe"))
local image = peparser.image.parse(file)

local resources = peparser.resources.from_image(image)
if resources then
	peparser.resources.ensure_path(resources, { 1, 2, 3 }, buffer.fromstring("Hello! This is a resource!"))
end
image = peparser.resources.to_image(image, resources)
