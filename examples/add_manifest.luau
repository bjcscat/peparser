local fs = require("@lute/fs")
local peparser = require("@peparser")

local manifest_xml = [[<?xml version='1.0' encoding='UTF-8' standalone='yes'?>
<assembly xmlns='urn:schemas-microsoft-com:asm.v1' manifestVersion='1.0'>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level='asInvoker' uiAccess='false' />
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>]]

print(`Reading file`)
local file_data = fs.readasync("myapp.exe")
local file_buffer = buffer.fromstring(file_data)

print("Parsing PE image")
local image = peparser.image.parse(file_buffer)

print("Current sections:")
for i, section in image.sections do
	print(`  {i}. {section.header.name} - RVA: 0x{string.format("%X", section.header.virtual_address)}`)
end

print("Adding manifest resource")
local resources = peparser.resources.from_image(image) or peparser.resources.create_directory(0)

local LANG_NEUTRAL = 0
local manifest_path = peparser.resources.make_path(peparser.resources.TYPES.MANIFEST, 1, LANG_NEUTRAL)
local manifest_buffer = buffer.fromstring(manifest_xml)

peparser.resources.ensure_path(resources, manifest_path, manifest_buffer)

print("Applying resources to image")
image = peparser.resources.to_image(image, resources)

print("Sections after relocation:")
for i, section in image.sections do
	print(`  {i}. {section.header.name} - RVA: 0x{string.format("%X", section.header.virtual_address)}`)
end

print("Serializing PE image")
local output_buffer = peparser.image.serialize(image, false)

print(`Writing output file`)
fs.writestringtofile("myapp_modified.exe", buffer.tostring(output_buffer))
