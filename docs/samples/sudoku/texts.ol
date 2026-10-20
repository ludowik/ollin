## The TEXTS of Sudoku, in the languages the game speaks: French (the default) and English. The French strings are
## the translation the game asks for, not a slip in the language of the repository.
##
## Every language has the same keys, which docs/samples/sudoku/texts_test.ol checks. A text is a string, except the ones
## that take figures (the hints, the names of a unit, the help), which are functions of them.

const LANGUAGES = ["fr", "en"]      ## the order of the language menu; the first one is the default

global i18n = {lang: LANGUAGES[1]}

const TEXTS = {
    fr: {
        name: "Français",
        level: "Niveau",
        levelEasy: "Facile",
        levelMedium: "Moyen",
        levelHard: "Difficile",
        levelExpert: "Expert",
        newGame: "Nouvelle partie",
        chooseLevel: "Choisissez un niveau",
        daily: "Grille du jour",
        options: "Options",
        menuHelp: "Comment jouer",
        menuLanguage: "Langue",
        menuSoundOn: "Son : activé",
        menuSoundOff: "Son : désactivé",
        menuErrorsOn: "Erreurs en rouge : oui",
        menuErrorsOff: "Erreurs en rouge : non",
        menuInputCell: "Saisie : case puis chiffre",
        menuInputDigit: "Saisie : chiffre puis cases",
        menuBack: "Retour au jeu",
        back: "Retour",
        tapBack: "touchez n'importe où pour revenir",
        pencil: "Crayon",
        erase: "Effacer",
        undo: "Annuler",
        hint: "Indice",
        generating: "Préparation de la grille",
        won: "Grille résolue !",
        hintNone: "Plus d'indice pour cette grille.",
        hintMistake: "Un chiffre est faux : il est entouré.",
        hintNaked: func(h)
            return "La case de la ligne {h.row}, colonne {h.col}, ne peut contenir que le {h.digit} : tous les autres chiffres sont déjà dans sa ligne, sa colonne ou son carré."
        end,
        hintHidden: func(h)
            return "Dans {h.unit}, le {h.digit} ne peut aller que dans la case entourée."
        end,
        hintPlain: func(h)
            return "Aucune technique simple ici. La case entourée contient un {h.digit}."
        end,
        unitRow: func(n)
            return "la ligne {n}"
        end,
        unitColumn: func(n)
            return "la colonne {n}"
        end,
        unitBox: func(n)
            return "le carré {n}"
        end,
        help: func(r)
            return [
                "Remplissez la grille pour que chaque ligne, chaque colonne et chaque carré de {r.box}x{r.box} contienne une seule fois les chiffres de 1 à {r.size}.",
                "Touchez une case, puis un chiffre du pavé. Dans les options, vous pouvez aussi choisir un chiffre, puis toucher plusieurs cases à la suite.",
                "Le crayon note les chiffres possibles dans une case. Poser un chiffre l'efface des notes de sa ligne, de sa colonne et de son carré.",
                "Un indice entoure une case et explique comment trouver son chiffre ; vous en avez {r.hints} par grille. Si un chiffre est faux, l'indice le montre sans être compté.",
                "Les chiffres en conflit apparaissent en rouge, sauf si vous désactivez cette aide dans les options. Annuler remonte jusqu'au début de la grille.",
                "La grille du jour est la même pour tous ce jour-là, à chaque niveau. Votre partie est sauvegardée au fil du jeu."
            ]
        end
    },
    en: {
        name: "English",
        level: "Level",
        levelEasy: "Easy",
        levelMedium: "Medium",
        levelHard: "Hard",
        levelExpert: "Expert",
        newGame: "New game",
        chooseLevel: "Choose a level",
        daily: "Puzzle of the day",
        options: "Options",
        menuHelp: "How to play",
        menuLanguage: "Language",
        menuSoundOn: "Sound: on",
        menuSoundOff: "Sound: off",
        menuErrorsOn: "Errors in red: yes",
        menuErrorsOff: "Errors in red: no",
        menuInputCell: "Input: cell, then digit",
        menuInputDigit: "Input: digit, then cells",
        menuBack: "Back to game",
        back: "Back",
        tapBack: "tap anywhere to go back",
        pencil: "Pencil",
        erase: "Erase",
        undo: "Undo",
        hint: "Hint",
        generating: "Preparing the grid",
        won: "Solved!",
        hintNone: "No hint left for this puzzle.",
        hintMistake: "A digit is wrong: it is circled.",
        hintNaked: func(h)
            return "The cell in row {h.row}, column {h.col}, can only hold the {h.digit}: every other digit is already in its row, its column or its box."
        end,
        hintHidden: func(h)
            return "In {h.unit}, the {h.digit} can only go in the circled cell."
        end,
        hintPlain: func(h)
            return "No simple technique here. The circled cell holds a {h.digit}."
        end,
        unitRow: func(n)
            return "row {n}"
        end,
        unitColumn: func(n)
            return "column {n}"
        end,
        unitBox: func(n)
            return "box {n}"
        end,
        help: func(r)
            return [
                "Fill the grid so that every row, every column and every {r.box}x{r.box} box holds each digit from 1 to {r.size} once.",
                "Tap a cell, then a digit on the pad. In the options you can also pick a digit first, then tap several cells in a row.",
                "The pencil notes the digits a cell could hold. Placing a digit takes it out of the notes of its row, its column and its box.",
                "A hint circles a cell and explains how to find its digit; you have {r.hints} per puzzle. If a digit is wrong, the hint shows it without being counted.",
                "Digits in conflict show in red, unless you switch that help off in the options. Undo goes all the way back to the start of the puzzle.",
                "The puzzle of the day is the same for everyone that day, at every level. Your game is saved as you play."
            ]
        end
    }
}

## The text for a key, in the current language.
func tr(key)
    return TEXTS[i18n.lang][key]
end

## The words of a hint ({kind, cell, digit, unit}, see hintFor), which is left as it is: the screen still reads its
## unit as a number. Uses the tables of board.ol and unitInfo of solver.ol.
func hintText(h)
    if h.kind == "mistake" then
        return tr("hintMistake")
    end
    var words = {digit: h.digit, row: board.rowOf[h.cell], col: board.colOf[h.cell]}
    if h.kind == "naked" then
        return tr("hintNaked")(words)
    elseif h.kind == "hidden" then
        var kind, n = unitInfo(h.unit)
        words.unit = tr({row: "unitRow", column: "unitColumn", box: "unitBox"}[kind])(n)
        return tr("hintHidden")(words)
    end
    return tr("hintPlain")(words)
end

## Switches language; an unknown code changes nothing. Says whether it did.
func setLanguage(code)
    if TEXTS[code] == nil then
        return false
    end
    i18n.lang = code
    return true
end
