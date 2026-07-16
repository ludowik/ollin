## Distance de vue auto-adaptative RÉUTILISABLE (terrain streamé par chunks).
##
## Encapsule le rayon courant, ses bornes, le mode manuel et l'auto-adaptation : en
## vsync verrouillé, deltaTime ne révèle la marge que quand des frames débordent, donc
## on mesure la PART de frames lentes sur une fenêtre. Les frames irréelles (> STALL_DT,
## arrière-plan/reprise) sont ignorées. Possède aussi les deux boutons − / + (haut-droite)
## qui basculent en réglage manuel.
##
## update() renvoie :  1 = le rayon a GRANDI (relancer le streaming),
##                    -1 = le rayon a RÉTRÉCI (décharger l'anneau extérieur),
##                     0 = inchangé.
## hit() renvoie :     1 / -1 (idem), 2 = bouton consommé sans changement (borne
##                     atteinte), 0 = hors boutons (à traiter ailleurs, ex. joystick).
##
## Câblage côté hôte :
##   import "view_distance.ol"
##   global vd = ViewDistance(4, 1, 24)
##   func mouse.pressed(x, y)
##       var ev = vd.hit(x, y)
##       if ev == 1 then streaming = true
##       elseif ev == -1 then stream_unload(lastcx, lastcz, 0)
##       elseif ev == 0 then pad.press(x, y) end   ## ev == 2 : rien à faire
##   end
##   ## dans draw() : boucler sur vd.radius, puis
##   ##   var ev = vd.update(deltaTime, streaming)
##   ##   if ev == 1 then streaming = true elseif ev == -1 then stream_unload(pcx, pcz, 0) end
##   ##   ... vd.draw()  (boutons)  ...  vd.mode() → "auto"/"manuel"

class ViewDistance
    func init(start, lo, hi)
        self.radius = start
        self.lo = lo
        self.hi = hi          ## filet de sécurité ; la vraie limite vient du FPS/mémoire
        self.manual = false
        self.SLOW_DT = 0.021
        self.STALL_DT = 0.30
        self.WIN = 0.5
        self.GROW = 0.10
        self.DROP = 0.25
        self.RELAX = 8.0
        self.MEM_MAX = 110000000
        self.t = 0.0
        self.n = 0
        self.slow = 0
        self.step = 1         ## montée qui double (1,2,4,8…)
        self.cap = 999        ## plafond appris au décrochage, relâché après RELAX stable
        self.good = start     ## dernier rayon confirmé fluide (repli d'un dépassement)
        self.stable = 0.0
        self.BTN = 54
        self.BTN_Y = 40
    end

    func mode()
        if self.manual then return "manuel" end
        return "auto"
    end

    ## Ajuste le rayon selon la part de frames lentes de la fenêtre écoulée. Ne mesure
    ## ni pendant la cuisson (streaming) ni en manuel. Décrochage (mémoire pleine ou
    ## > DROP) → repli dichotomique vers `good` + plafond appris. Fluide (< GROW) →
    ## montée qui double ; au plafond, relâche après RELAX. Entre les deux → on tient.
    func update(dt, streaming)
        if dt <= 0 or dt >= self.STALL_DT or streaming or self.manual then
            return 0
        end
        self.t = self.t + dt
        self.n = self.n + 1
        if dt > self.SLOW_DT then self.slow = self.slow + 1 end
        if self.t < self.WIN then return 0 end
        var mem_full = mem() > self.MEM_MAX   ## lu une fois par fenêtre, pas à chaque frame
        var ev = 0
        if (mem_full or self.slow > self.n * self.DROP) and self.radius > self.lo then
            self.cap = self.radius - 1
            var back = (self.good + self.radius) // 2
            if back > self.radius - 1 then back = self.radius - 1 end
            if back < self.lo then back = self.lo end
            self.radius = back
            self.step = 1
            self.stable = 0.0
            ev = -1
        elseif self.slow < self.n * self.GROW then
            self.good = self.radius
            if self.radius < self.hi and self.radius < self.cap and not mem_full then
                self.radius = math.min(self.radius + self.step, math.min(self.hi, self.cap))
                self.step = self.step * 2
                self.stable = 0.0
                ev = 1
            else
                self.step = 1
                self.stable = self.stable + self.t
                if self.radius == self.cap and self.stable >= self.RELAX and not mem_full then
                    self.cap = self.cap + 1
                    self.stable = 0.0
                end
            end
        else
            self.step = 1
            self.stable = 0.0
        end
        self.t = 0.0
        self.n = 0
        self.slow = 0
        return ev
    end

    func btnXPlus()   return W - self.BTN - 12 end
    func btnXMinus()  return self.btnXPlus() - self.BTN - 10 end

    ## Traite un appui : bouton + / − → passe en manuel et ajuste le rayon (borné).
    ## Renvoie 1 (grandi) / -1 (rétréci) / 2 (bouton mais borne atteinte) /
    ## 0 (aucun bouton → à traiter ailleurs).
    func hit(x, y)
        if y < self.BTN_Y or y > self.BTN_Y + self.BTN then
            return 0
        end
        if x >= self.btnXPlus() and x <= self.btnXPlus() + self.BTN then
            self.manual = true
            if self.radius < self.hi then
                self.radius = self.radius + 1
                return 1
            end
            return 2
        end
        if x >= self.btnXMinus() and x <= self.btnXMinus() + self.BTN then
            self.manual = true
            if self.radius > self.lo then
                self.radius = self.radius - 1
                return -1
            end
            return 2
        end
        return 0
    end

    func draw()
        var xp = self.btnXPlus()
        var xm = self.btnXMinus()
        graphics.noStroke()
        graphics.fill(Color(0, 0, 0, 0.38))
        graphics.rect(xm, self.BTN_Y, self.BTN, self.BTN)
        graphics.rect(xp, self.BTN_Y, self.BTN, self.BTN)
        graphics.drawText("-", xm + self.BTN / 2 - 6, self.BTN_Y + self.BTN / 2 - 16, 30, colors.WHITE)
        graphics.drawText("+", xp + self.BTN / 2 - 9, self.BTN_Y + self.BTN / 2 - 16, 30, colors.WHITE)
    end
end
