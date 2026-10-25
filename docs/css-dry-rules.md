# CSS house rules — Rails + Tailwind + daisyUI

The source of truth for every `/css:*` command. Read this before proposing or making
any change to class attributes.

---

## 1. The abstraction ladder

For each duplicated class string, climb this ladder and stop at the **first** rung that fits.
Never skip to a lower rung because it is faster.

**Rung 1 — a daisyUI component class already does this.**
`btn`, `card`, `badge`, `alert`, `input`, `select`, `textarea`, `checkbox`, `toggle`, `range`,
`table`, `tabs`, `menu`, `navbar`, `drawer`, `dropdown`, `modal`, `join`, `stat`, `steps`,
`breadcrumbs`, `tooltip`, `avatar`, `loading`, `skeleton`, `divider`, `collapse`, `chat`,
`timeline`, `pagination` (via `join`), `progress`, `radial-progress`.

A hand-rolled `inline-flex items-center justify-center rounded-md px-4 py-2 …` is a `btn`.
Deleting twelve utilities in favour of `btn btn-primary` is the single highest-value change
available, because it also inherits theming, sizes, states and accessibility styling for free.

> daisyUI 5 renamed and removed some classes (`card-bordered` → `card-border`;
> `form-control` / `label-text` superseded by `fieldset` / `label`; `btn-focus` gone).
> Check the version in `package.json` / `yarn.lock` before any mass replacement, and verify
> each class you introduce actually exists in that version.

**Rung 2 — a semantic theme token replaces a hardcoded color.**
Views must not name palette colors. Map:

| Instead of | Use |
| --- | --- |
| `bg-white`, `bg-gray-50/100` | `bg-base-100`, `bg-base-200` |
| `border-gray-200/300` | `border-base-300` |
| `text-gray-900`, `text-black` | `text-base-content` |
| `text-gray-500/600` | `text-base-content/60` (opacity, not a different color) |
| `bg-blue-600 text-white` | `bg-primary text-primary-content` |
| `bg-red-50 text-red-800` | `alert alert-error` / `text-error` |
| `bg-green-*`, `bg-amber-*` | `success`, `warning` |

One exception, and it is the only one: the hero panel's signature amber is `ring-signature-edge` /
`bg-hero-tile` / `text-hero-tile-content`, theme tokens declared in `app/assets/tailwind/application.css`.
Do not map those back onto `warning` — they are a deliberately fixed hue, and `warning` would change it.

Anything that survives this mapping is a theme gap: add the color to the daisyUI theme
definition rather than inlining it. A view that names `blue` cannot be re-themed or
dark-moded, and that is the actual cost of the duplication.

**Rung 3 — the whole markup block repeats → a partial or a component.**
Rails partial with **strict locals** (Rails 7.1+):

```erb
<%# locals: (title:, href:, variant: :primary, size: :md, extra_class: nil) %>
```

Strict locals are mandatory: they turn a silently-wrong render into a loud error and they
document the component's API at the top of the file. Write the comment exactly as above: Rails
ignores one it cannot parse (`<%#locals`, `locals:(`, braces, a note after the paren) and the
partial takes any locals. `test/views/strict_locals_comment_test.rb` fails on one. Use
ViewComponent or Phlex instead when the thing needs its own tests, slots or non-trivial Ruby.

**Rung 4 — the class string repeats but the markup does not → a helper or constant.**

```ruby
# app/helpers/ui_helper.rb
def card_class(interactive: false, extra: nil)
  token_list("card bg-base-100 shadow-sm", "hover:shadow-md transition" => interactive, extra => extra.present?)
end
```

`token_list` (aliased `class_names`) is built into ActionView — use it instead of ternaries and
string interpolation. When callers must be able to *override* a default (e.g. pass `p-8` to
something that defaults to `p-4`), add the `tailwind_merge` gem and merge, rather than
concatenating and hoping source order wins.

**Rung 5 — last resort: a CSS-layer abstraction.**
A custom `@utility` (Tailwind 4) or a component class in the stylesheet. `@apply` is the
bottom rung, not the first move: it re-hides the styling from the view, is invisible to
Tailwind's IntelliSense, and tends to grow into a second, undocumented design system.
Allowed only for genuinely global primitives, and each use must be justified in the diff.

---

## 2. Hard rules

1. **No class names built by interpolation.** `class="bg-#{status}-500"` and
   `class="text-<%= color %>-600"` are invisible to Tailwind's scanner, so the utility is
   never compiled. Use a literal lookup:
   ```ruby
   STATUS_CLASS = { active: "badge-success", pending: "badge-warning", failed: "badge-error" }.freeze
   ```
   Every value must appear as a complete literal string somewhere Tailwind scans.
   A name glued to a placeholder is not one: in JS, `` `chip${active ? " chip-active" : ""}` ``
   never shows the scanner `chip` as a whole word, and `@utility chip` is not compiled. Write
   `active ? "chip chip-active" : "chip"`.
2. **Tailwind's source globs must cover every place class strings can live.** Moving a class
   string from an ERB file into `app/helpers`, `app/models`, or a `Style` constants module
   silently drops those utilities from the build unless the globs include that path. Verify
   the `content:` array (Tailwind 3) or `@source` directives (Tailwind 4) **before** any
   extraction to Ruby, not after.
3. **No inline `style=""`** for anything a utility can express. The exception is a genuinely
   dynamic numeric value, which goes through a CSS custom property:
   `style="--progress: #{pct}%"` with a utility reading `var(--progress)`.
4. **No arbitrary values** (`p-[13px]`, `text-[#1d4ed8]`, `w-[137px]`) unless there is a
   written reason. They are usually a designer's pixel value that should be a scale step or a
   theme token.
5. **No `!important` utilities.** A `!` prefix means an abstraction is fighting a caller;
   fix the abstraction or use `tailwind_merge`.
6. **Class order is meaningless.** Compare class strings as sorted token sets, never as
   strings. Two attributes with the same tokens in different order are the same duplicate.
7. **Extract on the third occurrence, not the second.** Two similar strings are often a
   coincidence; three is a pattern. The census reports both — the count is the evidence.
8. **One concern per commit.** A commit either replaces hand-rolled utilities with daisyUI
   components, or swaps palette colors for tokens, or extracts a partial. Never two at once:
   mixed commits cannot be bisected when something looks wrong.

---

## 3. Verification — required, not optional

A DRY refactor of view classes is supposed to be **behaviour-preserving**, which makes it
unusually easy to check. Every refactor commit must pass all three:

**A. Rendered-HTML equivalence.** Capture normalized HTML for the affected pages before and
after, and diff. Normalization sorts the tokens inside each `class` attribute so reordering is
invisible; a real diff then means a real change.

```ruby
# spec/support/css_snapshot.rb (or test/support/…)
def css_snapshot(name, html)
  normalized = html.gsub(/class="([^"]*)"/) { %(class="#{$1.split.sort.join(" ")}") }
  path = Rails.root.join("tmp/css_snapshots/#{name}.html")
  path.dirname.mkpath
  path.write(normalized)
end
```

Run the suite on the base commit, `cp -r tmp/css_snapshots tmp/css_snapshots_base`, refactor,
re-run, `diff -ru`. For a pure daisyUI substitution the diff is expected and must be reviewed
line by line; for a partial extraction it should be **empty**.

**B. Compiled CSS diff.** Build the stylesheet before and after
(`bin/rails tailwindcss:build`, or the app's own build command) and diff the output. Utilities
disappearing that you did not intend to remove means rule 2 was violated — a class string
moved somewhere Tailwind no longer scans.

**C. Visual check on the touched screens.** A system test screenshot, or the developer
opening the page. Class-level refactors are cheap to verify visually and expensive to get
wrong silently.

---

## 4. What "done" looks like for a cluster

- The duplicated string exists in exactly one place.
- That place has a name that describes the *role* (`_stat_tile.html.erb`, `badge_class`), not
  the appearance (`_rounded_gray_box.html.erb`).
- Call sites read as intent: `<%= render "ui/card", title: post.title %>`, not a class soup.
- No palette color, arbitrary value, `!important`, or interpolated class name was introduced.
- Snapshot diff reviewed; compiled CSS diff reviewed; page looked at.
