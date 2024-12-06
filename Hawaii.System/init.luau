-- This is a script that builds the import tree from Bootstrapper
-- Its done like this so we have less files to maintain and creates a loose-couple
-- to the bootstrapper's exports

for k, v in import "*" .from ("/FFI/Bootstrapper") do exports[k] = v end