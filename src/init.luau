local types = require("@self/types")

return {
	DATA_DIRECTORIES = types.DATA_DIRECTORIES,

	image = require("@self/pe_image"),
	resources = require("@self/resources"),
}
