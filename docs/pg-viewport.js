// Realigns the app (a body in position:fixed) on the VISUAL VIEWPORT.
//
// On mobile — iOS above all — opening the keyboard shrinks the visual viewport (the area
// actually visible) but NOT the layout viewport. An app anchored in position:fixed to the
// layout viewport therefore stays aligned with the top of the PAGE rather than the top of what
// is VISIBLE: as soon as the browser slides the visual viewport (on focus, or when scrolling
// with the keyboard up), the toolbar drifts upwards and then disappears.
//
// No static CSS property fixes this. The only reliable answer is to listen to visualViewport
// (resize and scroll) and actively reposition the app so that it covers exactly what is
// visible — height = vv.height, offset = vv.offsetTop. The bar then stays against the top edge
// of the visible area, keyboard up or not.
//
// Returns a disposer, which removes the listeners and lays the body flat again.
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
