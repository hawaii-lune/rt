-- This file is part of the Hawaii Runtime.
-- Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).
-- You may obtain a copy of the License at:
--   https://www.mozilla.org/en-US/MPL/2.0/

local BasicTypes = require("./BasicTypes")
local FormatConfig = require("./FormatConfig")
local luau = require("@lune/luau")
local Path = require("../File/Path")
local serde = require("@lune/serde")
local Types = require("./Types")

local DEFAULT_OPTIONS = FormatConfig.HWI_DEFAULT_OPTIONS
local BITFLAG = FormatConfig.HWI_OPTION_BITFLAGS
local SYSTEM_PACKS = FormatConfig.INTERNAL_PACKAGES

local function getBufferedWriter(
	name: string,
	objects: {{path: string, content: buffer}},
	entry: string,
	dependencies: {Types.HWIDependency}
): buffer
	-- object content should be compressed at this point
	-- HWI VERSION BITFLAG and a work in progress signing key
	local size = 6
	size +=
		BasicTypes.SizeofULEBString(name) + BasicTypes.SizeofULEBString(entry)
		+ BasicTypes.ULEB128Size(#objects) + BasicTypes.ULEB128Size(#dependencies)
	-- compute object and dependency size
	for _, object in objects do
		size += BasicTypes.SizeofULEBString(object.path) + BasicTypes.SizeofULEBBuffer(object.content)
	end

	for _, dependency in dependencies do
		size += BasicTypes.SizeofULEBString(dependency.Alias) + BasicTypes.SizeofULEBString(dependency.Dependency)
		local pkg = dependency.PackageSettings
		if pkg then
			if SYSTEM_PACKS[dependency.Dependency] then
				warn(`Internal package {dependency.Dependency} cannot be remotely referenced. Skipping Creator/Version field...`)
				size += 2
				continue
			end

			size += BasicTypes.SizeofULEBString(pkg.Creator) + BasicTypes.SizeofULEBString(pkg.Version)
		else
			size += 2
		end
	end

	return buffer.create(size)
end

local PATHS = {
	objects = Path.fromUNIX("/objects"),
	source = Path.fromUNIX("/source")
}

local function funcWrap(source: string): string
	return `return function(import, exports, package) {source} end`
end

local function encodeSourcecode(sourcecode: buffer, options: Types.HWIFormatOptions): buffer
	local worker = buffer.tostring(sourcecode)
	local finalisedSource = funcWrap(worker)

	return buffer.fromstring(if options.Compiled then luau.compile(finalisedSource, {
		optimizationLevel = if options.Release then 2 else 1,
		coverageLevel = 0,
		debugLevel = if options.Release then 0 else 2
	}) else finalisedSource)
end

local function getBitFlag(options: Types.HWIFormatOptions)
	return
		(if options.Compressed then BITFLAG.Compressed else 0)
		+ (if options.Compiled then BITFLAG.Compiled else 0)
		+ (if options.Native then BITFLAG.Native else 0)
		+ (if options.Release then BITFLAG.Release else 0)
end

-- hwi creator
return function(
	name: string,
	objects: {[Path.Path]: Types.HWIWriterObject},
	entry: Path.Path,
	options: Types.HWIFormatOptions?,
	dependencies: {Types.HWIDependency}?
): Types.HWIResult
	local compressedObjects: {{path: string, content: buffer}} = {}
	local buildOptions: Types.HWIFormatOptions = {
		Compressed = if options and options.Compressed ~= nil then options.Compressed else DEFAULT_OPTIONS.Compressed,
		Compiled = if options and options.Compiled ~= nil then options.Compiled else DEFAULT_OPTIONS.Compiled,
		Native = if options and options.Native ~= nil then options.Native else DEFAULT_OPTIONS.Native,
		Release = if options and options.Release ~= nil then options.Release else DEFAULT_OPTIONS.Release
	}
	local entryAbsolute = PATHS.source .. entry
	local entryInFile = false
	local deps = dependencies or {}::{Types.HWIDependency}

	for path, object in objects do
		local absoluteRoot = PATHS[object.DirectoryType]
		local isSourceFile = absoluteRoot == PATHS.source
		if not absoluteRoot then error("invalid directory source") end
		absoluteRoot ..= path
		if absoluteRoot == entryAbsolute then entryInFile = true end

		local content = object.Content
		if isSourceFile then
			content = encodeSourcecode(content, buildOptions)
		end

		if buildOptions.Compressed then
			content = buffer.fromstring(serde.compress("zlib", content))
		end

		table.insert(compressedObjects, {
			path = absoluteRoot:ToString("UNIX"),
			content = content 
		})
	end

	local absoluteString = entryAbsolute:ToString("UNIX")
	if not entryInFile then error(`Entry point {entry:ToString()} cant be found in object list`) end
	
	local writer = getBufferedWriter(
		name,
		compressedObjects,
		absoluteString,
		deps
	)

	buffer.writestring(writer, 0, "HWI")
	buffer.writeu8(writer, 3, FormatConfig.HWI_PREFER)
	local offsetPointer = {offset = 4}

	BasicTypes.InsertString(writer, name, offsetPointer)
	buffer.writeu8(writer, offsetPointer.offset, getBitFlag(buildOptions))
	offsetPointer.offset += 1
	BasicTypes.InsertString(writer, absoluteString, offsetPointer)
	BasicTypes.InsertULEB128(writer, #deps, offsetPointer)

	for _, dep in deps do
		BasicTypes.InsertString(writer, dep.Alias, offsetPointer)
		BasicTypes.InsertString(writer, dep.Dependency, offsetPointer)
		local pkg = dep.PackageSettings
		if pkg and not SYSTEM_PACKS[dep.Dependency] then
			BasicTypes.InsertString(writer, pkg.Creator, offsetPointer)
			BasicTypes.InsertString(writer, pkg.Version, offsetPointer)
		else
			buffer.writeu16(writer, offsetPointer.offset, 0)
			offsetPointer.offset += 2
		end
	end

	BasicTypes.InsertULEB128(writer, #compressedObjects, offsetPointer)

	for _, object in compressedObjects do
		BasicTypes.InsertString(writer, object.path, offsetPointer)
		BasicTypes.InsertBuffer(writer, object.content, offsetPointer)
	end

	-- future signing key impl for when lune gets a crypto libray
	buffer.writeu8(writer, offsetPointer.offset, 0)

	return {
		Name = name,
		Content = writer
	}
end