### commentaire
multilignes
###

## commentaire de fin de ligne

print("hello world!")

var def
assert(def == nil)

var a = 12.12
var b, c = 1, 2
var res = a + b
print(res)

var vrai = true
var faux = false

while vrai
    a += 1 ## add
    a -= .5 ## subtract
    a *= 1.1 ## multiply
    a /= 0.9 ## divide
    if a > 40 then break end
end

assert(1000.12 == 1_000.12)
assert(1000000 == 1_000_000)

while (not vrai)
end

a %= 2 ## modulo

a  = -a + b * b + (a / a - 1)

var exp = true or false and true or (not true)
assert(1 == true)
assert(0 == false)
assert("non vide" == true)
assert("" == false)

print(a)

a = 2

if a == 2 then
    print("a == 2")
else if a == b then
    ## elseif optionnel
    print("a == b")
else
    ## else optionnel
    print("le cas échéant")
end

try
    throw "oulala"
catch err
    print(err)
else
    ## le block else est optionnel
    print("all is good")
end

try
catch err
    print(err)
else
    print("all is good")
end

try
catch err
end

## déclaration d'une fonction

a = 2
func fname(arg1, arg2, ...)
    print(arg1, arg2)
    var a = 1 ## local, overload global a
    return arg1, arg2, ...
end
fname(1, 2, 3)
assert(a==2)


func f2(arg1, arg2=1)
    assert(arg1 == nil)
    assert(arg2 == 1)
end
f2()

for i in 1..10
		print(i)
end

for i=1,10
		print(i)
end

for i=1,10,2    ## step optionnel
		print(i)
end

for i=10,1,-1   ## step négatif
		print(i)
end

var t = {} ## map : syntaxe identique a json / js
var m = {
	"a": 1,
  "b": 2,
	macle: true,
	mamap: {}
}   ## map literal with string keys
print(m["a"])                ## index get → 1
m["c"] = 3                   ## index set
m["a"] += 10                 ## compound index assignment
assert(m["a"] == 11)
assert(m["c"] == 3)
m.c = 4 ## équivalent a m["c"] 

for k,v in m
		print(k, v)
end
