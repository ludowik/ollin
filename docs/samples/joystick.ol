## Joystick analogique tactile RÉUTILISABLE.
##
## Zone active = bas de l'écran (à partir de zone_top × H). Un doigt posé DANS la
## zone arme le contrôle et le garde actif même s'il en sort (valeurs clampées).
##   steer()    → [-1;1]  distance horizontale au centre  (<0 = gauche, >0 = droite)
##   throttle() → [0;1]   distance verticale au bas de la zone (1 = plein avant)
##
## Câblage côté programme hôte (les callbacks mouse.* sont GLOBAUX au moteur, un
## module ne peut pas les capter lui-même → 3 relais + un draw) :
##
##   import "joystick.ol"
##   global pad = Joystick()
##   func mouse.pressed(x, y)  pad.press(x, y)  end
##   func mouse.moved(x, y)    pad.move(x, y)   end
##   func mouse.released(x, y) pad.release()    end
##   ## dans draw() : yaw -= pad.steer() * VITESSE_ROT * deltaTime
##   ##              avancer de  pad.throttle() * VITESSE * deltaTime
##   ## et à la fin : pad.draw()

class Joystick
    func init()
        self.active = false      ## armé (doigt posé dans la zone), reste vrai s'il en sort
        self.px = 0              ## position courante du doigt
        self.py = 0
        self.zone_top = 0.66     ## haut de la zone (fraction de H)
        self.dead = 0.06         ## zone morte du virage (près du centre = tout droit)
    end

    ## Ordonnée du haut de la zone active (px).
    func top()
        return H * self.zone_top
    end

    ## Relais d'entrée — à brancher sur mouse.pressed/moved/released.
    func press(x, y)
        self.px = x
        self.py = y
        self.active = y >= self.top()     ## armé seulement si on démarre DANS la zone
    end
    func move(x, y)
        self.px = x
        self.py = y
    end
    func release()
        self.active = false
    end

    ## Virage ∈ [-1;1] : distance horizontale du doigt au centre (zone morte au milieu).
    func steer()
        if not self.active then
            return 0.0
        end
        var s = (self.px - W / 2) / (W / 2)
        if s > 0 - self.dead and s < self.dead then
            return 0.0
        end
        return math.clamp(s, -1.0, 1.0)
    end

    ## Poussée ∈ [0;1] : distance verticale du doigt au bas de la zone (hors zone par
    ## le haut → clampé à 1 = plein avant).
    func throttle()
        if not self.active then
            return 0.0
        end
        return math.clamp((H - self.py) / (H - self.top()), 0.0, 1.0)
    end

    ## Retour visuel : axe central + poignée reliée à l'ancre bas-centre (si actif).
    func draw()
        var y0 = self.top()
        var ax = W / 2
        graphics.fill(Color(1, 1, 1, 0.06))
        graphics.rect(0, y0, W, H - y0)
        graphics.fill(Color(1, 1, 1, 0.14))
        graphics.rect(ax - 1, y0, 2, H - y0)
        if self.active then
            graphics.stroke(Color(1, 1, 1, 0.45))
            graphics.line(ax, H - 4, self.px, self.py)
            graphics.noStroke()
            graphics.fill(Color(0.45, 0.65, 1.0, 0.85))
            graphics.circle(self.px, self.py, 20)
        end
    end
end
