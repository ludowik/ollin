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
  const pct = v => (Math.abs(v) < 0.05 ? "" : v > 0 ? "+" : "−") + Math.abs(v).toFixed(1) + " %";
  const millions = n => (n / 1e6).toFixed(1) + " M";
  const dayMonth = iso => iso.slice(8, 10) + "/" + iso.slice(5, 7);

  const SVGNS = "http://www.w3.org/2000/svg";
  const el = (t, a) => {
    const n = document.createElementNS(SVGNS, t);
    for (const k in a) n.setAttribute(k, a[k]);
    return n;
  };
  const emptyNode = n => {
    while (n.firstChild) n.removeChild(n.firstChild);
  };

  const tip = document.getElementById("tip");
  const problem = document.getElementById("problem");
  const svgCurves = document.getElementById("curves");
  const svgGaps = document.getElementById("gaps");

  function report(e) {
    problem.hidden = false;
    problem.textContent = "The charts could not be drawn (" + (e && e.message ? e.message : e) +
                        "). The values remain readable in the table.";
  }

  // Data.
  let doc;
  try {
    const resp = await fetch("data/icount-history.json?v=" + ctx.v);
    if (!resp.ok) throw new Error("HTTP " + resp.status);
    doc = await resp.json();
  } catch (e) {
    report(e);
    return () => {};
  }

  // The time reading: when absent, the page stays valid without its section, which is removed
  // from the DOM rather than left empty — a heading over a hollow frame reads as a breakdown.
  let bench = null;
  try {
    const resp = await fetch("data/bench-snapshot.json?v=" + ctx.v);
    if (resp.ok) bench = await resp.json();
  } catch (e) {
    bench = null;
  }
  if (!bench) {
    // Every element to remove carries an id: aiming at another's neighbour ("the heading just
    // before the table") failed, the heading being a sibling of the scrolling CONTAINER rather
    // than of the table itself.
    ["title-times", "about-times", "block-bench", "title-detail", "scroll-times"]
      .forEach(id => document.getElementById(id).remove());
  }

  const MILESTONES = doc.milestones;
  const SERIES = doc.scripts.map(s => ({ id: s.id, name: s.name, cssClass: "s-" + s.id, css: "--s-" + s.id }));
  // ALL the series must be present: testing only one would leave `show()` computing y(null)
  // for the others, hence NaN coordinates with no message.
  const known = j => SERIES.every(s => typeof j[s.id] === "number");
  const first = MILESTONES.find(known);
  const last = [...MILESTONES].reverse().find(known);
  // No complete milestone: the file is unusable for the charts (a renamed series, values all
  // missing). Say why, rather than failing on first.date.
  if (!first) {
    report(new Error("no milestone carries the " + SERIES.length + " expected series: " +
                       SERIES.map(s => s.id).join(", ")));
    return () => {};
  }
  const MONTHS = ["January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December"];
  const inWords = iso => Number(iso.slice(8, 10)) + " " + MONTHS[Number(iso.slice(5, 7)) - 1];
  const measured = MILESTONES.filter(known).length;

  document.getElementById("intro").textContent =
    "What Ollin's engine costs to run, measured two ways: the WORK it asks for, followed from " +
    inWords(first.date) + " to " + inWords(last.date) + " " +
    last.date.slice(0, 4) + (bench ? ", and the TIME it takes, read against Lua and Python." : ".");
  document.getElementById("about-work").textContent =
    "Instructions executed by " + SERIES.map(s => s.name).join(", ") + ". " +
    MILESTONES.length + " milestones, one per day on which the engine's core was touched" +
    (measured < MILESTONES.length ? ", " + (MILESTONES.length - measured) + " of them without a value, having failed to build. " : ". ") +
    "Measured with " + doc.tool + "; " + doc.machine + ".";

  // Summaries.
  const summaryBox = document.getElementById("summary");
  SERIES.forEach(s => {
    const a = first[s.id], b = last[s.id];
    const v = (b - a) / a * 100;
    const card = document.createElement("div");
    card.className = "card";
    const what = document.createElement("div");
    what.className = "what";
    const past = document.createElement("span");
    past.className = "dot " + s.cssClass;
    what.append(past, document.createTextNode(s.name));
    const val = document.createElement("div");
    val.className = "value";
    val.textContent = pct(v);
    const det = document.createElement("div");
    det.className = "detail";
    det.textContent = fmt(a) + " → " + fmt(b) + (v < 0 ? " (÷" + (a / b).toFixed(2) + ")" : "");
    card.append(what, val, det);
    summaryBox.append(card);
  });

  // The reading keys carry the final value: on a phone the chart has no right margin left for an
  // end-of-curve label.
  const keyBox = document.getElementById("keys");
  SERIES.forEach(s => {
    const w = document.createElement("span");
    const i = document.createElement("i");
    i.className = s.cssClass;
    const b = document.createElement("b");
    b.textContent = millions(last[s.id]);
    w.append(i, document.createTextNode(s.name), b);
    keyBox.append(w);
  });

  // Tooltip.
  function place(cx, cy) {
    tip.style.opacity = 1;
    const margin = 14, lb = tip.offsetWidth, hb = tip.offsetHeight;
    let px = cx + margin, py = cy - 10;
    if (px + lb > innerWidth - 8) px = Math.max(8, cx - lb - margin);
    if (py + hb > innerHeight - 8) py = innerHeight - hb - 8;
    if (py < 8) py = 8;
    tip.style.left = px + "px";
    tip.style.top = py + "px";
  }
  const hide = () => { tip.style.opacity = 0; };

  // With a finger, lifting emits pointerleave right after the press, so we only close on the
  // pointer leaving for a MOUSE, and let a press outside the chart close it otherwise.
  const outsideHandlers = [];
  function closeOnOutside(svg, clearHover) {
    const h = ev => { if (!svg.contains(ev.target)) clearHover(); };
    document.addEventListener("pointerdown", h, true);
    outsideHandlers.push(h);
  }

  // The latest drawing publishes its hover functions here; the listeners themselves are
  // installed once and for all after the first drawing.
  let hoverCurves = null;
  let hoverGaps = null;

  // Curves.
  function drawCurves(w) {
    const small = w < 560;
    const h = small ? Math.round(w * 0.86) : 400;
    const m = { t: 12, r: small ? 12 : 92, b: small ? 42 : 46, l: small ? 40 : 58 };
    emptyNode(svgCurves);
    svgCurves.setAttribute("viewBox", "0 0 " + w + " " + h);
    svgCurves.setAttribute("width", w);
    svgCurves.setAttribute("height", h);

    const iw = w - m.l - m.r, ih = h - m.t - m.b, n = MILESTONES.length;
    const x = i => m.l + i * iw / (n - 1);
    const top = Math.max(...MILESTONES.filter(known).flatMap(j => SERIES.map(s => j[s.id])));
    const stepY = 25e6;
    const ymax = Math.ceil(top / 1e7) * 1e7;
    const y = v => m.t + ih - (v / ymax) * ih;

    const grid = el("g", { class: "grid" }), axis = el("g", { class: "axis" });
    for (let v = 0; v <= ymax; v += stepY) {
      grid.append(el("line", { x1: m.l, x2: m.l + iw, y1: y(v), y2: y(v) }));
      const t = el("text", { x: m.l - 8, y: y(v) + 4, "text-anchor": "end", class: "mono" });
      t.textContent = v === 0 ? "0" : (small ? String(v / 1e6) : millions(v));
      axis.append(t);
    }
    if (small) {
      const u = el("text", { x: m.l - 8, y: m.t - 1, "text-anchor": "end", class: "mono" });
      u.textContent = "M";
      axis.append(u);
    }
    svgCurves.append(grid);

    const step = small ? 8 : 3;
    let shown = "";
    MILESTONES.forEach((j, i) => {
      if (i % step !== 0 && i !== n - 1) return;
      const d = dayMonth(j.date);
      if (d === shown) return;
      shown = d;
      const t = el("text", {
        x: x(i), y: h - m.b + 20, class: "mono",
        "text-anchor": i === n - 1 ? "end" : i === 0 ? "start" : "middle",
      });
      t.textContent = d;
      axis.append(t);
    });
    const leg = el("text", { x: m.l, y: h - m.b + 37, class: "mono dim" });
    leg.textContent = small ? n + " engine milestones" : n + " milestones - one per day of engine commits";
    axis.append(leg);
    svgCurves.append(axis);

    SERIES.forEach(s => {
      let d = "", open = false;
      MILESTONES.forEach((j, i) => {
        const v = j[s.id];
        if (v === null) { open = false; return; }
        d += (open ? " L" : " M") + x(i).toFixed(1) + " " + y(v).toFixed(1);
        open = true;
      });
      svgCurves.append(el("path", { class: "curve", d: d.trim(), stroke: "var(" + s.css + ")" }));
      const dv = last[s.id];
      svgCurves.append(el("circle", { cx: x(n - 1), cy: y(dv), r: 4.5, fill: "var(" + s.css + ")", class: "ring" }));
      if (!small) {
        const b = el("text", { x: x(n - 1) + 12, y: y(dv) + 4, class: "end", fill: "var(" + s.css + ")" });
        b.textContent = millions(dv);
        svgCurves.append(b);
      }
    });

    const crosshair = el("line", { class: "crosshair", y1: m.t, y2: m.t + ih });
    const points = el("g");
    svgCurves.append(crosshair, points);

    function show(i, cx, cy) {
      const j = MILESTONES[i];
      crosshair.setAttribute("x1", x(i));
      crosshair.setAttribute("x2", x(i));
      crosshair.setAttribute("opacity", known(j) ? 0.5 : 0);
      emptyNode(points);
      if (known(j)) {
        SERIES.forEach(s => points.append(el("circle", {
          cx: x(i), cy: y(j[s.id]), r: 4.5, fill: "var(" + s.css + ")", class: "ring",
        })));
      }
      emptyNode(tip);
      const when = document.createElement("div");
      when.className = "when";
      when.textContent = j.date + "  ·  " + j.commit;
      tip.append(when);
      if (!known(j)) {
        const l = document.createElement("div");
        l.className = "row";
        l.textContent = "unknown value";
        tip.append(l);
      } else {
        SERIES.forEach(s => {
          const l = document.createElement("div");
          l.className = "row";
          const i2 = document.createElement("i");
          i2.className = s.cssClass;
          const b = document.createElement("b");
          b.textContent = fmt(j[s.id]);
          const nm = document.createElement("s");
          nm.textContent = s.id;
          l.append(i2, b, nm);
          tip.append(l);
        });
      }
      const su = document.createElement("div");
      su.className = "subject";
      su.textContent = j.subject;
      tip.append(su);
      place(cx, cy);
    }
    function aim(ev) {
      const bb = svgCurves.getBoundingClientRect();
      const ux = (ev.clientX - bb.left) / bb.width * w;
      let chosen = 0, dist = Infinity;
      MILESTONES.forEach((_, i) => {
        const d = Math.abs(x(i) - ux);
        if (d < dist) { dist = d; chosen = i; }
      });
      show(chosen, ev.clientX, ev.clientY);
    }
    const clearHover = () => {
      hide();
      crosshair.setAttribute("opacity", 0);
      emptyNode(points);
    };
    // The state of THIS drawing, read back by the listeners installed once, further down.
    hoverCurves = { aim: aim, clearHover: clearHover };
  }

  // Gaps from one milestone to the next. The detailed series is the FIRST of the data file, not a
  // "fib" wired in here: renaming a series in the JSON would otherwise have given NaN bars, with
  // no error.
  const GAPS_SERIES = SERIES[0];
  document.getElementById("gaps-series").textContent = GAPS_SERIES.id;

  function drawGaps(w) {
    const small = w < 560;
    const h = small ? Math.round(w * 0.62) : 300;
    const m = { t: 22, r: small ? 8 : 22, b: small ? 26 : 44, l: small ? 34 : 56 };
    emptyNode(svgGaps);
    svgGaps.setAttribute("viewBox", "0 0 " + w + " " + h);
    svgGaps.setAttribute("width", w);
    svgGaps.setAttribute("height", h);

    const iw = w - m.l - m.r, ih = h - m.t - m.b;
    const pts = [];
    let prev = null;
    MILESTONES.forEach(j => {
      if (!known(j)) return;
      if (prev !== null) {
        pts.push({
          date: dayMonth(j.date), commit: j.commit, subject: j.subject,
          v: (j[GAPS_SERIES.id] - prev) / prev * 100,
        });
      }
      prev = j[GAPS_SERIES.id];
    });

    const bound = Math.max(10, Math.ceil(Math.max(...pts.map(p => Math.abs(p.v))) / 4) * 4);
    const y = v => m.t + ih / 2 - (v / bound) * (ih / 2);
    const stepX = iw / pts.length;
    const barW = Math.max(3, Math.min(20, stepX - (small ? 2 : 4)));
    const x = k => m.l + (k + 0.5) * stepX;

    const grid = el("g", { class: "grid" }), axis = el("g", { class: "axis" });
    const ticks = small ? [-bound, 0, bound] : [-bound, -bound / 2, 0, bound / 2, bound];
    ticks.forEach(v => {
      grid.append(el("line", { x1: m.l, x2: m.l + iw, y1: y(v), y2: y(v) }));
      const t = el("text", { x: m.l - 6, y: y(v) + 4, "text-anchor": "end", class: "mono" });
      t.textContent = small ? (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v) : pct(v).replace(" %", "%");
      axis.append(t);
    });
    svgGaps.append(grid, axis);

    const marks = el("g"), bars = [];
    pts.forEach((p, k) => {
      const upwards = p.v >= 0;
      const hb = Math.max(1.5, Math.abs(y(p.v) - y(0)));
      const r = Math.min(4, barW / 2, hb);
      const bx = x(k) - barW / 2, by = upwards ? y(p.v) : y(0);
      // Rounded at the data end, square on the baseline.
      const d = upwards
        ? "M" + bx + " " + (by + hb) + " L" + bx + " " + (by + r) + " Q" + bx + " " + by + " " + (bx + r) + " " + by +
          " L" + (bx + barW - r) + " " + by + " Q" + (bx + barW) + " " + by + " " + (bx + barW) + " " + (by + r) +
          " L" + (bx + barW) + " " + (by + hb) + " Z"
        : "M" + bx + " " + by + " L" + bx + " " + (by + hb - r) + " Q" + bx + " " + (by + hb) + " " + (bx + r) + " " + (by + hb) +
          " L" + (bx + barW - r) + " " + (by + hb) + " Q" + (bx + barW) + " " + (by + hb) + " " + (bx + barW) + " " + (by + hb - r) +
          " L" + (bx + barW) + " " + by + " Z";
      const bar = el("path", { d: d, fill: upwards ? "var(--rise)" : "var(--fall)" });
      // `fill="transparent"` does not count as "painted" for pointer-events: without
      // pointer-events="all" the hover area catches nothing.
      const zone = el("rect", {
        x: x(k) - stepX / 2, y: m.t, width: stepX, height: ih,
        fill: "transparent", "pointer-events": "all",
      });
      const enter = ev => {
        bar.setAttribute("opacity", 0.72);
        emptyNode(tip);
        const when = document.createElement("div");
        when.className = "when";
        when.textContent = p.date + "  ·  " + p.commit;
        const row = document.createElement("div");
        row.className = "row";
        const b = document.createElement("b");
        b.textContent = pct(p.v);
        const s = document.createElement("s");
        s.textContent = "on " + GAPS_SERIES.id;
        row.append(b, s);
        const su = document.createElement("div");
        su.className = "subject";
        su.textContent = p.subject;
        tip.append(when, row, su);
        place(ev.clientX, ev.clientY);
      };
      zone.addEventListener("pointerenter", enter);
      zone.addEventListener("pointerdown", enter);
      zone.addEventListener("pointerleave", ev => {
        if (ev.pointerType !== "mouse") return;
        bar.removeAttribute("opacity");
        hide();
      });
      bars.push(bar);
      marks.append(bar, zone);
    });
    svgGaps.append(marks);
    hoverGaps = { clearHover: () => {
      bars.forEach(b => b.removeAttribute("opacity"));
      hide();
    } };
    // The baseline goes over the bars but stays transparent to the pointer; otherwise it steals
    // the hover exactly along its axis.
    svgGaps.append(el("line", { x1: m.l, x2: m.l + iw, y1: y(0), y2: y(0), class: "zero" }));

    [...pts].sort((a, b) => Math.abs(b.v) - Math.abs(a.v)).slice(0, small ? 2 : 4).forEach(p => {
      const k = pts.indexOf(p), upwards = p.v >= 0;
      const ty = upwards ? y(p.v) - 8 : y(p.v) + 17;
      const anchor = k < 2 ? "start" : k > pts.length - 3 ? "end" : "middle";
      const t = el("text", { x: x(k), y: ty, "text-anchor": anchor, class: "note" });
      t.textContent = pct(p.v);
      const d = el("text", { x: x(k), y: upwards ? ty - 12 : ty + 13, "text-anchor": anchor, class: "note dim" });
      d.textContent = p.date;
      svgGaps.append(t, d);
    });
  }

  // The time reading: horizontal bars, in multiples of the reference. The scale is CAPPED rather
  // than compressed: the highest coefficient (Python on the numeric loop) would crush everything
  // else, and a non-linear scale would lie about the ratios. Bars that go past the cap are cut
  // short with a point, and their value is written out at the end.
  const coef = v => "×" + v.toFixed(2);
  const seconds = v => v.toFixed(4) + " s";
  const median = id => {
    const t = bench.benchmarks.map(b => b[id]).sort((a, b) => a - b);
    const m = Math.floor(t.length / 2);
    return t.length % 2 ? t[m] : (t[m - 1] + t[m]) / 2;
  };

  if (bench) {
    // The reference is not among `competitors`, so the heading names it first; otherwise the page
    // would announce a single language compared while the chart shows two.
    document.getElementById("title-times").textContent = "The time, against " +
      [bench.reference.name].concat(bench.competitors.filter(c => c.id !== "ollin").map(c => c.name)).join(" and ");
    document.getElementById("about-times").textContent =
      "Read on " + inWords(bench.date) + " " + bench.date.slice(0, 4) + " at commit " +
      bench.commit + ", best of " + bench.runs + " runs, in processor time. " +
      bench.machine + "; " + bench.build + ". Reference: " + bench.reference.name +
      ", whose absolute time counts as 1.";

    const box = document.getElementById("keys-bench");
    bench.competitors.forEach(c => {
      const w = document.createElement("span");
      const i = document.createElement("i");
      i.className = "s-" + c.id;
      const b = document.createElement("b");
      b.textContent = "median " + coef(median(c.id));
      w.append(i, document.createTextNode(c.name), b);
      box.append(w);
    });
  }

  const svgBench = document.getElementById("bench");

  function drawBench(w) {
    const small = w < 560;
    const B = bench.benchmarks, C = bench.competitors;
    const rowH = 20 + C.length * 11;
    const m = { t: 20, r: small ? 40 : 54, b: 30, l: 6 };
    const h = m.t + B.length * rowH + m.b;
    emptyNode(svgBench);
    svgBench.setAttribute("viewBox", "0 0 " + w + " " + h);
    svgBench.setAttribute("width", w);
    svgBench.setAttribute("height", h);

    const iw = w - m.l - m.r;
    // The cap: enough to hold all of Ollin's coefficients, and one notch above the reference —
    // never the absolute maximum, which would come from a very slow competitor.
    const topOllin = Math.max(...B.map(b => b.ollin));
    const bound = Math.max(2, Math.ceil(topOllin + 0.5));
    const x = v => m.l + Math.min(v, bound) / bound * iw;

    const grid = el("g", { class: "grid" }), axis = el("g", { class: "axis" });
    for (let v = 0; v <= bound; v++) {
      grid.append(el("line", { x1: x(v), x2: x(v), y1: m.t, y2: h - m.b }));
      const t = el("text", { x: x(v), y: h - m.b + 16, "text-anchor": "middle", class: "mono" });
      t.textContent = "×" + v;
      axis.append(t);
    }
    svgBench.append(grid, axis);

    B.forEach((b, i) => {
      const y0 = m.t + i * rowH;
      const name = el("text", { x: m.l + 2, y: y0 + 9, class: "tick" });
      name.textContent = small ? b.name : b.name + " — " + b.what;
      svgBench.append(name);
      C.forEach((c, k) => {
        const y = y0 + 15 + k * 11;
        const beyond = b[c.id] > bound;
        const bx = x(b[c.id]);
        svgBench.append(el("rect", {
          x: m.l, y: y, width: Math.max(1.5, bx - m.l), height: 7, rx: 3.5,
          fill: "var(--s-" + c.id + ")", opacity: beyond ? 0.55 : 1,
        }));
        // A value beyond the scale is written AGAINST the right edge, right-aligned: placed at
        // the end of the shortened bar it went out of frame and was cut in two on a phone
        // ("x12.").
        const t = el("text", {
          x: beyond ? w - 2 : bx + 6, y: y + 7, class: "val",
          fill: "var(--s-" + c.id + ")", "text-anchor": beyond ? "end" : "start",
        });
        t.textContent = (beyond ? "▸ " : "") + coef(b[c.id]);
        svgBench.append(t);
      });
      // The reference marker, over the bars but SEGMENTED line by line: a single vertical over
      // the whole height would cross the benchmark names.
      svgBench.append(el("line", {
        x1: x(1), x2: x(1), y1: y0 + 13, y2: y0 + 13 + C.length * 11, class: "ref-line",
      }));
    });
    const ref = el("text", { x: x(1), y: m.t - 12, "text-anchor": "middle", class: "tick" });
    ref.textContent = bench.reference.name + " = ×1";
    svgBench.append(ref);
  }

  // Table.
  (function buildTable() {
    const table = document.getElementById("values");
    const thead = document.createElement("thead"), tr = document.createElement("tr");
    const columns = ["date", "commit"];
    SERIES.forEach(s => columns.push(s.id, "Δ " + s.id));
    columns.push("the day's last commit");
    columns.forEach(c => {
      const th = document.createElement("th");
      th.textContent = c;
      tr.append(th);
    });
    thead.append(tr);
    const tbody = document.createElement("tbody");
    let prev = null;
    MILESTONES.forEach(j => {
      const row = document.createElement("tr");
      const cells = [["", dayMonth(j.date)], ["", j.commit]];
      SERIES.forEach(s => {
        const v = j[s.id];
        cells.push(["n", v === null ? "—" : fmt(v)]);
        if (v === null || prev === null) {
          cells.push(["n", "—"]);
        } else {
          const d = (v - prev[s.id]) / prev[s.id] * 100;
          cells.push([d > 0.05 ? "n rise" : d < -0.05 ? "n fall" : "n", pct(d)]);
        }
      });
      cells.push(["subject", j.subject]);
      cells.forEach(([cls, txt]) => {
        const td = document.createElement("td");
        if (cls) td.className = cls;
        td.textContent = txt;   // file data: never through innerHTML
        row.append(td);
      });
      tbody.append(row);
      if (known(j)) prev = j;
    });
    table.append(thead, tbody);
  })();

  // Table of the time reading.
  if (bench) {
    const table = document.getElementById("times");
    const thead = document.createElement("thead"), tr = document.createElement("tr");
    ["benchmark", "what it measures", bench.reference.name]
      .concat(bench.competitors.map(c => c.name))
      .forEach(c => {
        const th = document.createElement("th");
        th.textContent = c;
        tr.append(th);
      });
    thead.append(tr);
    const tbody = document.createElement("tbody");
    bench.benchmarks.forEach(b => {
      const row = document.createElement("tr");
      const cells = [["", b.name], ["subject", b.what], ["n", seconds(b[bench.reference.id])]];
      bench.competitors.forEach(c => cells.push(["n", coef(b[c.id])]));
      cells.forEach(([cls, txt]) => {
        const td = document.createElement("td");
        if (cls) td.className = cls;
        td.textContent = txt;   // file data: never through innerHTML
        row.append(td);
      });
      tbody.append(row);
    });
    table.append(thead, tbody);
  }

  // Drawing, and redrawing when the width changes.
  function usableWidth(svg) {
    const b = svg.parentElement, cs = getComputedStyle(b);
    return Math.max(240, Math.floor(b.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)));
  }
  let lastWidth = 0;
  function redraw() {
    const w = usableWidth(svgCurves);
    if (w === lastWidth) return;
    lastWidth = w;
    drawCurves(w);
    drawGaps(usableWidth(svgGaps));
    if (bench) drawBench(usableWidth(svgBench));
  }
  // The hover listeners are installed ONCE, on elements that are never replaced: they delegate to
  // the latest published drawing.
  const onAimCurves = ev => { if (hoverCurves) hoverCurves.aim(ev); };
  const onLeaveCurves = ev => {
    if (hoverCurves && ev.pointerType === "mouse") hoverCurves.clearHover();
  };
  const onCancelCurves = () => { if (hoverCurves) hoverCurves.clearHover(); };
  const onRotation = () => setTimeout(redraw, 120);
  let observer = null;
  try {
    redraw();
    svgCurves.addEventListener("pointermove", onAimCurves);
    svgCurves.addEventListener("pointerdown", onAimCurves);
    svgCurves.addEventListener("pointerleave", onLeaveCurves);
    svgCurves.addEventListener("pointercancel", onCancelCurves);
    closeOnOutside(svgCurves, onCancelCurves);
    closeOnOutside(svgGaps, () => { if (hoverGaps) hoverGaps.clearHover(); });
    addEventListener("resize", redraw);
    addEventListener("orientationchange", onRotation);
    if (window.ResizeObserver) {
      observer = new ResizeObserver(redraw);
      observer.observe(document.querySelector(".perf-wrap"));
    }
  } catch (e) {
    report(e);
  }

  // Cleanup: every GLOBAL listener installed here must be removed, otherwise it survives the
  // change of view (app.js replaces #view, but not window or document).
  return () => {
    removeEventListener("resize", redraw);
    removeEventListener("orientationchange", onRotation);
    outsideHandlers.forEach(h => document.removeEventListener("pointerdown", h, true));
    if (observer) observer.disconnect();
    hide();
  };
}
