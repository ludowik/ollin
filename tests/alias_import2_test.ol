## Second importer, under the SAME alias. Both are imported flat by regressions.ol, so both
## declarations of `shd` land in one scope — which used to be refused.
import "shared_lib_test.ol" as shd
func aliasTwo()
    return shd.sharedTwice(shd.SHARED_K)
end
