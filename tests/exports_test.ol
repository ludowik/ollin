### Fixture: a module declaring EVERY kind of exportable name.
    Imported under an alias by regressions.ol, which checks that each one is filed
    into the module's map (a bug once seen: an enum was not exported).
###
var expVar = 1
global expGlobal = 2
func expFunc()
    return 3
end
class ExpClass
    func init()
        self.v = 4
    end
end
enum ExpEnum A, B end
var expHost = {}
enum expHost.inAMap X end   ## a chained target: it exports NO name of its own
