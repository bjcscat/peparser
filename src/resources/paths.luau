local types = require("../types")

type ResourceNode = types.ResourceNode
type ResourceId = types.ResourceId

-- TODO: languages

-- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-loadresourcea
local RESOURCE_TYPES = {
	CURSOR = 1, -- Hardware-dependent cursor resource
	BITMAP = 2, -- Bitmap resource
	ICON = 3, -- Hardware-dependent icon resource
	MENU = 4, -- Menu resource
	DIALOG = 5, -- Dialog box
	STRING = 6, -- String-table entry
	FONTDIR = 7, -- Font directory resource
	FONT = 8, -- Font resource
	ACCELERATOR = 9, -- Accelerator table
	RCDATA = 10, -- Application-defined resource (raw data)
	MESSAGETABLE = 11, -- Message-table entry
	GROUP_CURSOR = 12, -- Hardware-independent cursor resource
	GROUP_ICON = 14, -- Hardware-independent icon resource
	VERSION = 16, -- Version resource
	DLGINCLUDE = 17, -- Allows a resource editing tool to associate a string with an .rc file
	PLUGPLAY = 19, -- Plug and Play resource
	VXD = 20, -- VXD resource
	ANICURSOR = 21, -- Animated cursor
	ANIICON = 22, -- Animated icon
	HTML = 23, -- HTML resource
	MANIFEST = 24, -- Side-by-Side Assembly Manifest
}

local function make_path(resource_type: number, id: ResourceId, language: number?): { ResourceId }
	return { resource_type, id, language or 0 }
end

return {
	TYPES = RESOURCE_TYPES,

	make_path = make_path,
}
