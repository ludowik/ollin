### commentaire
multilignes
###

## commentaire de fin de ligne

print("hello world!")

var a = 12.12
var b, c = 1, 2
var res = a + b
print(res)

var vrai = true
var faux = false

while vrai
    a += 1
    if a > 40 then break end
end

print(a)

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
    ## le block else est optionnelle
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
