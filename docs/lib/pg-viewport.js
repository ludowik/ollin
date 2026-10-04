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
    // A rotation is the case the two visualViewport events do not cover: iOS may fire neither, or fire them
    // with the sizes of the orientation just left, and the app would keep the old height and offset — the
    // toolbar above the screen and an empty strip below. The window's own events catch the turn, and the
    // sizes are read again as they settle.
    let settle = [];
    const resync = () => {
        sync();
        settle.forEach(clearTimeout);
        settle = [100, 300, 700, 1200].map((ms) => setTimeout(sync, ms));
    };
    const turn = screen.orientation;
    vv.addEventListener('resize', sync);
    vv.addEventListener('scroll', sync);
    window.addEventListener('resize', resync);
    window.addEventListener('orientationchange', resync);
    if (turn) {
        turn.addEventListener('change', resync);
    }
    sync();
    return () => {
        vv.removeEventListener('resize', sync);
        vv.removeEventListener('scroll', sync);
        window.removeEventListener('resize', resync);
        window.removeEventListener('orientationchange', resync);
        if (turn) {
            turn.removeEventListener('change', resync);
        }
        settle.forEach(clearTimeout);
        body.style.height = '';
        body.style.transform = '';
    };
}
