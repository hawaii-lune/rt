-- Lune FS<->Uri bindings
-- its more useful to have file IO operations output as a buffer, so thats the case here

local fs = require("@lune/fs")
local URI = require("./URI")
local process = require("@lune/process")
type URI = URI.URI

local function finalisePath(uri: URI): string
	if not uri.Relative then return uri:ToString() end
	-- cwd is mutable, though this is optimised
	return (URI.new(process.cwd) .. uri):ToString()
end

-- exports
export type MetadataKind = fs.MetadataKind
export type MetadataPermissions = fs.MetadataPermissions
export type Metadata = fs.Metadata
export type WriteOptions = fs.WriteOptions

-- functions

local fsURI = {}

function fsURI.readFile(path: URI.URI): buffer
	return buffer.fromstring(fs.readFile(finalisePath(path)))
end

function fsURI.readDir(path: URI.URI): {string}
	return fs.readDir(finalisePath(path))
end

function fsURI.writeFile(path: URI.URI, contents: string | buffer)
	fs.writeFile(finalisePath(path), contents)
end

function fsURI.writeDir(path: URI.URI)
	fs.writeDir(finalisePath(path))
end

function fsURI.removeFile(path: URI.URI)
	fs.removeFile(finalisePath(path))
end

function fsURI.removeDir(path: URI.URI)
	fs.removeDir(finalisePath(path))
end

function fsURI.metadata(path: URI.URI): Metadata
	return fs.metadata(finalisePath(path))
end

function fsURI.isFile(path: URI.URI): boolean
	return fs.isFile(finalisePath(path))
end

function fsURI.isDir(path: URI.URI): boolean
	return fs.isDir(finalisePath(path))
end

function fsURI.move(from: URI.URI, to: URI.URI, overwriteOrOptions: (boolean | WriteOptions)?)
	fs.move(finalisePath(from), finalisePath(to), overwriteOrOptions)
end

function fsURI.copy(from: URI.URI, to: URI.URI, overwriteOrOptions: (boolean | WriteOptions)?)
	fs.copy(finalisePath(from), finalisePath(to), overwriteOrOptions)
end

return fsURI