// Which utilities are losing to first-party CSS, and by how much.
//
// bin/css_check cannot see a CSS-only change: no markup moves, so every
// snapshot is identical and the harness reports success either way. This is
// the instrument for that blind spot. It reads the live CSSOM and reports, per
// element on the page, every property where an UNLAYERED first-party rule and
// a UTILITY both have something to say -- and what each of them says.
//
// Unlayered CSS beats every layered rule whatever the specificity, so today
// the unlayered value wins. Move that rule into `@layer components` (or base)
// and the utility wins instead. Each line below is therefore one thing that
// would change if you layered the file the rule lives in.
//
// A daisyUI component class counts as a utility here, because to the cascade it
// is one: daisyUI compiles `.btn`, `.badge` and the rest into layers nested
// inside `utilities`, so an unlayered rule beats them today and loses to them
// the moment it is layered, exactly as it would to `p-4`.
//
// USAGE
//   Paste into the browser console on a page worth checking. Results
//   accumulate across navigations in sessionStorage, so walk a few pages --
//   a dashboard, a table-heavy report, a form, a print layout -- then read
//   the total:
//
//     JSON.parse(sessionStorage.getItem('__cascade') || '{}')
//
//   Clear between runs with sessionStorage.removeItem('__cascade').
//
// WHY IT COMPARES VALUES, NOT JUST PROPERTIES
//   Most overlaps are no-ops: two rules setting `margin-bottom` to the same
//   8px, or `text-align` to the same `left`. An earlier version reported bare
//   property overlap and cried wolf about ~60 findings where only 21 were real
//   differences. Same-value pairs are dropped here.
//
// WHAT IT DOES NOT MODEL
//   - Media queries. A rule inside `@media (width < lg)` is reported whether
//     or not the viewport is in range; check the source before believing one.
//   - Source order between two unlayered first-party files. Layering a file
//     also makes it lose to other unlayered CSS: layering components/lexxy.css
//     alone would hand the win back to the vendored stylesheets/lexxy-*.css.
//     This only compares against utilities.
//   - `@utility` classes are in the utilities layer, so a first-party rule
//     beating one of those shows up here and is often deliberate.
//   - Anything but a bare `.class` rule. daisyUI styles a good deal through
//     descendants -- `.table :where(th, td)`, `.menu li > a` -- and none of
//     that is read, so a quiet run on a file that restyles the inside of a
//     daisyUI component proves nothing. Read the computed style instead.
//
// See docs/css-refactor/plan.md, "The precedence pass", for the rules in this
// app that must never be layered, and why.
(() => {
  const sheets = [...document.styleSheets].filter(s => {
    try { return !!s.cssRules } catch (e) { return false }
  });
  const util = new Map();   // "p-4" -> { property: value }, utilities' own rules
  const sub = new Map();    // "btn" -> { property: value }, layers nested in it
  const un = [];            // [{ sel, d: { property: value } }]

  const decls = r => {
    const o = {};
    for (let i = 0; i < r.style.length; i++) o[r.style[i]] = r.style.getPropertyValue(r.style[i]);
    return o;
  };

  // `layer` is the OUTERMOST layer a rule sits in, because that is the one that
  // decides how it fares against unlayered CSS. It used to be the nearest, and
  // CSSOM names a nested block by its own name alone: daisyUI's
  // `@layer utilities { @layer daisyui.l1.l2.l3 { .btn {…} } }` was filed under
  // `daisyui.l1.l2.l3`, matched neither branch below, and took all ~1,500
  // daisyUI rules with it. A rule forcing `display: block` onto every `.btn` in
  // a button row was reported as no conflict at all.
  const walk = (rules, layer, nested) => {
    for (const r of rules) {
      const kind = r.constructor.name;
      if (kind === 'CSSLayerBlockRule') { walk(r.cssRules, layer || r.name || '(anon)', !!layer); continue }
      if (kind !== 'CSSStyleRule') { if (r.cssRules) walk(r.cssRules, layer, nested); continue }
      if (layer === 'utilities') {
        // Only a bare ".class" rule, so ".p-4" counts and ".dark\:x:where(...)" does not.
        const m = r.selectorText.match(/^\.((?:\\.|[^\s.:>+~[,])+)$/);
        if (m) {
          const c = m[1].replace(/\\/g, '');
          const into = nested ? sub : util;
          into.set(c, Object.assign(into.get(c) || {}, decls(r)));
        }
      } else if (!layer) {
        un.push({ sel: r.selectorText, d: decls(r) });
      }
      if (r.cssRules) walk(r.cssRules, layer, nested);
    }
  };
  sheets.forEach(s => walk(s.cssRules, null, false));

  const out = JSON.parse(sessionStorage.getItem('__cascade') || '{}');
  for (const rule of un) {
    let els;
    try { els = document.querySelectorAll(rule.sel) } catch (e) { continue }
    for (const el of els) {
      for (const c of el.classList) {
        // A layer's own rules beat its sublayers whatever the source order, so a
        // class with both (`@utility x { @apply btn … }`) answers with its own.
        const u = { ...sub.get(c), ...util.get(c) };
        for (const p in rule.d) {
          if (!(p in u)) continue;
          if (rule.d[p].trim() === u[p].trim()) continue;   // same value: layering changes nothing
          out[`${rule.sel} || ${p} || .${c}`] = `now:${rule.d[p]}  ->  after:${u[p]}`;
        }
      }
    }
  }
  sessionStorage.setItem('__cascade', JSON.stringify(out));
  return { page: location.pathname, realDifferences: Object.keys(out).length };
})()
