local image_builder = require("@self/image_builder")
local parser = require("@self/parser")
local resource_utils = require("@self/resource_utils")
local serializer = require("@self/serializer")
local types = require("@self/types")

export type Image = types.Image
export type Section = types.Section
export type NTHeaders = types.NTHeaders
export type DOSHeader = types.DOSHeader
export type COFFHeader = types.COFFHeader
export type StandardHeader = types.StandardHeader
export type WindowsHeader = types.WindowsHeader
export type PE32WindowsHeader = types.PE32WindowsHeader
export type PE64WindowsHeader = types.PE64WindowsHeader
export type ImageDataDirectory = types.ImageDataDirectory
export type SectionHeader = types.SectionHeader
export type ResourceNode = types.ResourceNode
export type ResourceEntry = types.ResourceEntry
export type ResourceDirectory = types.ResourceDirectory
export type ResourceDataEntry = types.ResourceDataEntry

return {
	types = types,

	int64 = require("@self/int64"),
	utf16le = require("@self/utf16le"),

	parse = parser.parse,
	serialize = serializer.serialize,
	relocate_sections = serializer.relocate_sections,
	align = serializer.align,
	calculate_headers_size = serializer.calculate_headers_size,

	resources = resource_utils,

	builder = image_builder,
}
