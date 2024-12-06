-- This file is part of the Hawaii Runtime.
-- Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).
-- You may obtain a copy of the License at:
--   https://www.mozilla.org/en-US/MPL/2.0/

local BasicTypes = require("./BasicTypes")
local FormatConfig = require("./FormatConfig")
local HWIReader = require("./HWIReader")
local Path = require("../File/Path")
local serde = require("@lune/serde")
local Types = require("./Types")

local XHWI_IMPORT_TYPE = FormatConfig.XHWI_IMPORT_TYPE
local XHWI_IMPORT_NAMES = FormatConfig.XHWI_IMPORT_NAMES
local SYSTEM_PACKS = FormatConfig.INTERNAL_PACKAGES

local function ObjectEntry(content: buffer, offsetPointer: BasicTypes.OffsetPointer): Types.IPackageReference
	local importTypeID = buffer.readu8(content, offsetPointer.offset)
	local importType = XHWI_IMPORT_TYPE[importTypeID]

	if not importType then error(`Invalid object import type {importTypeID}`) end
	offsetPointer.offset += 1
	local objectName = BasicTypes.ReadString(content, offsetPointer)

	local object = {}::Types.IPackageReference
	object.Name = objectName
	object.ImportType = importType

	if object.ImportType == XHWI_IMPORT_NAMES.Embedded then
		object.CompressedContent = buffer.fromstring(BasicTypes.ReadString(content, offsetPointer))

		function object.Open(self: Types.HWIEmbeddedReference): Types.HWIFile
			local content = self.RawContent

			if not content then
				content = HWIReader(
					buffer.fromstring(serde.decompress("zlib", self.CompressedContent))
				)
				self.RawContent = content
			end

			return content
		end
	elseif object.ImportType == XHWI_IMPORT_NAMES.RelativeToFile then
		-- no content in this one specifically
		-- but we should have a branch sink here anyway for future usage
	elseif object.ImportType == XHWI_IMPORT_NAMES.Package then
		object.Creator = BasicTypes.ReadString(content, offsetPointer)
		object.Version = BasicTypes.ReadString(content, offsetPointer)
	end

	return object
end

return function(content: buffer, loc: Path.Path?): Types.XHWIContainer
	if buffer.len(content) < FormatConfig.XHWI_MIN_CONTENT_SIZE then
		error("Input stream is too small for the smallest possible XHWI file")
	end

	if buffer.readstring(content, 0, 4) ~= "XHWI" then
		error("Invalid content header")
	end

	local ver = buffer.readu8(content, 4)
	if ver < FormatConfig.XHWI_MIN or ver > FormatConfig.XHWI_MAX then
		error(`version out of range {FormatConfig.XHWI_MIN} <= {ver} < {FormatConfig.XHWI_MAX}`)
	end

	local offsetPointer = {offset = 5}
	local name = BasicTypes.ReadString(content, offsetPointer)
	local entry = BasicTypes.ReadString(content, offsetPointer)
	local objectSize = BasicTypes.ULEB128(content, offsetPointer)
	local objects = {}
	local entryObj
	local entryAppearsAsRemote = false

	if objectSize > 0 then
		for idx = 1, objectSize do
			local object = ObjectEntry(content, offsetPointer)

			if SYSTEM_PACKS[object.Name] then
				warn(`Executable contains reference to internal package {object.Name}, skipping...`)
				continue
			end

			if object.Name == entry then
				if object.ImportType == XHWI_IMPORT_NAMES.Embedded then
					entryObj = object
				else
					entryAppearsAsRemote = true
				end
			end

			objects[object.Name] = object
		end
	end

	if not entryObj then
		if entryAppearsAsRemote then
			print(`[NOTE]: Package {entry} is present as a remote reference.`)
		end

		error(`Entry package {entry} not present within the executable as an embedded reference.`)
	end

	local xhwi = {
		Name = name,
		Entry = entryObj,
		Location = loc,
		Packages = objects
	}
	table.freeze(xhwi)
	return xhwi
end