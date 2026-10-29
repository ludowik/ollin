## The RULES of a pocket calculator, with no drawing: what the display shows after each key. Operations are carried out
## in the order they are typed, as on a pocket calculator, so 2 + 3 x 4 is 20 and not 14.
##
## The state is a map made by calcNew(), and calcPress(state, key) changes it:
##   display    the text on the screen: a number, or "Error"
##   acc        the left operand of the pending operation, or nil
##   op         the pending operation, "+", "-", "*" or "/", or nil
##   fresh      the next digit starts a new number rather than lengthening the display
##   entered    the display holds an operand for the pending operation, typed or computed since the operator
##   lastOp, lastArg   what "=" repeats when it is pressed again
##   history    the line above the display: "12 +" while an operation is pending, "12 + 3 =" once done
##   error      the display says "Error" and the next key starts again
## A number is held as a float, so a long product does not wrap around like an integer; 0 is false in Ollin, so every
## test on acc compares it to nil.
##
## Imported by calculator.ol.

const MAX_DIGITS = 10                  ## digits a number can be typed with; a result is rounded to as many
const SYMBOLS = {"+": "+", "-": "-", "*": "x", "/": "/"}   ## what the screen says for each operation (the font has no multiplication sign)

func calcNew()
    var s = {}
    calcReset(s)
    return s
end

func calcReset(s)
    s.display = "0"
    s.acc = nil
    s.op = nil
    s.fresh = true
    s.entered = false
    s.error = false
    s.lastOp = nil
    s.lastArg = nil
    s.history = ""
end

## The text of a number, rounded to ten significant digits so that 0.1 + 0.2 shows 0.3; nil when it has no text.
func calcFormat(x)
    if math.isNan(x) or math.isInf(x) then
        return nil
    end
    var text = "{x:.10g}"
    if text == "-0" then
        return "0"
    end
    return text
end

## The number on the display, as a float: a division always gives one, whereas 1.0 written in a script is the integer 1.
func calcValue(s)
    return s.display.number() / 1
end

func calcApply(a, op, b)
    switch op
    case "+"
        return a + b
    case "-"
        return a - b
    case "*"
        return a * b
    else
        if b == 0 then
            return nil
        end
        return a / b
    end
end

## Shows a result, or "Error" when it has no text (a division by zero, a number too large). Tells whether it could.
func calcShow(s, x)
    var text = nil
    if x <> nil then
        text = calcFormat(x)
    end
    if text == nil then
        calcReset(s)
        s.display = "Error"
        s.error = true
        return false
    end
    s.display = text
    return true
end

## The label of the clearing key: C takes back the number being typed, AC (when there is none) clears everything.
func calcClearLabel(s)
    if s.entered and not s.error then
        return "C"
    end
    return "AC"
end

func calcDigit(s, key)
    var sign = ""
    var digits = s.display
    if s.display.startsWith("-") then
        sign = "-"
        digits = s.display.substr(2)
    end
    if s.fresh then
        sign = ""
        digits = "0"
        if s.op == nil then
            s.history = ""
        end
    end
    var room = digits.replace(".", "").len() < MAX_DIGITS
    if key == "." then
        if digits.find(".") == nil and room then
            digits = digits + "."
        end
    elseif digits == "0" then
        digits = key
    elseif room then
        digits = digits + key
    end
    s.display = sign + digits
    s.fresh = false
    s.entered = true
end

func calcOperator(s, key)
    if s.op <> nil and s.entered then
        var result = calcApply(s.acc, s.op, calcValue(s))
        if not calcShow(s, result) then
            return
        end
        s.acc = result
    elseif s.op == nil then
        s.acc = calcValue(s)
    end
    s.op = key
    s.fresh = true
    s.entered = false
    s.history = calcFormat(s.acc) + " " + SYMBOLS[key]
end

func calcEquals(s)
    var left = nil
    var op = nil
    var arg = nil
    if s.op <> nil then
        left = s.acc
        op = s.op
        arg = calcValue(s)
        s.lastOp = op
        s.lastArg = arg
    elseif s.lastOp <> nil then
        left = calcValue(s)
        op = s.lastOp
        arg = s.lastArg
    else
        return
    end
    if not calcShow(s, calcApply(left, op, arg)) then
        return
    end
    s.history = calcFormat(left) + " " + SYMBOLS[op] + " " + calcFormat(arg) + " ="
    s.acc = nil
    s.op = nil
    s.fresh = true
    s.entered = false
end

## A percentage of the left operand after + or -, so 200 + 10 % adds 20; otherwise a hundredth of the display.
func calcPercent(s)
    var v = calcValue(s)
    if s.acc <> nil and (s.op == "+" or s.op == "-") then
        v = s.acc * v / 100
    else
        v = v / 100
    end
    if calcShow(s, v) then
        s.fresh = true
        s.entered = true
    end
end

func calcNegate(s)
    if s.fresh and s.op <> nil and not s.entered then
        s.display = "-0"                   ## an operator was just pressed: the number about to be typed is negative
        s.fresh = false
        s.entered = true
        return
    end
    if s.display.startsWith("-") then
        s.display = s.display.substr(2)
    else
        s.display = "-" + s.display
    end
    if s.display == "0" or s.display == "-0" then
        s.fresh = false
        s.entered = true
    end
end

func calcBackspace(s)
    if s.fresh then
        return                             ## a result is not edited
    end
    var text = s.display.substr(1, s.display.len() - 1)
    if text == "" or text == "-" then
        text = "0"
    end
    s.display = text
end

## One key: a digit, ".", "+", "-", "*", "/", "=", "%", "+/-", "<" (backspace), "C" or "AC".
func calcPress(s, key)
    if s.error then
        calcReset(s)
    end
    switch key
    case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "."
        calcDigit(s, key)
    case "+", "-", "*", "/"
        calcOperator(s, key)
    case "="
        calcEquals(s)
    case "%"
        calcPercent(s)
    case "+/-"
        calcNegate(s)
    case "<"
        calcBackspace(s)
    case "C"
        s.display = "0"
        s.fresh = true
        s.entered = false
    case "AC"
        calcReset(s)
    end
    return s
end
