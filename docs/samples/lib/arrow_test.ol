## The arrows of lib/arrow.ol.

import "arrow.ol"

assert(arrowPoints("up", 10, 20, 4).join(",") == "10,16,6,24,14,24", "an arrow up has its tip above")
assert(arrowPoints("down", 10, 20, 4).join(",") == "10,24,6,16,14,16", "an arrow down has its tip below")
assert(arrowPoints("left", 10, 20, 4).join(",") == "6,20,14,16,14,24", "an arrow left has its tip on the left")
assert(arrowPoints("right", 10, 20, 4).join(",") == "14,20,6,16,6,24", "an arrow right has its tip on the right")
print("arrow ok")
