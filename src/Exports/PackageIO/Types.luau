-- This file is part of the Hawaii Runtime.
-- Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).
-- You may obtain a copy of the License at:
--   https://www.mozilla.org/en-US/MPL/2.0/

local Path = require("../File/Path")

-- Shared
export type PackageReference = {
	Creator: string,
	Version: string
}

-- XHWIReader.luau
export type HWIEmbeddedReference = {
	Name: string,
	ImportType: "Embedded",
	CompressedContent: buffer,
	RawContent: HWIFile,
	Open: (HWIEmbeddedReference) -> HWIFile
}

export type HWIRelativeReference = {
	Name: string,
	ImportType: "RelativeToFile",
	Location: Path.Path?
}

export type HWIPackageReference = {
	Name: string,
	ImportType: "Package",
	Creator: string,
	Version: string
}

export type IPackageReference = HWIEmbeddedReference | HWIRelativeReference | HWIPackageReference

export type XHWIContainer = {
	Name: string,
	Entry: HWIEmbeddedReference,
	Location: Path.Path?,
	Packages: {[string]: IPackageReference}
}

-- XHWIWriter.luau

export type RemoteDependencyConfig = {
	Dependency: string,
	PackageSettings: PackageReference?
}

-- HWIReader.luau

export type HWIObject = {
	Name: string,
	Location: Path.Path,
	CompressedContent: buffer,
	RawContent: buffer?,
	Open: (HWIObject) -> buffer
}

export type HWIFile = {
	Name: string,
	Entry: HWIObject,
	Objects: {[Path.Path]: HWIObject},
	Dependencies: {[string]: HWIDependency},
	Options: HWIFormatOptions,
	Signed: false -- waiting for that crypto lib :|
}

-- HWIWriter.luau

export type HWIFormatOptions = {
	Compressed: boolean,
	Compiled: boolean,
	Native: boolean,
	Release: boolean
}

export type HWIDependency = {
	Alias: string,
	Dependency: string,
	PackageSettings: PackageReference?
}

export type HWIWriterObject = {
	DirectoryType: "objects"|"source",
	Content: buffer
}

export type HWIResult = {
	Content: buffer,
	Name: string
}

return nil