// PERF view (engine performance) — init(ctx), called by app.js once the views/perf.html fragment
// is mounted.
//   ctx = { root, getOllin, hardReload, navigate, v }
//
// The measurements come from two files, of different standing:
//   data/icount-history.json  the WORK, a historical series — without it the page has nothing to say
//   data/bench-snapshot.json  the TIME, a single reading — optional: its section disappears when
//                             the file is missing, and the rest of the page still stands
// Publishing new measurements means rewriting those files, and touching none of this code.
//
// Both charts are drawn at the container's REAL width, and redrawn when it changes. A frozen
// viewBox shrunk by CSS would bring an 11px font down to 3px on a phone — the chart would still
// be "visible" but unreadable.

export async function init(ctx) {
  const NBSP = " ";
  const fmt = n => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, NBSP);
  const pct = v => (Math.abs(v) < 0.05 ? "" : v > 0 ? "+" : "−") + Math.abs(v).toFixed(1).replace(".", ",") + " %";
  const millions = n => (n / 1e6).toFixed(1).replace(".", ",") + " M";
  const jourMois = iso => iso.slice(8, 10) + "/" + iso.slice(5, 7);

  const SVGNS = "http://www.w3.org/2000/svg";
  const el = (t, a) => {
    const n = document.createElementNS(SVGNS, t);
    for (const k in a) n.setAttribute(k, a[k]);
    return n;
  };
  const vider = n => {
    while (n.firstChild) n.removeChild(n.firstChild);
  };

  const bulle = document.getElementById("bulle");
  const souci = document.getElementById("souci");
  const svgCourbes = document.getElementById("courbes");
  const svgEcarts = document.getElementById("ecarts");

  function signaler(e) {
    souci.hidden = false;
    souci.textContent = "Les graphiques n'ont pas pu être dessinés (" + (e && e.message ? e.message : e) +
                        "). Les valeurs restent lisibles dans le tableau.";
  }

  // Data.
  let doc;
  try {
    const rep = await fetch("data/icount-history.json?v=" + ctx.v);
    if (!rep.ok) throw new Error("HTTP " + rep.status);
    doc = await rep.json();
  } catch (e) {
    signaler(e);
    return () => {};
  }

  // The time reading: when absent, the page stays valid without its section, which is removed
  // from the DOM rather than left empty — a heading over a hollow frame reads as a breakdown.
  let bench = null;
  try {
    const rep = await fetch("data/bench-snapshot.json?v=" + ctx.v);
    if (rep.ok) bench = await rep.json();
  } catch (e) {
    bench = null;
  }
  if (!bench) {
    // Every element to remove carries an id: aiming at another's neighbour ("the heading just
    // before the table") failed, the heading being a sibling of the scrolling CONTAINER rather
    // than of the table itself.
    ["titre-temps", "apropos-temps", "bloc-bench", "titre-detail", "defile-temps"]
      .forEach(id => document.getElementById(id).remove());
  }

  const JALONS = doc.jalons;
  const SERIES = doc.scripts.map(s => ({ id: s.id, nom: s.nom, classe: "s-" + s.id, css: "--s-" + s.id }));
  // ALL the series must be present: testing only one would leave `montrer()` computing y(null)
  // for the others, hence NaN coordinates with no message.
  const connu = j => SERIES.every(s => typeof j[s.id] === "number");
  const premier = JALONS.find(connu);
  const dernier = [...JALONS].reverse().find(connu);
  // No complete milestone: the file is unusable for the charts (a renamed series, values all
  // missing). Say why, rather than failing on premier.date.
  if (!premier) {
    signaler(new Error("aucun jalon ne porte les " + SERIES.length + " séries attendues : " +
                       SERIES.map(s => s.id).join(", ")));
    return () => {};
  }
  const MOIS = ["janvier", "février", "mars", "avril", "mai", "juin",
                "juillet", "août", "septembre", "octobre", "novembre", "décembre"];
  const enClair = iso => Number(iso.slice(8, 10)) + " " + MOIS[Number(iso.slice(5, 7)) - 1];
  const mesures = JALONS.filter(connu).length;

  document.getElementById("intro").textContent =
    "Ce que le moteur d'Ollin coûte à exécuter, mesuré de deux façons : le TRAVAIL qu'il " +
    "demande, suivi du " + enClair(premier.date) + " au " + enClair(dernier.date) + " " +
    dernier.date.slice(0, 4) + (bench ? ", et le TEMPS qu'il prend, relevé face à Lua et à Python." : ".");
  document.getElementById("apropos-travail").textContent =
    "Instructions exécutées par " + SERIES.map(s => s.nom).join(", ") + ". " +
    JALONS.length + " jalons, un par journée où le cœur du moteur a été touché" +
    (mesures < JALONS.length ? " — dont " + (JALONS.length - mesures) + " sans valeur, faute de compiler. " : ". ") +
    "Mesuré avec " + doc.outil + " ; " + doc.machine + ".";

  // Summaries.
  const boiteBilans = document.getElementById("bilans");
  SERIES.forEach(s => {
    const a = premier[s.id], b = dernier[s.id];
    const v = (b - a) / a * 100;
    const carte = document.createElement("div");
    carte.className = "bilan";
    const quoi = document.createElement("div");
    quoi.className = "quoi";
    const past = document.createElement("span");
    past.className = "pastille " + s.classe;
    quoi.append(past, document.createTextNode(s.nom));
    const val = document.createElement("div");
    val.className = "valeur";
    val.textContent = pct(v);
    const det = document.createElement("div");
    det.className = "detail";
    det.textContent = fmt(a) + " → " + fmt(b) + (v < 0 ? " (÷" + (a / b).toFixed(2).replace(".", ",") + ")" : "");
    carte.append(quoi, val, det);
    boiteBilans.append(carte);
  });

  // The reading keys carry the final value: on a phone the chart has no right margin left for an
  // end-of-curve label.
  const boiteCles = document.getElementById("cles");
  SERIES.forEach(s => {
    const w = document.createElement("span");
    const i = document.createElement("i");
    i.className = s.classe;
    const b = document.createElement("b");
    b.textContent = millions(dernier[s.id]);
    w.append(i, document.createTextNode(s.nom), b);
    boiteCles.append(w);
  });

  // Tooltip.
  function poser(cx, cy) {
    bulle.style.opacity = 1;
    const marge = 14, lb = bulle.offsetWidth, hb = bulle.offsetHeight;
    let px = cx + marge, py = cy - 10;
    if (px + lb > innerWidth - 8) px = Math.max(8, cx - lb - marge);
    if (py + hb > innerHeight - 8) py = innerHeight - hb - 8;
    if (py < 8) py = 8;
    bulle.style.left = px + "px";
    bulle.style.top = py + "px";
  }
  const masquer = () => { bulle.style.opacity = 0; };

  // With a finger, lifting emits pointerleave right after the press, so we only close on the
  // pointer leaving for a MOUSE, and let a press outside the chart close it otherwise.
  const horsGraphe = [];
  function fermerAilleurs(svg, effacer) {
    const h = ev => { if (!svg.contains(ev.target)) effacer(); };
    document.addEventListener("pointerdown", h, true);
    horsGraphe.push(h);
  }

  // The latest drawing publishes its hover functions here; the listeners themselves are
  // installed once and for all after the first drawing.
  let survolCourbes = null;
  let survolEcarts = null;

  // Curves.
  function dessinerCourbes(w) {
    const petit = w < 560;
    const h = petit ? Math.round(w * 0.86) : 400;
    const m = { t: 12, r: petit ? 12 : 92, b: petit ? 42 : 46, l: petit ? 40 : 58 };
    vider(svgCourbes);
    svgCourbes.setAttribute("viewBox", "0 0 " + w + " " + h);
    svgCourbes.setAttribute("width", w);
    svgCourbes.setAttribute("height", h);

    const iw = w - m.l - m.r, ih = h - m.t - m.b, n = JALONS.length;
    const x = i => m.l + i * iw / (n - 1);
    const haut = Math.max(...JALONS.filter(connu).flatMap(j => SERIES.map(s => j[s.id])));
    const pasY = 25e6;
    const ymax = Math.ceil(haut / 1e7) * 1e7;
    const y = v => m.t + ih - (v / ymax) * ih;

    const grille = el("g", { class: "grille" }), axe = el("g", { class: "axe" });
    for (let v = 0; v <= ymax; v += pasY) {
      grille.append(el("line", { x1: m.l, x2: m.l + iw, y1: y(v), y2: y(v) }));
      const t = el("text", { x: m.l - 8, y: y(v) + 4, "text-anchor": "end", class: "mono" });
      t.textContent = v === 0 ? "0" : (petit ? String(v / 1e6) : millions(v));
      axe.append(t);
    }
    if (petit) {
      const u = el("text", { x: m.l - 8, y: m.t - 1, "text-anchor": "end", class: "mono" });
      u.textContent = "M";
      axe.append(u);
    }
    svgCourbes.append(grille);

    const pas = petit ? 8 : 3;
    let vue = "";
    JALONS.forEach((j, i) => {
      if (i % pas !== 0 && i !== n - 1) return;
      const d = jourMois(j.date);
      if (d === vue) return;
      vue = d;
      const t = el("text", {
        x: x(i), y: h - m.b + 20, class: "mono",
        "text-anchor": i === n - 1 ? "end" : i === 0 ? "start" : "middle",
      });
      t.textContent = d;
      axe.append(t);
    });
    const leg = el("text", { x: m.l, y: h - m.b + 37, class: "mono discret" });
    leg.textContent = petit ? n + " jalons moteur" : n + " jalons — un par journée de commit moteur";
    axe.append(leg);
    svgCourbes.append(axe);

    SERIES.forEach(s => {
      let d = "", ouvert = false;
      JALONS.forEach((j, i) => {
        const v = j[s.id];
        if (v === null) { ouvert = false; return; }
        d += (ouvert ? " L" : " M") + x(i).toFixed(1) + " " + y(v).toFixed(1);
        ouvert = true;
      });
      svgCourbes.append(el("path", { class: "courbe", d: d.trim(), stroke: "var(" + s.css + ")" }));
      const dv = dernier[s.id];
      svgCourbes.append(el("circle", { cx: x(n - 1), cy: y(dv), r: 4.5, fill: "var(" + s.css + ")", class: "anneau" }));
      if (!petit) {
        const b = el("text", { x: x(n - 1) + 12, y: y(dv) + 4, class: "bout", fill: "var(" + s.css + ")" });
        b.textContent = millions(dv);
        svgCourbes.append(b);
      }
    });

    const viseur = el("line", { class: "viseur", y1: m.t, y2: m.t + ih });
    const points = el("g");
    svgCourbes.append(viseur, points);

    function montrer(i, cx, cy) {
      const j = JALONS[i];
      viseur.setAttribute("x1", x(i));
      viseur.setAttribute("x2", x(i));
      viseur.setAttribute("opacity", connu(j) ? 0.5 : 0);
      vider(points);
      if (connu(j)) {
        SERIES.forEach(s => points.append(el("circle", {
          cx: x(i), cy: y(j[s.id]), r: 4.5, fill: "var(" + s.css + ")", class: "anneau",
        })));
      }
      vider(bulle);
      const quand = document.createElement("div");
      quand.className = "quand";
      quand.textContent = j.date + "  ·  " + j.commit;
      bulle.append(quand);
      if (!connu(j)) {
        const l = document.createElement("div");
        l.className = "ligne";
        l.textContent = "valeur inconnue";
        bulle.append(l);
      } else {
        SERIES.forEach(s => {
          const l = document.createElement("div");
          l.className = "ligne";
          const i2 = document.createElement("i");
          i2.className = s.classe;
          const b = document.createElement("b");
          b.textContent = fmt(j[s.id]);
          const nm = document.createElement("s");
          nm.textContent = s.id;
          l.append(i2, b, nm);
          bulle.append(l);
        });
      }
      const su = document.createElement("div");
      su.className = "sujet";
      su.textContent = j.sujet;
      bulle.append(su);
      poser(cx, cy);
    }
    function viser(ev) {
      const bb = svgCourbes.getBoundingClientRect();
      const ux = (ev.clientX - bb.left) / bb.width * w;
      let choisi = 0, dist = Infinity;
      JALONS.forEach((_, i) => {
        const d = Math.abs(x(i) - ux);
        if (d < dist) { dist = d; choisi = i; }
      });
      montrer(choisi, ev.clientX, ev.clientY);
    }
    const effacer = () => {
      masquer();
      viseur.setAttribute("opacity", 0);
      vider(points);
    };
    // The state of THIS drawing, read back by the listeners installed once, further down.
    survolCourbes = { viser: viser, effacer: effacer };
  }

  // Gaps from one milestone to the next. The detailed series is the FIRST of the data file, not a
  // "fib" wired in here: renaming a series in the JSON would otherwise have given NaN bars, with
  // no error.
  const SERIE_ECARTS = SERIES[0];
  document.getElementById("serie-ecarts").textContent = SERIE_ECARTS.id;

  function dessinerEcarts(w) {
    const petit = w < 560;
    const h = petit ? Math.round(w * 0.62) : 300;
    const m = { t: 22, r: petit ? 8 : 22, b: petit ? 26 : 44, l: petit ? 34 : 56 };
    vider(svgEcarts);
    svgEcarts.setAttribute("viewBox", "0 0 " + w + " " + h);
    svgEcarts.setAttribute("width", w);
    svgEcarts.setAttribute("height", h);

    const iw = w - m.l - m.r, ih = h - m.t - m.b;
    const pts = [];
    let avant = null;
    JALONS.forEach(j => {
      if (!connu(j)) return;
      if (avant !== null) {
        pts.push({
          date: jourMois(j.date), commit: j.commit, sujet: j.sujet,
          v: (j[SERIE_ECARTS.id] - avant) / avant * 100,
        });
      }
      avant = j[SERIE_ECARTS.id];
    });

    const borne = Math.max(10, Math.ceil(Math.max(...pts.map(p => Math.abs(p.v))) / 4) * 4);
    const y = v => m.t + ih / 2 - (v / borne) * (ih / 2);
    const pasX = iw / pts.length;
    const larg = Math.max(3, Math.min(20, pasX - (petit ? 2 : 4)));
    const x = k => m.l + (k + 0.5) * pasX;

    const grille = el("g", { class: "grille" }), axe = el("g", { class: "axe" });
    const ticks = petit ? [-borne, 0, borne] : [-borne, -borne / 2, 0, borne / 2, borne];
    ticks.forEach(v => {
      grille.append(el("line", { x1: m.l, x2: m.l + iw, y1: y(v), y2: y(v) }));
      const t = el("text", { x: m.l - 6, y: y(v) + 4, "text-anchor": "end", class: "mono" });
      t.textContent = petit ? (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v) : pct(v).replace(" %", "%");
      axe.append(t);
    });
    svgEcarts.append(grille, axe);

    const marques = el("g"), barres = [];
    pts.forEach((p, k) => {
      const versHaut = p.v >= 0;
      const hb = Math.max(1.5, Math.abs(y(p.v) - y(0)));
      const r = Math.min(4, larg / 2, hb);
      const bx = x(k) - larg / 2, by = versHaut ? y(p.v) : y(0);
      // Rounded at the data end, square on the baseline.
      const d = versHaut
        ? "M" + bx + " " + (by + hb) + " L" + bx + " " + (by + r) + " Q" + bx + " " + by + " " + (bx + r) + " " + by +
          " L" + (bx + larg - r) + " " + by + " Q" + (bx + larg) + " " + by + " " + (bx + larg) + " " + (by + r) +
          " L" + (bx + larg) + " " + (by + hb) + " Z"
        : "M" + bx + " " + by + " L" + bx + " " + (by + hb - r) + " Q" + bx + " " + (by + hb) + " " + (bx + r) + " " + (by + hb) +
          " L" + (bx + larg - r) + " " + (by + hb) + " Q" + (bx + larg) + " " + (by + hb) + " " + (bx + larg) + " " + (by + hb - r) +
          " L" + (bx + larg) + " " + by + " Z";
      const barre = el("path", { d: d, fill: versHaut ? "var(--hausse)" : "var(--baisse)" });
      // `fill="transparent"` does not count as "painted" for pointer-events: without
      // pointer-events="all" the hover area catches nothing.
      const zone = el("rect", {
        x: x(k) - pasX / 2, y: m.t, width: pasX, height: ih,
        fill: "transparent", "pointer-events": "all",
      });
      const entrer = ev => {
        barre.setAttribute("opacity", 0.72);
        vider(bulle);
        const quand = document.createElement("div");
        quand.className = "quand";
        quand.textContent = p.date + "  ·  " + p.commit;
        const ligne = document.createElement("div");
        ligne.className = "ligne";
        const b = document.createElement("b");
        b.textContent = pct(p.v);
        const s = document.createElement("s");
        s.textContent = "sur " + SERIE_ECARTS.id;
        ligne.append(b, s);
        const su = document.createElement("div");
        su.className = "sujet";
        su.textContent = p.sujet;
        bulle.append(quand, ligne, su);
        poser(ev.clientX, ev.clientY);
      };
      zone.addEventListener("pointerenter", entrer);
      zone.addEventListener("pointerdown", entrer);
      zone.addEventListener("pointerleave", ev => {
        if (ev.pointerType !== "mouse") return;
        barre.removeAttribute("opacity");
        masquer();
      });
      barres.push(barre);
      marques.append(barre, zone);
    });
    svgEcarts.append(marques);
    survolEcarts = { effacer: () => {
      barres.forEach(b => b.removeAttribute("opacity"));
      masquer();
    } };
    // The baseline goes over the bars but stays transparent to the pointer; otherwise it steals
    // the hover exactly along its axis.
    svgEcarts.append(el("line", { x1: m.l, x2: m.l + iw, y1: y(0), y2: y(0), class: "zero" }));

    [...pts].sort((a, b) => Math.abs(b.v) - Math.abs(a.v)).slice(0, petit ? 2 : 4).forEach(p => {
      const k = pts.indexOf(p), versHaut = p.v >= 0;
      const ty = versHaut ? y(p.v) - 8 : y(p.v) + 17;
      const anc = k < 2 ? "start" : k > pts.length - 3 ? "end" : "middle";
      const t = el("text", { x: x(k), y: ty, "text-anchor": anc, class: "note" });
      t.textContent = pct(p.v);
      const d = el("text", { x: x(k), y: versHaut ? ty - 12 : ty + 13, "text-anchor": anc, class: "note discret" });
      d.textContent = p.date;
      svgEcarts.append(t, d);
    });
  }

  // The time reading: horizontal bars, in multiples of the reference. The scale is CAPPED rather
  // than compressed: the highest coefficient (Python on the numeric loop) would crush everything
  // else, and a non-linear scale would lie about the ratios. Bars that go past the cap are cut
  // short with a point, and their value is written out at the end.
  const coef = v => "×" + v.toFixed(2).replace(".", ",");
  const secondes = v => v.toFixed(4).replace(".", ",") + " s";
  const mediane = id => {
    const t = bench.benchmarks.map(b => b[id]).sort((a, b) => a - b);
    const m = Math.floor(t.length / 2);
    return t.length % 2 ? t[m] : (t[m - 1] + t[m]) / 2;
  };

  if (bench) {
    // The reference is not among `concurrents`, so the heading names it first; otherwise the page
    // would announce a single language compared while the chart shows two.
    document.getElementById("titre-temps").textContent = "Le temps, face à " +
      [bench.reference.nom].concat(bench.concurrents.filter(c => c.id !== "ollin").map(c => c.nom)).join(" et à ");
    document.getElementById("apropos-temps").textContent =
      "Relevé du " + enClair(bench.date) + " " + bench.date.slice(0, 4) + " sur le commit " +
      bench.commit + ", meilleur de " + bench.runs + " exécutions, en temps processeur. " +
      bench.machine + " ; " + bench.build + ". Référence : " + bench.reference.nom +
      ", dont le temps absolu vaut 1.";

    const boite = document.getElementById("cles-bench");
    bench.concurrents.forEach(c => {
      const w = document.createElement("span");
      const i = document.createElement("i");
      i.className = "s-" + c.id;
      const b = document.createElement("b");
      b.textContent = "médiane " + coef(mediane(c.id));
      w.append(i, document.createTextNode(c.nom), b);
      boite.append(w);
    });
  }

  const svgBench = document.getElementById("bench");

  function dessinerBench(w) {
    const petit = w < 560;
    const B = bench.benchmarks, C = bench.concurrents;
    const hLigne = 20 + C.length * 11;
    const m = { t: 20, r: petit ? 40 : 54, b: 30, l: 6 };
    const h = m.t + B.length * hLigne + m.b;
    vider(svgBench);
    svgBench.setAttribute("viewBox", "0 0 " + w + " " + h);
    svgBench.setAttribute("width", w);
    svgBench.setAttribute("height", h);

    const iw = w - m.l - m.r;
    // The cap: enough to hold all of Ollin's coefficients, and one notch above the reference —
    // never the absolute maximum, which would come from a very slow competitor.
    const hautOllin = Math.max(...B.map(b => b.ollin));
    const borne = Math.max(2, Math.ceil(hautOllin + 0.5));
    const x = v => m.l + Math.min(v, borne) / borne * iw;

    const grille = el("g", { class: "grille" }), axe = el("g", { class: "axe" });
    for (let v = 0; v <= borne; v++) {
      grille.append(el("line", { x1: x(v), x2: x(v), y1: m.t, y2: h - m.b }));
      const t = el("text", { x: x(v), y: h - m.b + 16, "text-anchor": "middle", class: "mono" });
      t.textContent = "×" + v;
      axe.append(t);
    }
    svgBench.append(grille, axe);

    B.forEach((b, i) => {
      const y0 = m.t + i * hLigne;
      const nom = el("text", { x: m.l + 2, y: y0 + 9, class: "etiq" });
      nom.textContent = petit ? b.nom : b.nom + " — " + b.quoi;
      svgBench.append(nom);
      C.forEach((c, k) => {
        const y = y0 + 15 + k * 11;
        const depasse = b[c.id] > borne;
        const bx = x(b[c.id]);
        svgBench.append(el("rect", {
          x: m.l, y: y, width: Math.max(1.5, bx - m.l), height: 7, rx: 3.5,
          fill: "var(--s-" + c.id + ")", opacity: depasse ? 0.55 : 1,
        }));
        // A value beyond the scale is written AGAINST the right edge, right-aligned: placed at
        // the end of the shortened bar it went out of frame and was cut in two on a phone
        // ("×12,").
        const t = el("text", {
          x: depasse ? w - 2 : bx + 6, y: y + 7, class: "val",
          fill: "var(--s-" + c.id + ")", "text-anchor": depasse ? "end" : "start",
        });
        t.textContent = (depasse ? "▸ " : "") + coef(b[c.id]);
        svgBench.append(t);
      });
      // The reference marker, over the bars but SEGMENTED line by line: a single vertical over
      // the whole height would cross the benchmark names.
      svgBench.append(el("line", {
        x1: x(1), x2: x(1), y1: y0 + 13, y2: y0 + 13 + C.length * 11, class: "barre-ref",
      }));
    });
    const ref = el("text", { x: x(1), y: m.t - 12, "text-anchor": "middle", class: "etiq" });
    ref.textContent = bench.reference.nom + " = ×1";
    svgBench.append(ref);
  }

  // Table.
  (function tableau() {
    const table = document.getElementById("valeurs");
    const thead = document.createElement("thead"), tr = document.createElement("tr");
    const colonnes = ["date", "commit"];
    SERIES.forEach(s => colonnes.push(s.id, "Δ " + s.id));
    colonnes.push("dernier commit du jour");
    colonnes.forEach(c => {
      const th = document.createElement("th");
      th.textContent = c;
      tr.append(th);
    });
    thead.append(tr);
    const tbody = document.createElement("tbody");
    let avant = null;
    JALONS.forEach(j => {
      const ligne = document.createElement("tr");
      const cases = [["", jourMois(j.date)], ["", j.commit]];
      SERIES.forEach(s => {
        const v = j[s.id];
        cases.push(["n", v === null ? "—" : fmt(v)]);
        if (v === null || avant === null) {
          cases.push(["n", "—"]);
        } else {
          const d = (v - avant[s.id]) / avant[s.id] * 100;
          cases.push([d > 0.05 ? "n hausse" : d < -0.05 ? "n baisse" : "n", pct(d)]);
        }
      });
      cases.push(["sujet", j.sujet]);
      cases.forEach(([cls, txt]) => {
        const td = document.createElement("td");
        if (cls) td.className = cls;
        td.textContent = txt;   // file data: never through innerHTML
        ligne.append(td);
      });
      tbody.append(ligne);
      if (connu(j)) avant = j;
    });
    table.append(thead, tbody);
  })();

  // Table of the time reading.
  if (bench) {
    const table = document.getElementById("temps");
    const thead = document.createElement("thead"), tr = document.createElement("tr");
    ["benchmark", "ce qu'il mesure", bench.reference.nom]
      .concat(bench.concurrents.map(c => c.nom))
      .forEach(c => {
        const th = document.createElement("th");
        th.textContent = c;
        tr.append(th);
      });
    thead.append(tr);
    const tbody = document.createElement("tbody");
    bench.benchmarks.forEach(b => {
      const ligne = document.createElement("tr");
      const cases = [["", b.nom], ["sujet", b.quoi], ["n", secondes(b[bench.reference.id])]];
      bench.concurrents.forEach(c => cases.push(["n", coef(b[c.id])]));
      cases.forEach(([cls, txt]) => {
        const td = document.createElement("td");
        if (cls) td.className = cls;
        td.textContent = txt;   // file data: never through innerHTML
        ligne.append(td);
      });
      tbody.append(ligne);
    });
    table.append(thead, tbody);
  }

  // Drawing, and redrawing when the width changes.
  function largeurUtile(svg) {
    const b = svg.parentElement, cs = getComputedStyle(b);
    return Math.max(240, Math.floor(b.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)));
  }
  let derniere = 0;
  function redessiner() {
    const w = largeurUtile(svgCourbes);
    if (w === derniere) return;
    derniere = w;
    dessinerCourbes(w);
    dessinerEcarts(largeurUtile(svgEcarts));
    if (bench) dessinerBench(largeurUtile(svgBench));
  }
  // The hover listeners are installed ONCE, on elements that are never replaced: they delegate to
  // the latest published drawing.
  const viserCourbes = ev => { if (survolCourbes) survolCourbes.viser(ev); };
  const quitterCourbes = ev => {
    if (survolCourbes && ev.pointerType === "mouse") survolCourbes.effacer();
  };
  const annulerCourbes = () => { if (survolCourbes) survolCourbes.effacer(); };
  const surRotation = () => setTimeout(redessiner, 120);
  let observateur = null;
  try {
    redessiner();
    svgCourbes.addEventListener("pointermove", viserCourbes);
    svgCourbes.addEventListener("pointerdown", viserCourbes);
    svgCourbes.addEventListener("pointerleave", quitterCourbes);
    svgCourbes.addEventListener("pointercancel", annulerCourbes);
    fermerAilleurs(svgCourbes, annulerCourbes);
    fermerAilleurs(svgEcarts, () => { if (survolEcarts) survolEcarts.effacer(); });
    addEventListener("resize", redessiner);
    addEventListener("orientationchange", surRotation);
    if (window.ResizeObserver) {
      observateur = new ResizeObserver(redessiner);
      observateur.observe(document.querySelector(".perf-wrap"));
    }
  } catch (e) {
    signaler(e);
  }

  // Cleanup: every GLOBAL listener installed here must be removed, otherwise it survives the
  // change of view (app.js replaces #view, but not window or document).
  return () => {
    removeEventListener("resize", redessiner);
    removeEventListener("orientationchange", surRotation);
    horsGraphe.forEach(h => document.removeEventListener("pointerdown", h, true));
    if (observateur) observateur.disconnect();
    masquer();
  };
}
