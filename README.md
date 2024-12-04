# Hawaii Runtime

Standalone runtime, seperated so we can develop the bootstrapper here detatched
from it's packages.

# Building

This can be built in two steps, first by bundling it with darklua, then by
getting lune to build it to an `exe`.

Since no CHWI file is loaded in the standalone debug, this will assume the role
of loading HWI files. (Note, if the CHWI matches that of Hawaii.CLI, the
debugger is still enabled)

```bat
darklua process src/init.luau out/Hawaii.luau
lune build -t win-x86_64 -o out/Hawaii.exe out/Hawaii.luau
```

## Exports

If a package by the name of `Hawaii.System` is loaded into the import engine,
then it is assumed that useful libraries contained in this package can be
exported.

These are as of current:

* `Bookstrapper` - disabled as of current
* `PackageIO` - library to work with HWI / CHWI files
* `URI` - **U**niform **R**esource **I**ndentifier library

## Regarding Hawaii.Builder

Hawaii.Builder *had* an option to build to EXE. I am investigating on how to do
this with the new build engine. My current approach is to reference this as a
submodule and point to it in the `hawaii.toml` file