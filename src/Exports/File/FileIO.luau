-- This file is part of the Hawaii Runtime.
-- Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).
-- You may obtain a copy of the License at:
--   https://www.mozilla.org/en-US/MPL/2.0/

local fs = require("@lune/fs")
local Path = require("./Path")
local process = require("@lune/process")
type Path = Path.Path

local function finalisePath(path: Path): string
	if not path.Relative then return path:ToString() end
	-- cwd is mutable, though this is optimised
	return (Path.new(process.cwd) .. path):ToString()
end

-- exports
export type MetadataKind = fs.MetadataKind
export type MetadataPermissions = fs.MetadataPermissions
export type Metadata = fs.Metadata
export type WriteOptions = fs.WriteOptions

-- functions

local fsURI = {}

function fsURI.readFile(path: Path): buffer
	return buffer.fromstring(fs.readFile(finalisePath(path)))
end

function fsURI.readDir(path: Path): {string}
	return fs.readDir(finalisePath(path))
end

function fsURI.writeFile(path: Path, contents: string | buffer)
	fs.writeFile(finalisePath(path), contents)
end

function fsURI.writeDir(path: Path)
	fs.writeDir(finalisePath(path))
end

function fsURI.removeFile(path: Path)
	fs.removeFile(finalisePath(path))
end

function fsURI.removeDir(path: Path)
	fs.removeDir(finalisePath(path))
end

function fsURI.metadata(path: Path): Metadata
	return fs.metadata(finalisePath(path))
end

function fsURI.isFile(path: Path): boolean
	return fs.isFile(finalisePath(path))
end

function fsURI.isDir(path: Path): boolean
	return fs.isDir(finalisePath(path))
end

function fsURI.move(from: Path, to: Path, overwriteOrOptions: (boolean | WriteOptions)?)
	fs.move(finalisePath(from), finalisePath(to), overwriteOrOptions)
end

function fsURI.copy(from: Path, to: Path, overwriteOrOptions: (boolean | WriteOptions)?)
	fs.copy(finalisePath(from), finalisePath(to), overwriteOrOptions)
end

return fsURI