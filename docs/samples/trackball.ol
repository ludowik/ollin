## Rotation « trackball » RÉUTILISABLE — glisser à la souris ou au doigt fait tourner
## une scène ou un objet, sans blocage de cardan (composition de quaternions).
##
##   orient()  → quaternion d'orientation courant, à passer à graphics.rotateq
##   dragging  → vrai pendant un glissement (pour suspendre une rotation automatique)
##   idle(degresParSeconde)  → rotation douce au repos, à appeler dans draw()
##
## Câblage côté programme hôte (les callbacks mouse.* sont GLOBAUX au moteur, un
## module ne peut pas les capter lui-même → 3 relais) :
##
##   import "trackball.ol"
##   global ball = Trackball()
##   func mouse.pressed(x, y)  ball.press(x, y) end
##   func mouse.moved(x, y)    ball.move(x, y)  end
##   func mouse.released(x, y) ball.release()   end
##   ## dans draw() : graphics.rotateq(ball.orient())

class Trackball
    func init(sensitivity)
        self.q = graphics.quat()
        self.dragging = false
        self.lastx = 0
        self.lasty = 0
        ## Degrés de rotation par pixel glissé. Le défaut ne s'applique qu'en l'ABSENCE
        ## d'argument : `or` prendrait aussi le dessus sur 0, qui fige volontairement la
        ## rotation (zéro est faux en Ollin).
        self.sensitivity = 0.5
        if sensitivity <> nil then
            self.sensitivity = sensitivity
        end
    end

    func orient()
        return self.q
    end

    func press(x, y)
        self.dragging = true
        self.lastx = x
        self.lasty = y
    end

    func release()
        self.dragging = false
    end

    func move(x, y)
        if not self.dragging then
            return
        end
        var dx = (x - self.lastx) * self.sensitivity
        var dy = (y - self.lasty) * self.sensitivity
        self.lastx = x
        self.lasty = y
        ## dx → rotation autour de Y, dy → autour de X ; composée À GAUCHE, donc dans le
        ## repère de l'ÉCRAN : le glissement suit le doigt quelle que soit l'orientation.
        var spin = graphics.quatAxis(0, 1, 0, dx).mul(graphics.quatAxis(1, 0, 0, dy))
        self.q = spin.mul(self.q)
    end

    ## Rotation douce quand l'utilisateur ne glisse pas — sans effet pendant un glissement.
    func idle(degresParSeconde)
        if self.dragging then
            return
        end
        self.q = graphics.quatAxis(0, 1, 0, deltaTime * degresParSeconde).mul(self.q)
    end
end
