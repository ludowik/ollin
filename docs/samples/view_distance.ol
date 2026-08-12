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
        ## `fps` ne sert que d'amorce, remplacé dès la première fenêtre par la cadence VOTÉE.
        ##
        ## Le vote plutôt que la plus courte frame : le navigateur livre parfois deux images
        ## rapprochées (rattrapage), et 2 % de telles frames suffisaient à faire croire à un
        ## écran 120 Hz, donc à traiter toutes les frames normales comme des retards.
        ## Ici chaque cadence plausible compte ses frames « à l'heure » (dt <= période ×
        ## MARGIN) et on retient la PLUS ÉLEVÉE qui en réunit VOTE_PART : quelques frames
        ## aberrantes ne pèsent alors rien.
        self.CAD = [120, 90, 60, 50, 40, 30]   ## cadences candidates, décroissantes
        self.ok = [0, 0, 0, 0, 0, 0]           ## frames à l'heure pour chaque candidate
        self.MARGIN = 1.25                     ## tolérance sur la période (= seuil de retard)
        self.VOTE_PART = 0.7                   ## part de frames à l'heure pour élire une cadence
        self.hzKeep = fps                      ## cadence retenue (amorce)
        self.voted = false                     ## une cadence a-t-elle déjà été élue ?
        self.miss = 0                          ## fenêtres consécutives ne confirmant pas hzKeep
        ## La cadence d'un écran ne change quasiment jamais : une baisse du vote est d'abord
        ## mise sur le compte d'une surcharge passagère (sinon un rendu qui décroche ferait
        ## croire à un écran plus lent, et le repli du rayon ne se déclencherait plus). Elle
        ## n'est adoptée qu'après DEMOTE fenêtres — le temps qu'un vrai bridage se confirme.
        self.DEMOTE = 20
        self.STALL_DT = 0.30              ## frame irréelle (onglet en arrière-plan, reprise)
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
        self.BTN_MARGIN = 12  ## marge bord droit
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
        for j = 1, #self.CAD do
            if dt <= self.MARGIN / self.CAD[j] then
                self.ok[j] = self.ok[j] + 1
            end
        end
        if self.t < self.WIN or self.n < self.MIN_N then return 0 end
        ## La cadence est élue sur la MÊME fenêtre que celle qu'on juge : les frames en
        ## retard sont exactement celles qui ne sont pas « à l'heure » pour cette cadence.
        var first = not self.voted
        self.slow = self.n - self.voteCadence()
        if first then
            self.t = 0.0                       ## fenêtre d'amorce : elle a servi à élire la
            self.n = 0                         ## cadence, la juger n'aurait aucun sens
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

    ## Élit la cadence de la fenêtre et renvoie le nombre de frames à l'heure pour elle.
    ## Une cadence plus basse que celle retenue n'est adoptée qu'après DEMOTE fenêtres.
    func voteCadence()
        var vote = self.CAD[#self.CAD]
        var kept = self.ok[#self.CAD]
        for j = 1, #self.CAD do
            if self.ok[j] >= self.n * self.VOTE_PART then
                vote = self.CAD[j]
                kept = self.ok[j]
                break
            end
        end
        if not self.voted then
            self.hzKeep = vote                 ## première élection : adoptée telle quelle,
            self.voted = true                  ## sinon l'amorce fausserait le tout premier jugement
            self.miss = 0
        elseif vote >= self.hzKeep then
            self.hzKeep = vote
            self.miss = 0
        else
            self.miss = self.miss + 1
            if self.miss >= self.DEMOTE then
                self.hzKeep = vote
                self.miss = 0
            end
        end
        ## Frames à l'heure pour la cadence RETENUE (pas pour celle votée) : c'est elle qui
        ## définit ce qu'est un retard.
        var atTime = kept
        for j = 1, #self.CAD do
            if self.CAD[j] == self.hzKeep then
                atTime = self.ok[j]
            end
            self.ok[j] = 0
        end
        return atTime
    end

    ## Cadence d'affichage retenue (Hz), affichable pour la mise au point.
    func hz()
        return self.hzKeep
    end

    ## Boutons alignés de droite à gauche : 0 = +, 1 = −, 2 = A.
    func btnX(i)   return W - self.BTN_MARGIN - self.BTN - i * (self.BTN + self.GAP) end

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
