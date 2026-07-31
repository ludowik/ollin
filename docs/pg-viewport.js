// Recale l'app (body en position:fixed) sur le VISUAL VIEWPORT.
//
// Sur mobile — iOS surtout — l'ouverture du clavier retrecit le visual viewport
// (la zone reellement visible) mais PAS le layout viewport. Une app ancree en
// position:fixed au layout viewport reste donc calee en haut de la PAGE, pas en
// haut du VISIBLE : des que le navigateur fait glisser le visual viewport (au
// focus, ou quand on defile clavier ouvert), la barre d'outils derive vers le
// haut puis disparait.
//
// Aucune propriete CSS statique ne corrige ca. La seule solution fiable : ecouter
// visualViewport (resize + scroll) et repositionner activement l'app pour qu'elle
// couvre exactement le visible — hauteur = vv.height, decalage = vv.offsetTop.
// Ainsi la barre reste collee au bord haut du visible, clavier ouvert ou non.
//
// Renvoie un disposer (retire les ecouteurs + remet le body a plat).
export function pinToVisualViewport() {
    const vv = window.visualViewport;
    if (!vv) {
        return () => {};
    }
    const body = document.body;
    const sync = () => {
        body.style.height = vv.height + 'px';
        body.style.transform = 'translateY(' + vv.offsetTop + 'px)';
    };
    vv.addEventListener('resize', sync);
    vv.addEventListener('scroll', sync);
    sync();
    return () => {
        vv.removeEventListener('resize', sync);
        vv.removeEventListener('scroll', sync);
        body.style.height = '';
        body.style.transform = '';
    };
}
