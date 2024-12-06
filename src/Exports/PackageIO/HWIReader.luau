-- This file is part of the Hawaii Runtime.
-- Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).
-- You may obtain a copy of the License at:
--   https://www.mozilla.org/en-US/MPL/2.0/

local BasicTypes = require("./BasicTypes")
local FormatConfig = require("./FormatConfig")
local Path = require("../File/Path")
local serde = require("@lune/serde")
local Types = require("./Types")

local SYSTEM_PACKS = FormatConfig.INTERNAL_PACKAGES
local BITFLAG = FormatConfig.HWI_OPTION_BITFLAGS

local function Object(content: buffer, offsetPointer: BasicTypes.OffsetPointer): Types.HWIObject
	local path = Path.fromUNIX(BasicTypes.ReadString(content, offsetPointer))
	local compressed = buffer.fromstring(BasicTypes.ReadString(content, offsetPointer))

	return {
		Name = path.File,
		Location = path,
		CompressedContent = compressed,
		Open = function(self: Types.HWIObject): buffer
			local rawcontent = self.RawContent

			if not rawcontent then
				rawcontent = buffer.fromstring(serde.decompress("zlib", self.CompressedContent))
				self.RawContent = rawcontent
			end

			return rawcontent
		end
	}
end

local function Dependency(content: buffer, offsetPointer: BasicTypes.OffsetPointer): Types.HWIDependency
	local alias = BasicTypes.ReadString(content, offsetPointer)
	local dependency = BasicTypes.ReadString(content, offsetPointer)
	local creator = BasicTypes.ReadString(content, offsetPointer)
	local pkgversion = BasicTypes.ReadString(content, offsetPointer)

	local creatorEmpty, versionEmpty = creator == "", pkgversion == ""
	local isRemote = not creatorEmpty and not versionEmpty
	if not isRemote and (not creatorEmpty or not versionEmpty) then
		local c = if creatorEmpty then "unknown" else creator
		local v = if versionEmpty then "0.0.0" else pkgversion

		warn(`Package contains a bad remote dependency configuration {c}/{dependency}@{v}`)
	end

	if SYSTEM_PACKS[dependency] and isRemote then
		warn(`Internal package {dependency} was defined as a remote.`)
	end

	return {
		Alias = alias,
		Dependency = dependency,

		PackageSettings = if isRemote then {
			Creator = creator,
			Version = pkgversion
		} else nil
	}
end

local function readBitFlag(u8: number): Types.HWIFormatOptions
	-- this is hardcoded
	local options = {
		Compressed = bit32.band(u8, BITFLAG.Compressed) == BITFLAG.Compressed,
		Compiled = bit32.band(u8, BITFLAG.Compiled) == BITFLAG.Compiled,
		Native = bit32.band(u8, BITFLAG.Native) == BITFLAG.Native,
		Release = bit32.band(u8, BITFLAG.Native) == BITFLAG.Native,
	}

	table.freeze(options)
	return options
end

return function(content: buffer): Types.HWIFile
	if buffer.len(content) < FormatConfig.HWI_MIN_CONTENT_SIZE then
		error("Input stream is too small for the smallest possible HWI file")
	end

	if buffer.readstring(content, 0, 3) ~= "HWI" then
		error("Invalid content header")
	end

	local ver = buffer.readu8(content, 3)
	if ver < FormatConfig.HWI_MIN or ver > FormatConfig.HWI_MAX then
		error(`version out of range {FormatConfig.HWI_MIN} <= {ver} < {FormatConfig.HWI_MAX}`)
	end

	local offsetPointer = {offset = 4}
	local name = BasicTypes.ReadString(content, offsetPointer)
	local options = readBitFlag(buffer.readu8(content, offsetPointer.offset))
	offsetPointer.offset += 1
	local entry = Path.fromUNIX(BasicTypes.ReadString(content, offsetPointer))
	local numDeps = BasicTypes.ULEB128(content, offsetPointer)
	local deps = {}

	if numDeps > 0 then
		for depIdx = 1, numDeps do
			local dep = Dependency(content, offsetPointer)
			deps[dep.Dependency] = dep
		end
	end

	local numObjects = BasicTypes.ULEB128(content, offsetPointer)
	local entryFile
	local objects = {}

	if numObjects > 0 then
		for objIdx = 1, numObjects do
			local obj = Object(content, offsetPointer)
			objects[obj.Location] = obj

			if obj.Location == entry then entryFile = obj end
		end
	end

	if not entryFile then
		error(`Entry object {entry:ToString("UNIX")} not present in HWI {name}`)
	end

	-- todo: read signature here.
	local hwi = {
		Name = name,
		Entry = entryFile,
		Objects = objects,
		Dependencies = deps,
		Options = options,
		Signed = false
	}
	table.freeze(hwi)
	return hwi
end
