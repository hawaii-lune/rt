-- This file is part of the Hawaii Runtime.
-- Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).
-- You may obtain a copy of the License at:
--   https://www.mozilla.org/en-US/MPL/2.0/

local BasicTypes = require("./BasicTypes")
local FormatConfig = require("./FormatConfig")
local serde = require("@lune/serde")
local Types = require("./Types")

local SYSTEM_PACKS = FormatConfig.INTERNAL_PACKAGES

return function(
	name: string,
	writableHWIs: {Types.HWIResult},
	entry: Types.HWIResult,
	remoteDeps: {Types.RemoteDependencyConfig}?
): buffer
	-- XHWI
	-- Version [1]
	-- XHWI Name
	-- Entry HWI Name
	-- HWI Files
	--[[
		PackageName
		ImportType = 0 - Embedded, 1 - RelativeToRoot, 2 - Packaged
		If 0 - file content
		If 1 - nothing
		If 2 - PackageConfig
	]]

	local numEntries = #writableHWIs + if remoteDeps then #remoteDeps else 0
	local hwiOverallSize = 0
	local rmDepSize = 0

	local embeddedFiles: {{fileName: string, content: buffer}} = {}
	local entryInWritable = false

	for _, file in writableHWIs do
		-- HWI files are always compressed
		if SYSTEM_PACKS[file.Name] then error(`System package {file.Name} cannot be included in XHWIs`) end

		if entry == file then entryInWritable = true end
		local compressed = buffer.fromstring(serde.compress("zlib", file.Content))
		table.insert(embeddedFiles, {
			fileName = file.Name,
			content = compressed
		})

		hwiOverallSize += 1 + BasicTypes.SizeofULEBString(file.Name) + BasicTypes.SizeofULEBBuffer(compressed)
	end

	if not entryInWritable then
		error(`Cant find entry file {entry.Name} in buffer. Remote dependencies cannot be used as entry points.`)
	end

	if remoteDeps then
		for _, dep in remoteDeps do
			if SYSTEM_PACKS[dep.Dependency] then error(`System package {dep.Dependency} cannot be included in XHWIs`) end
			
			rmDepSize += 1 + BasicTypes.SizeofULEBString(dep.Dependency)
			local pkg = dep.PackageSettings
			if pkg then
				rmDepSize += BasicTypes.SizeofULEBString(pkg.Creator) + BasicTypes.SizeofULEBString(pkg.Version)
			end
		end
	end

	local writer = buffer.create(5
		+ BasicTypes.SizeofULEBString(name)
		+ BasicTypes.SizeofULEBString(entry.Name)
		+ BasicTypes.ULEB128Size(numEntries)
		+ hwiOverallSize
		+ rmDepSize
	)
	
	buffer.writestring(writer, 0, "XHWI")
	buffer.writeu8(writer, 4, FormatConfig.XHWI_PREFER)
	local offsetPointer = {offset = 5}

	BasicTypes.InsertString(writer, name, offsetPointer)
	BasicTypes.InsertString(writer, entry.Name, offsetPointer)
	BasicTypes.InsertULEB128(writer, numEntries, offsetPointer)
  
	-- embed remote deps
	if remoteDeps then
		for _, remote in remoteDeps do
			local pkg = remote.PackageSettings
			buffer.writeu8(writer, offsetPointer.offset, if pkg then FormatConfig.XHWI_IMPORT_TYPE.Package else FormatConfig.XHWI_IMPORT_TYPE.RelativeToFile)
			offsetPointer.offset += 1
			
			BasicTypes.InsertString(writer, remote.Dependency, offsetPointer)
			if pkg then
				BasicTypes.InsertString(writer, pkg.Creator, offsetPointer)
				BasicTypes.InsertString(writer, pkg.Version, offsetPointer)
			end
		end
	end

	for _, objects in embeddedFiles do
		buffer.writeu8(writer, offsetPointer.offset, FormatConfig.XHWI_IMPORT_TYPE.Embedded)
		offsetPointer.offset += 1
		BasicTypes.InsertString(writer, objects.fileName, offsetPointer)
		BasicTypes.InsertBuffer(writer, objects.content, offsetPointer)
	end

	return writer
end