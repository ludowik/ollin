### Fixture : un module qui déclare TOUTES les sortes de noms exportables.
    Importé avec un alias par regressions.ol, qui vérifie que chacun est rangé
    dans la map du module (bug vécu : un enum n'était pas exporté).
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
var expHote = {}
enum expHote.dansUneMap X end   ## cible chaînée : n'exporte AUCUN nom propre
