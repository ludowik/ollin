## The TEXTS of Blockudoku, in the languages the game speaks: French (the default) and English. The French
## strings are the translation the game asks for, not a slip in the language of the repository.
##
## Every language has the same keys, which tests/blockudoku_texts_test.ol checks. A text is a string, except
## the help, which is a function of the figures of the rules: they live in the game's config, not here. A title is
## the text of its menu entry in capitals: the game does that when it draws it.

const LANGUAGES = ["fr", "en"]      ## the order of the language menu; the first one is the default

global i18n = {lang: LANGUAGES[1]}

const TEXTS = {
    fr: {
        name: "Français",
        score: "Score",
        best: "Meilleur",
        newGame: "Nouvelle partie",
        options: "Options",
        menuHelp: "Comment jouer",
        menuPieces: "Toutes les pièces",
        menuLanguage: "Langue",
        menuBack: "Retour au jeu",
        back: "Retour",
        shapes: "formes",
        tapBack: "touchez n'importe où pour revenir",
        gameOver: "PARTIE TERMINÉE",
        newBest: "Nouveau record !",
        help: func(r)
            return [
                "Faites glisser l'une des trois pièces sur la grille et relâchez pour la poser. Une pièce ne peut pas être tournée.",
                "Remplissez une ligne, une colonne ou un carré de {r.box}x{r.box} entier pour l'effacer. Plusieurs peuvent être effacés en même temps.",
                "Chaque case posée vaut {r.cell}. Chaque zone effacée vaut {r.zone}, et en effacer plusieurs à la fois multiplie ce gain par leur nombre.",
                "Effacez quelque chose plusieurs tours de suite et vous construisez une série : chaque tour de la série rapporte {r.streak} points de plus que le précédent.",
                "Une pièce pâle ne rentre nulle part sur la grille pour le moment. La partie est perdue quand aucune des trois pièces ne peut être posée.",
                "Votre partie est sauvegardée au fil du jeu, et votre meilleur score est conservé."
            ]
        end
    },
    en: {
        name: "English",
        score: "Score",
        best: "Best",
        newGame: "New game",
        options: "Options",
        menuHelp: "How to play",
        menuPieces: "All pieces",
        menuLanguage: "Language",
        menuBack: "Back to game",
        back: "Back",
        shapes: "shapes",
        tapBack: "tap anywhere to go back",
        gameOver: "GAME OVER",
        newBest: "New best!",
        help: func(r)
            return [
                "Drag one of the three pieces onto the grid and let go to place it. A piece cannot be turned.",
                "Fill a whole row, a whole column or a whole {r.box}x{r.box} box and it is cleared. Several at once are cleared together.",
                "Each cell you place scores {r.cell}. Each zone you clear scores {r.zone}, and clearing several zones at once multiplies that by their number.",
                "Clear something on consecutive turns and you build a streak: each turn of the streak adds {r.streak} more points than the one before.",
                "A faded piece fits nowhere on the grid right now. The game is over when none of the three pieces can be placed.",
                "Your game is saved as you play, and your best score is kept."
            ]
        end
    }
}

## The text for a key, in the current language.
func tr(key)
    return TEXTS[i18n.lang][key]
end

## Switches language; an unknown code changes nothing. Says whether it did.
func setLanguage(code)
    if TEXTS[code] == nil then
        return false
    end
    i18n.lang = code
    return true
end
