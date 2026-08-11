## Distance de vue auto-adaptative RÉUTILISABLE (terrain streamé par chunks).
##
## Encapsule le rayon courant, ses bornes, le mode manuel et l'auto-adaptation : en
## vsync verrouillé, deltaTime ne révèle la marge que quand des frames débordent, donc
## on mesure la PART de frames lentes sur une fenêtre, par rapport à la cadence
## d'affichage MESURÉE (un mobile bridé à 30 Hz garde sa puissance de calcul). Les frames irréelles (> STALL_DT,
## arrière-plan/reprise) sont ignorées. Possède aussi trois boutons (haut-droite) :
## − / + basculent en réglage manuel, A rebascule en auto-adaptation.
##
## update() renvoie :  1 = le rayon a GRANDI (relancer le streaming),
##                    -1 = le rayon a RÉTRÉCI (décharger l'anneau extérieur),
##                     0 = inchangé.
## hit() renvoie :     1 / -1 (idem), 2 = bouton consommé sans changement (borne
##                     atteinte), 0 = hors boutons (à traiter ailleurs, ex. joystick).
##
## Câblage côté hôte :
##   import "view_distance.ol"
##   global vd = ViewDistance(4, 1, 24)       ## 4e arg = cadence d'AMORCE (défaut 60) ;
##                                            ## la cadence réelle est ensuite mesurée
##   func mouse.pressed(x, y)
##       var ev = vd.hit(x, y)
##       if ev == 1 then streaming = true
##       elseif ev == -1 then streamUnload(lastcx, lastcz, 0)
##       elseif ev == 0 then pad.press(x, y) end   ## ev == 2 : rien à faire
##   end
##   ## dans draw() : boucler sur vd.radius, puis
##   ##   var ev = vd.update(deltaTime, streaming)
##   ##   if ev == 1 then streaming = true elseif ev == -1 then streamUnload(pcx, pcz, 0) end
##   ##   ... vd.draw()  (boutons)  ...  vd.mode() → "auto"/"manuel"

class ViewDistance
    func init(start, lo, hi, fps = 60)
        self.radius = start
        self.lo = lo
        self.hi = hi          ## filet de sécurité ; la vraie limite vient du FPS/mémoire
        self.manual = false
        ## Cadence d'affichage MESURÉE, pas supposée : un mobile peut brider à 30 Hz sans
        ## que la puissance de calcul soit divisée pour autant. Avec un seuil calé sur 60,
        ## chaque frame paraîtrait en retard et le rayon s'effondrerait jusqu'à `lo`.
        ## `fps` ne sert donc que d'amorce, remplacée dès la première fenêtre par la
        ## période observée (cf. update).
        self.period = 1.0 / fps
        self.PERIOD_MIN = 1.0 / 121       ## bornes plausibles d'un écran (121 Hz … 29 Hz)
        self.PERIOD_MAX = 1.0 / 29
        self.SLOW_MARGIN = 1.25           ## au-delà de période × marge = frame « en retard »
        self.SLOW_DT = self.period * self.SLOW_MARGIN
        self.STALL_DT = 0.30              ## frame irréelle (onglet en arrière-plan, reprise)
        self.fastest = 0.0                ## plus courte frame de la fenêtre courante
        self.measured = false             ## la cadence a-t-elle déjà été mesurée ?
        self.WIN = 0.5
        ## Une fenêtre doit aussi compter assez de frames : à 30 Hz, 0,5 s n'en donne que
        ## 15 et la part de frames lentes devient trop bruitée pour décider (une seule
        ## frame de retard y pèse 7 %). La fenêtre s'allonge donc quand la cadence baisse.
        self.MIN_N = 30
        self.GROW = 0.03      ## ne grandit que si TRÈS peu de frames lentes → garde de la marge
        self.DROP = 0.25      ## large zone morte [GROW;DROP] = ne chasse pas la limite, n'oscille pas
        self.RELAX = 20.0     ## re-teste le plafond appris rarement (évite le va-et-vient)
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
        self.MARGIN = 12      ## marge bord droit
        self.GAP = 10         ## écart entre boutons
    end

    func mode()
        return self.manual and "manuel" or "auto"
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
        if self.fastest == 0.0 or dt < self.fastest then self.fastest = dt end
        if self.t < self.WIN or self.n < self.MIN_N then return 0 end
        ## Calibrer AVANT de juger : la fenêtre d'amorce serait sinon comparée à une
        ## cadence supposée, et une seule fenêtre mal jugée suffit à rétrécir le rayon.
        if self.measurePeriod() then
            self.t = 0.0
            self.n = 0
            self.slow = 0
            return 0
        end
        var memFull = mem() > self.MEM_MAX   ## lu une fois par fenêtre, pas à chaque frame
        var ev = 0
        if (memFull or self.slow > self.n * self.DROP) and self.radius > self.lo then
            self.cap = self.radius - 1
            self.radius = math.clamp((self.good + self.radius) // 2, self.lo, self.radius - 1)
            self.step = 1
            self.stable = 0.0
            ev = -1
        elseif self.slow < self.n * self.GROW then
            self.good = self.radius
            if self.radius < self.hi and self.radius < self.cap and not memFull then
                self.radius = math.min(self.radius + self.step, math.min(self.hi, self.cap))
                self.step = self.step * 2
                self.stable = 0.0
                ev = 1
            else
                self.step = 1
                self.stable = self.stable + self.t
                if self.radius == self.cap and self.stable >= self.RELAX and not memFull then
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

    ## Période de rafraîchissement = plus COURTE frame de la fenêtre : aucune frame ne peut
    ## battre le vsync, donc la plus rapide le donne. En vsync les frames ratées coûtent un
    ## multiple de la période (33 ms, 50 ms…), jamais 5 % de plus, d'où la fiabilité du
    ## minimum. Elle descend d'un coup (cadence plus élevée constatée) mais ne remonte que
    ## de 5 % par fenêtre, pour ne pas prendre un régime dégradé passager pour la cadence de
    ## l'écran. Bornée aux cadences plausibles → au pire on vise 30 fps.
    ## Renvoie true la PREMIÈRE fois (fenêtre d'amorce, à ne pas juger).
    func measurePeriod()
        if self.fastest <= 0 then
            return false
        end
        var first = not self.measured
        var p = self.fastest
        if self.measured and self.fastest > self.period then
            p = math.min(self.fastest, self.period * 1.05)   ## remontée prudente
        end
        self.period = math.clamp(p, self.PERIOD_MIN, self.PERIOD_MAX)
        self.SLOW_DT = self.period * self.SLOW_MARGIN
        self.fastest = 0.0
        self.measured = true
        return first
    end

    ## Cadence d'affichage détectée (Hz), pour l'affichage de mise au point.
    func hz()
        return math.floor(1.0 / self.period + 0.5)
    end

    ## Boutons alignés de droite à gauche : 0 = +, 1 = −, 2 = A.
    func btnX(i)   return W - self.MARGIN - self.BTN - i * (self.BTN + self.GAP) end

    ## Traite un appui : + / − → passe en manuel et ajuste le rayon (borné) ; A → rebascule
    ## en auto-adaptation. Renvoie 1 (grandi) / -1 (rétréci) / 2 (bouton consommé sans
    ## changement de rayon) / 0 (aucun bouton → à traiter ailleurs).
    func hit(x, y)
        if y < self.BTN_Y or y > self.BTN_Y + self.BTN then
            return 0
        end
        var xp = self.btnX(0)
        if x >= xp and x <= xp + self.BTN then
            self.manual = true
            if self.radius < self.hi then
                self.radius = self.radius + 1
                return 1
            end
            return 2
        end
        var xm = self.btnX(1)
        if x >= xm and x <= xm + self.BTN then
            self.manual = true
            if self.radius > self.lo then
                self.radius = self.radius - 1
                return -1
            end
            return 2
        end
        var xa = self.btnX(2)
        if x >= xa and x <= xa + self.BTN then
            self.manual = false
            return 2
        end
        return 0
    end

    func draw()
        ## [index bouton, libellé, nudge X du glyphe] — le "−" est plus étroit
        var btns = [[0, "+", -9], [1, "-", -6], [2, "A", -9]]
        var ty = self.BTN_Y + self.BTN / 2 - 16
        graphics.noStroke()
        for b in btns do
            var x = self.btnX(b[1])
            graphics.fill(Color(0, 0, 0, 0.38))
            if b[2] == "A" and not self.manual then
                graphics.fill(Color(0.30, 0.70, 1.00, 0.55))   ## A allumé = auto actif
            end
            graphics.rect(x, self.BTN_Y, self.BTN, self.BTN)
            graphics.stroke(colors.WHITE)
            graphics.fontSize(30)
            graphics.text(b[2], x + self.BTN / 2 + b[3], ty)
        end
    end
end
