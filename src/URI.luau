-- Implements a UNIX-like URI
-- Can output to a Windows-like or UNIX-like path

local process = require("@lune/process")
type PathOutputTarget = "UNIX"|"DOS"
local staticPaths = setmetatable({}, {__mode = "v"})

local LOCAL_TARGET = if process.os == "windows" then "DOS" else "UNIX"
local ILLEGAL_DOS_CHARS = '[:<>"|?*\\/]'
local DOS_DRIVE = "^%w+:$"

export type URI = typeof(setmetatable({}::{
	Tree: {string},
	File: string,
	Relative: boolean,
	Parent: (URI) -> URI?,
	ToString: (URI, target: PathOutputTarget?) -> string
},{}::{
	__index: (URI, string) -> URI?,
	__concat: (URI, URI) -> URI?
}))

local function getStaticIndex(components: {string}, relative: boolean)
	local parentString = table.concat(components, "/")
	return if relative then parentString else `/{parentString}`
end

local newURI

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

local function joinPathString(lhs: URI, pathStream: string): URI
	local components, relative = sanitisePathComponents(pathStream, "/")
	if not relative then error("cannot join an absolute path to an existing path") end
	return newURI(appendComponents(table.clone(lhs.Tree), components), lhs.Relative)
end

local function joinPathURI(lhs: URI, rhs: URI)
	if not rhs.Relative then error("cannot join an absolute path to an existing path") end
	return newURI(appendComponents(table.clone(lhs.Tree), rhs.Tree), lhs.Relative)
end

local function appendURI(uri: URI, loc: string): URI?
	if string.find(loc, "/", 0, true) then
		-- use joinPathString instead
		return joinPathString(uri, loc)
	end

	if loc == "." then return uri end
	local ancestry = table.clone(uri.Tree)

	if loc == ".." then
		if not ancestry[2] then return nil end
		table.remove(ancestry, #ancestry)
	else
		table.insert(ancestry, loc)
	end

	return newURI(ancestry, uri.Relative)
end

local function URIParent(self: URI): URI?
	return appendURI(self, "..")
end

local function DOSToString(uri: URI): string
	-- this should validate that if relative = false, the first object matches
	-- the drive format, and everything else is allowed in path rules

	-- technically we should restrict the prohibited file names here but this
	-- is legacy jank that i'd rather not

	for index, part in uri.Tree do
		if index == 1 and not uri.Relative then
			-- first part should match drive format
			if not string.match(part, DOS_DRIVE) then error("malformed drive letter") end
			continue
		end

		-- each component should not conflict with the prohibited chars
		if string.match(part, ILLEGAL_DOS_CHARS) then error("prohibited DOS character in path") end
	end

	return table.concat(uri.Tree, "\\")
end
	
local function URIToString(self: URI, target: string?): string
	target = target or LOCAL_TARGET
	-- because DOS paths are more restrictive, it needs its own function
	if target == "DOS" then return DOSToString(self) end 

	local UNIX_REL = if self.Relative then "" else "/"
	return `{UNIX_REL}{table.concat(self.Tree, "/")}`
end

local URI_MT = {
	__index = appendURI,
	__concat = joinPathURI
}

local function unwrapDotPaths(components: {string}, relative: boolean): {string}
	local stack = {} -- output stack
	local stackSize = 0 -- size of the stack (optimization when we're popping)
	local workingSize = 0 -- size of the current file path, different to stack size
	local relativeReentryName -- used to simplify cases like folder/../folder -> folder

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

function newURI(components: {string}, relative: boolean): URI
	local staticIndex = getStaticIndex(components, relative)
	local uri = staticPaths[staticIndex]

	if not uri then
		components = unwrapDotPaths(components, relative)
		local file = components[#components]

		uri = setmetatable({
			Tree = components,
			File = file,
			Relative = relative,
			Parent = URIParent,
			ToString = URIToString
		}, URI_MT)

		table.freeze(uri)
		staticPaths[staticIndex] = uri
	end

	return uri::URI
end

local URI = {}

function URI.fromUNIX(path: string): URI
	local components, relative = sanitisePathComponents(path, "/")
	return newURI(components, relative)
end

function URI.fromDOS(path: string): URI
	path = string.gsub(path, "/", "\\")
	local components, relative = sanitisePathComponents(path, "\\")

	if not relative then
		local upper = string.match(process.cwd, "^(%w+:)\\")
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

	return newURI(components, relative)
end

function URI.new(path: string): URI
	return if LOCAL_TARGET == "DOS" then URI.fromDOS(path) else URI.fromUNIX(path)
end

return URI