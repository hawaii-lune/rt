# Hawaii Runtime

Standalone runtime, seperated so we can develop the bootstrapper here detatched
from it's packages.

# Building

This can be built in two steps, first by bundling it with darklua, then by
getting lune to build it to an `exe`.

```bat
darklua process src/init.luau out/Hawaii.luau
lune build -t win-x86_64 -o out/Hawaii.exe out/Hawaii.luau
```

To include a CHWI file before building, add a `.chwi.luau` file into the `src`
folder. This should be formatted with Base64, and have a linebreak every 80
characters. It should follow the form:

```lua
return [[
Base64 encoded CHWI file
]]
```

## Exports

If a package by the name of `Hawaii.System` is loaded into the import engine,
then it is assumed that useful libraries contained in this package can be
exported.

These are as of current:

* `Bookstrapper` - disabled as of current
* `PackageIO` - library to work with HWI / CHWI files
* `URI` - **U**niform **R**esource **I**ndentifier library

> can we have asymmetric enc in lune already so i can validate my own packages,
> thanks :3

## Regarding Hawaii.Builder

Hawaii.Builder *had* an option to build to EXE. I am investigating on how to do
this with the new build engine. My current approach is to reference this as a
submodule and point to it in the `hawaii.toml` file