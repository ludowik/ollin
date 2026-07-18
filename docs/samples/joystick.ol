## Joystick analogique tactile RÉUTILISABLE — zone CIRCULAIRE, neutre au centre.
##
## Un doigt posé DANS le disque arme le contrôle et le garde actif même s'il en sort
## (valeurs clampées). Le neutre est le CENTRE du disque :
##   steer()    → [-1;1]  décalage horizontal au centre (<0 = gauche, >0 = droite)
##   throttle() → [-1;1]  décalage vertical au centre   (>0 = avant, <0 = arrière)
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
##   ##              avancer de  pad.throttle() * VITESSE * deltaTime  (négatif = arrière)
##   ## et à la fin : pad.draw()

class Joystick
    func init()
        self.active = false       ## armé (doigt posé dans le disque), reste vrai s'il en sort
        self.px = 0               ## position courante du doigt
        self.py = 0
        self.center_frac = 0.66   ## centre (neutre) vertical, fraction de H
        self.radius_frac = 0.17   ## rayon du disque, fraction de H
        self.dead = 0.10          ## zone morte (neutre) autour du centre, fraction du rayon
    end

    func cx()
        return W / 2
    end
    func cy()
        return H * self.center_frac
    end
    func radius()
        return H * self.radius_frac
    end

    func press(x, y)
        self.px = x
        self.py = y
        var dx = x - self.cx()
        var dy = y - self.cy()
        self.active = (dx * dx + dy * dy) <= self.radius() * self.radius()   ## armé si DANS le disque
    end
    func move(x, y)
        self.px = x
        self.py = y
    end
    func release()
        self.active = false
    end

    ## Zone morte au centre + remise à l'échelle : 0 dans la zone morte, ±1 au bord.
    func shape(v)
        if v > 0 - self.dead and v < self.dead then
            return 0.0
        end
        var sign = 1.0
        if v < 0 then
            sign = -1.0
        end
        return sign * math.clamp((math.abs(v) - self.dead) / (1.0 - self.dead), 0.0, 1.0)
    end

    ## Virage ∈ [-1;1] : décalage horizontal du doigt au centre.
    func steer()
        if not self.active or W <= 0 then
            return 0.0
        end
        return self.shape((self.px - self.cx()) / self.radius())
    end

    ## Poussée ∈ [-1;1] : décalage vertical au centre (haut = avant, bas = arrière).
    func throttle()
        if not self.active or H <= 0 then
            return 0.0
        end
        return self.shape((self.cy() - self.py) / self.radius())
    end

    func draw()
        var cx = self.cx()
        var cy = self.cy()
        var r = self.radius()
        graphics.noStroke()
        graphics.fill(Color(1, 1, 1, 0.06))
        graphics.circle(cx, cy, r)                    ## zone circulaire (reflète le fonctionnement réel)
        graphics.fill(Color(1, 1, 1, 0.16))
        graphics.circle(cx, cy, r * self.dead + 4)    ## repère du neutre au centre
        if self.active then
            ## pouce bridé au bord du disque (comme un vrai stick)
            var dx = self.px - cx
            var dy = self.py - cy
            var d = math.sqrt(dx * dx + dy * dy)
            var kx = self.px
            var ky = self.py
            if d > r then
                kx = cx + dx / d * r
                ky = cy + dy / d * r
            end
            graphics.stroke(Color(1, 1, 1, 0.45))
            graphics.line(cx, cy, kx, ky)
            graphics.noStroke()
            graphics.fill(Color(0.45, 0.65, 1.0, 0.85))
            graphics.circle(kx, ky, 20)
        end
    end
end
