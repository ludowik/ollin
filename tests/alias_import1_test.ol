## First importer of the shared library, under the alias `shd`.
import "shared_lib_test.ol" as shd
func aliasOne()
    return shd.SHARED_K
end
