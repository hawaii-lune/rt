-- This file is part of the Hawaii Runtime.
-- Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).
-- You may obtain a copy of the License at:
--   https://www.mozilla.org/en-US/MPL/2.0/

local process = require("@lune/process")
type PathOutputTarget = "UNIX"|"DOS"
local staticPaths = setmetatable({}::{[string]: Path}, {__mode = "v"})

local LOCAL_TARGET: PathOutputTarget = if process.os == "windows" then "DOS" else "UNIX"
local ILLEGAL_DOS_CHARS = '[:<>"|?*\\/]'
local DOS_DRIVE = "^%w+:$"

export type Path = typeof(setmetatable({}::{
	Tree: {string},
	File: string,
	Relative: boolean,
	Parent: (Path) -> Path?,
	ToString: (Path, target: PathOutputTarget?) -> string
},{}::{
	__concat: (Path, Path) -> Path,
	__index: (Path, string) -> Path,
	__tostring: (Path) -> string
}))

local function getStaticIndex(components: {string}, relative: boolean)
	local parentString = table.concat(components, "/")
	return if relative then parentString else `/{parentString}`
end

local getPath

local function stringTrim(str: string): string
	return string.match(str, "^%s*(.-)%s*$") or ""
end

local function sanitisePathComponents(path: string, joiner: "\\"|"/"): ({string}, boolean)
	-- removes leading and trailing joiner, returns if relative
	if stringTrim(path) == "" then error("The path is empty.") end
	local components = string.split(path, joiner)

	if string.sub(path, -1) == joiner then
		table.remove(components, #components)
	end

	local relative = stringTrim(components[1]) ~= ""
	if not relative then table.remove(components, 1) end

	for index, component in components do
		components[index] = stringTrim(component)
	end

	return components, relative
end

local function appendComponents<T>(lhs: {T}, rhs: {T}): {T}
	return table.move(rhs, 1, #rhs, #lhs + 1, lhs)
end

local function joinPathString(lhs: Path, pathStream: string): Path
	local components, relative = sanitisePathComponents(pathStream, "/")
	if not relative then error("cannot join an absolute path to an existing path") end
	return getPath(appendComponents(table.clone(lhs.Tree), components), lhs.Relative)
end

local function joinPath(lhs: Path, rhs: Path)
	if not rhs.Relative then error("cannot join an absolute path to an existing path") end
	return getPath(appendComponents(table.clone(lhs.Tree), rhs.Tree), lhs.Relative)
end

local function appendPath(path: Path, loc: string): Path
	if string.find(loc, "/", 0, true) then
		-- use joinPathString instead
		return joinPathString(path, loc)
	end

	if loc == "." then return path end
	local ancestry = table.clone(path.Tree)

	if loc == ".." then
		if not ancestry[2] then
			if not path.Relative then error("Attempt to path an absolute path out of the root") end
			return getPath({".."}, true)
		end
		table.remove(ancestry, #ancestry)
	else
		table.insert(ancestry, loc)
	end

	return getPath(ancestry, path.Relative)
end

local function pathParent(self: Path): Path?
	return appendPath(self, "..")
end

local function DOSToString(path: Path): string
	-- this should validate that if relative = false, the first object matches
	-- the drive format, and everything else is allowed in path rules

	-- technically we should restrict the prohibited file names here but this
	-- is legacy jank that i'd rather not

	for index, part in path.Tree do
		if index == 1 and not path.Relative then
			-- first part should match drive format
			if not string.match(part, DOS_DRIVE) then error("malformed drive letter") end
			continue
		end

		-- each component should not conflict with the prohibited chars
		if string.match(part, ILLEGAL_DOS_CHARS) then error("prohibited DOS character in path") end
	end

	return table.concat(path.Tree, "\\")
end
	
local function pathToString(self: Path, target: PathOutputTarget?): string
	target = target or LOCAL_TARGET
	-- because DOS paths are more restrictive, it needs its own function
	if target == "DOS" then return DOSToString(self) end 

	local UNIX_REL = if self.Relative then "" else "/"
	return `{UNIX_REL}{table.concat(self.Tree, "/")}`
end

local PATH_MT = {
	__index = appendPath,
	__concat = joinPath,
	__tostring = pathToString
}

local function unwrapDotPaths(components: {string}, relative: boolean): {string}
	local stack = {} -- output stack
	local stackSize = 0 -- size of the stack (optimization when we're popping)
	local workingSize = 0 -- size of the current file path, different to stack size
	local relativeReentryName: string? -- used to simplify cases like folder/../folder -> folder

	for _, component in components do
		if component == "." then continue end -- Do nothing, refers to the same directory

		if component == ".." then
			if workingSize == 0 then
				-- nothing in stack, just append more .. objects
				if not relative then error("Attempt to path an absolute path out of the root") end -- this should never invoke but its a safety case
				
				if relativeReentryName then
					relativeReentryName = nil
					stackSize+=1
					stack[stackSize] = ".."
				end

				stackSize+=1
				stack[stackSize] = ".."
				continue
			end
			
			if workingSize == 1 then
				if not relative then error("Attempt to path an absolute path out of the root") end
				relativeReentryName = stack[stackSize]
			end

			stack[stackSize] = nil
			workingSize -= 1
			stackSize -= 1
		else
			if relativeReentryName then 
				if component ~= relativeReentryName then
					-- failed relativity test, append ..
					relativeReentryName = nil
					stackSize += 1
					workingSize += 1
					stack[stackSize] = ".."
				end

				relativeReentryName = nil
			end

			stackSize += 1
			workingSize += 1
			stack[stackSize] = component
		end
	end

	if relativeReentryName then stack[stackSize + 1] = ".." end
	return stack
end

function getPath(components: {string}, relative: boolean): Path
	components = unwrapDotPaths(components, relative)
	local staticIndex = getStaticIndex(components, relative)
	local path: Path? = staticPaths[staticIndex]

	if not path then
		local file = components[#components]

		path = setmetatable({
			Tree = components,
			File = file,
			Relative = relative,
			Parent = pathParent,
			ToString = pathToString
		}, PATH_MT)

		table.freeze(path)
		staticPaths[staticIndex] = path
	end

	return path::Path
end

local Path = {}

function Path.fromUNIX(path: string): Path
	local components, relative = sanitisePathComponents(path, "/")
	return getPath(components, relative)
end

function Path.fromDOS(path: string): Path
	path = string.gsub(path, "/", "\\")
	local components, relative = sanitisePathComponents(path, "\\")

	if not relative then
		local upper = string.match(process.cwd, "^(%w+:)\\") or "C:"
		table.insert(components, 1, if LOCAL_TARGET == "UNIX" then "C:" else string.upper(upper))
	end

	for index, component in components do
		local trimmed = stringTrim(component)
		if index == 1 and string.match(trimmed, DOS_DRIVE) then
			-- if "" then assume its \, in this case, we should retrieve the CWD and pull the drive letter
			if relative then
				relative = false
				components[1] = string.upper(trimmed)
			end
			continue
		end

		if string.match(trimmed, ILLEGAL_DOS_CHARS) then error(`File {trimmed} contains an illegal DOS character`) end
		components[index] = trimmed
	end

	return getPath(components, relative)
end

function Path.new(path: string): Path
	return if LOCAL_TARGET == "DOS" then Path.fromDOS(path) else Path.fromUNIX(path)
end

return Path