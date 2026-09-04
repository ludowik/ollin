## Two DIFFERENT modules under one alias, in one scope: a genuine contradiction, refused with a
## message naming both files. Run by test_errors.sh, which needs a real file because an import
## resolves against the importing file's directory.
import "alias_import1_test.ol"
import "config.ol" as shd
