-- This file is part of the Hawaii Runtime.
-- Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).
-- You may obtain a copy of the License at:
--   https://www.mozilla.org/en-US/MPL/2.0/

return {
	INTERNAL_PACKAGES = {
		-- These are invalid as XHWI deps, but can be used in HWI to locally
		-- set an alias
		["Hawaii.System"] = true
	},

	HWI_MIN = 1,
	HWI_MAX = 1,
	HWI_PREFER = 1,

	HWI_DEFAULT_OPTIONS = {
		Compressed = true,
		Compiled = true,
		Native = false,
		Release = false
	},

	HWI_OPTION_BITFLAGS = {
		Compressed = 1,
		Compiled = 2,
		Native = 4,
		Release = 8
	},

	HWI_MIN_CONTENT_SIZE = 10,

	XHWI_MIN = 1,
	XHWI_MAX = 1,
	XHWI_PREFER = 1,

	XHWI_IMPORT_TYPE = {
		[0] = "Embedded",
		[1] = "RelativeToFile",
		[2] = "Package",

		Embedded = 0,
		RelativeToFile = 1,
		Package = 2
	},

	-- technically the same as the above but used for format keys
	XHWI_IMPORT_NAMES = {
		Embedded = "Embedded"::"Embedded",
		RelativeToFile = "RelativeToFile"::"RelativeToFile",
		Package = "Package"::"Package"
	},

	XHWI_MIN_CONTENT_SIZE = 8
}