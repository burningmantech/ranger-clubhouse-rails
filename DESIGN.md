---
name: Clubhouse 3
description: A hyperlegible field manual for Black Rock Rangers — dense, warm, and readable in dust or at a desk.
colors:
  primary: "oklch(0.52 0.2 262)"
  primary-content: "oklch(100% 0 0)"
  secondary: "oklch(48% 0 89.876)"
  accent: "oklch(50% 0.2 300)"
  neutral: "oklch(30% 0.01 260)"
  neutral-content: "oklch(98% 0 0)"
  base-100: "oklch(97.5% 0.005 80)"
  base-200: "oklch(96% 0.004 80)"
  base-300: "oklch(92% 0.004 80)"
  base-content: "oklch(40% 0.01 60)"
  line: "oklch(30% 0.01 260)"
  info: "oklch(55% 0.2 260)"
  success: "oklch(48% 0.15 160)"
  warning: "oklch(48% 0.138 52.532)"
  error: "oklch(0.395 0.16 24.035)"
  sidebar-link-hq: "#524737"
  sidebar-link: "#3e4348"
  sidebar-title-hq: "#3d2503"
  sidebar-divider: "#101010"
  sidebar-content: "#f0f0f0"
  sidebar-active: "#ffc107"
  chrome: "#000000"
typography:
  display:
    fontFamily: "Atkinson Hyperlegible, system-ui, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 600
    lineHeight: 1.2
  headline:
    fontFamily: "Atkinson Hyperlegible, system-ui, sans-serif"
    fontSize: "1.1rem"
    fontWeight: 600
    lineHeight: 1.2
  title:
    fontFamily: "Atkinson Hyperlegible, system-ui, sans-serif"
    fontSize: "0.9rem"
    fontWeight: 600
    lineHeight: 1.2
  body:
    fontFamily: "Atkinson Hyperlegible, system-ui, sans-serif"
    fontSize: "0.9rem"
    fontWeight: 400
    lineHeight: 1.2
  label:
    fontFamily: "Atkinson Hyperlegible, system-ui, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
rounded:
  none: "0px"
  xxs: "2px"
  xs: "4px"
  sm: "6px"
  default: "8px"
  field: "0.5rem"
  box: "0.75rem"
  base: "12px"
  lg: "16px"
  selector: "1rem"
spacing:
  cell: "6px"
  tight: "8px"
  panel: "12px"
  region: "16px"
  section: "24px"
  page-max: "90rem"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.primary-content}"
    rounded: "{rounded.field}"
    typography: "{typography.body}"
    height: "36px"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.secondary}"
    rounded: "{rounded.field}"
    typography: "{typography.body}"
    height: "36px"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.base-content}"
    rounded: "{rounded.field}"
    typography: "{typography.body}"
    height: "36px"
  input-field:
    backgroundColor: "{colors.base-100}"
    textColor: "{colors.base-content}"
    rounded: "{rounded.field}"
    typography: "{typography.body}"
    height: "36px"
  table-container:
    backgroundColor: "{colors.base-100}"
    textColor: "{colors.base-content}"
    rounded: "{rounded.box}"
  table-header:
    backgroundColor: "{colors.base-200}"
    textColor: "{colors.base-content}"
    typography: "{typography.title}"
    padding: "6px"
  card-standard:
    backgroundColor: "{colors.base-100}"
    textColor: "{colors.base-content}"
    border: "1px {colors.line}"
    rounded: "{rounded.base}"
    padding: "none -- the call site keeps its own"
  box-default:
    backgroundColor: "{colors.base-100}"
    textColor: "{colors.base-content}"
    rounded: "{rounded.lg}"
  badge-soft:
    backgroundColor: "{colors.base-200}"
    textColor: "{colors.base-content}"
    rounded: "{rounded.selector}"
    typography: "{typography.label}"
---

# Design System: Clubhouse 3

## Overview

**Creative North Star: "The Legible Field Manual"**

Clubhouse 3 looks like a reference document engineered to be read fast under bad conditions. Every
decision in the system trades ornament for the ability to find one fact on a crowded page — in dust
and glare on a phone, on a shared HQ screen at 3am, or in a nine-hour administrative session across
hundreds of rows. The type is hyperlegible by design rather than by taste, the body scale is a tight
0.9rem on a 1.2 line-height, and table cells are padded at 6px. Density here is not crowding; it is
the refusal to make someone scroll for something that could have fit.

The surfaces are warm and the ink is cool. In light mode every base surface sits at hue 80 — a faint
paper-tan — while the single chromatic voice, a mid-blue primary at hue 262, appears only on things
you can act on. In dark mode the surfaces flip cool (hue 260) but the text stays warm (hue 80), so
the page reads as ink on stone in both directions rather than as one theme inverted. The result is a
document that feels made of material, not of rectangles.

What the system explicitly refuses: decorative color, colored text as emphasis, competing accents,
and any component invented ad hoc. Color carries meaning or it does not appear. Emphasis is weight
and size. New components and new color styling both require approval before they exist, which is why
the visual vocabulary has stayed small across roughly twenty functional namespaces.

**Key Characteristics:**

- One typeface for everything — Atkinson Hyperlegible, with its monospaced cut reserved for code.
- Warm surfaces in light, cool surfaces in dark, warm text in both.
- A single rationed accent; semantic status colors only where status exists.
- Flat at rest; a soft diffuse shadow marks a whole grouped region, not a widget.
- A 4px start border is the system's signature mark for "this belongs together".
- Every `responsive: true` table becomes a stack of labeled cards below 1024px.
- 36px is the floor for anything a finger touches, without exception.

## Colors

A near-monochrome warm-neutral field with one blue voice and four semantic signals, all authored in
OKLCH and consumed only through DaisyUI's semantic token names.

### Primary

- **Signal Blue** (`oklch(0.52 0.2 262)`): The only chromatic color in ordinary chrome. It marks
  primary actions, links, the start border on fieldsets and expanded detail cells, and the
  highlighted edge of an accent box. It is deliberately not warm — it is the one thing on the page
  that is not made of paper. In dark mode it brightens to `oklch(0.68 0.19 262)` to hold contrast
  against the near-black field.

### Secondary

- **Plain Graphite** (`oklch(48% 0 89.876)`): Zero chroma — a true gray, not a second brand color.
  It carries outline buttons and de-emphasized controls. Its chromalessness is the point: it must
  never read as a competing accent.

### Accent

- **Deep Violet** (`oklch(50% 0.2 300)`): The `accent` token. Present in the theme, near-absent in
  practice. Treat any new use as a request for approval, not as an available color. (Unrelated to
  `ButtonHelper`'s `:tertiary` variant, which is a ghost button.)

### Neutral

- **Warm Paper** (`oklch(97.5% 0.005 80)`, `base-100`): The default page and card surface. Barely
  tinted, and the tint is what keeps the interface from feeling clinical.
- **Paper Shade** (`oklch(96% 0.004 80)`, `base-200`): Table headers, even stripes, detail-row
  panels — the second plane.
- **Paper Edge** (`oklch(92% 0.004 80)`, `base-300`): Borders, dividers, and row-hover fill. The
  deepest neutral that is still a surface.
- **Field Ink** (`oklch(40% 0.01 60)`, `base-content`): All body and heading text. Warm, mid-dark,
  and never pure black.
- **Rule Line** (`oklch(30% 0.01 260)`, `--color-line`): Card and container borders. In dark mode it
  is lifted to `oklch(52% 0.01 260)` on its own, because `neutral` is too dim to draw a visible edge
  there and raising `neutral` itself would break navbar text contrast.

### Semantic

- **Success** (`oklch(48% 0.15 160)`), **Warning** (`oklch(48% 0.138 52.532)`), **Error**
  (`oklch(0.395 0.16 24.035)`), **Info** (`oklch(55% 0.2 260)`): status only. They appear at full
  strength on text and borders, and at a 5–10% tint as box fills.

### Navigation Chrome

The sidebar runs its own dark palette, context-tinted so a Ranger knows which world they are in
without reading a heading: **Slate** (`sidebar-link`, `#3e4348`) for the `me` and `hq` themes,
**Khaki** (`sidebar-link-hq`, `#524737`) for `admin`, with an **Amber Marker** (`sidebar-active`,
`#ffc107`) on the right edge of a drill trigger whose subtree holds the active item. The black it all sits on is
`chrome`, shared with the navbar, which wears it at 80%; the near-white it is written in is
`sidebar-content`. These sit outside the theme layer on purpose — chrome stays dark in both
themes — but they are tokens now, not literal hex in the markup.

### Named Rules

**The Rationed Accent Rule.** Signal Blue is the only chromatic color permitted in ordinary chrome.
If a screen has more than one non-semantic color competing for the eye, one of them is wrong.

**The Two-Temperature Rule.** Light surfaces are warm (hue 80) and dark surfaces are cool (hue 260),
while text is warm in both. Never author a surface color that breaks its mode's temperature.

**The Semantic-Only Rule.** Raw Tailwind color utilities (`text-gray-700`, `bg-white`,
`dark:bg-gray-800`) are banned outright. Use DaisyUI semantic tokens or the bridge tokens
(`text-body`, `text-heading`, `bg-default`). This is what keeps both themes correct for free.

**The Weight-Not-Color Rule.** Emphasis is `font-semibold` and a size step, never a color change.
Color that does not encode status is noise.

**The One-Status-Vocabulary Rule.** A person's status is colored by *what the reader has to do about
it*, and by one shared vocabulary — `Person::StatusesHelper` — never by a per-page map. Four
standings, four treatments, and no fifth:

| Standing | Statuses | Treatment |
|---|---|---|
| Norm | `active` | Plain text. No badge, no color. |
| Pipeline | `alpha`, `prospective`, `prospective waitlist` | Signal Blue + `user-clock` |
| Reduced | `inactive`, `inactive extension`, `auditor`, `past prospective` | Warning + `circle-pause` |
| Context | `echelon`, `retired`, `resigned`, `bonked`, `uberbonked`, `dismissed`, `suspended`, `deceased`, `vintage` | Plain Graphite + `circle-minus` |
| Anomaly | anything unrecognized, including a report's `deleted` fallback | Error + `triangle-exclamation` |

The norm carrying no color at all is what gives the other three their force: on an eight-hundred-row
roster, a chip on every row is eight hundred chips saying nothing. Two call shapes:
`person_status_badge` for a column that must render on every row, and
`person_status_exception_badges` for a roster where status is incidental and only the exception is
worth a chip. Every badge carries its icon as well as its color, because color alone fails a
colorblind reader and a sunlit phone.

## Typography

**Display Font:** Atkinson Hyperlegible (fallback `system-ui`)
**Body Font:** Atkinson Hyperlegible (fallback `system-ui`)
**Mono Font:** Atkinson Hyperlegible Mono — the monospaced cut of the same design

**Character:** The Braille Institute's hyperlegible typeface, chosen for the property that gives it
its name: letterforms engineered so that similar characters stay distinguishable at small sizes and
in poor conditions. The proportional cut carries every role in the app — display, headline, title,
body, and label alike — so the whole product speaks in one voice. The monospaced cut is a companion
of the same design, not a second family, and appears only where character cells genuinely have to
line up: `code`, `.font-mono`, ID and tag values, and log output. Both are loaded as variable fonts
across weights 200–800 with italics, self-hosted from our own origin.

### Hierarchy

- **Display** (600, 1.5rem, 1.2): Hero panel page titles (`heading_level: :h1`). One per page. An `:h2`
  hero is 1.25rem.
- **Headline** (600, 1.1rem at `lg` and above, 0.9rem below, 1.2): `ui_section` titles — the label
  on a grouped region — and every other level-2 heading (`heading-section`).
- **Title** (600, 0.9rem, 1.2): Every `<h3>` and `<h4>` (`heading-title`), table column
  headings, card section headings. Form legends are Headline-sized (1.1rem, semibold) — see Inputs /
  Fields. Nothing inside a section outweighs the section's title: the two match on a phone, and the
  Headline is a step larger from `lg` up.
- **Body** (400, 0.9rem, 1.2): Everything else. The tight leading is deliberate and is what makes a
  long table scannable in one screen.
- **Label** (600, 0.75rem, 1.2): The `data-label` prefix that appears in front of every value when a
  table folds into cards, and other micro-annotations. Sidebar section headers are the one uppercase
  role in the system (0.875rem, uppercase).

### Named Rules

**The One Typeface Rule.** There is no second family. Atkinson Hyperlegible is the default for
everything; reach for `font-mono` only when characters have to align in columns or a value is meant
to be read as a literal string — a document tag, a client ID, a raw log line. Setting prose,
headings, labels, or table text in the mono cut is a bug, not a style. If a design needs a display
face to be distinctive, it needs a better idea instead.

**The Aligned Numbers Rule.** The proportional cut sets figures at their natural widths, so
every table asks for `font-variant-numeric: tabular-nums` and columns of hours, dates, and counts
line up without anything being set in the mono face. Outside a table, reach for the `tabular-nums`
utility when digits stack vertically.

**The Tight Leading Rule.** Body leading is 1.2, not 1.5. Space between rows is bought with padding
where it aids grouping, never spent uniformly as line-height.

## Layout

The application shell is a DaisyUI drawer: a persistent sidebar from `lg` (1024px) up, an overlay
drawer below it, with the main region as the scroll container rather than the body. Content is
padded at 12px and capped at a 90rem maximum measure.

Vertical rhythm is a small set of steps repeated everywhere: 6px inside table cells, 12px for panel
interiors, 16px for a grouped region's inset, 24px between form sections. Whitespace is applied for
grouping and never for decoration — the density mandate means an empty band must justify itself.

The one breakpoint that matters is `lg` at 1024px, and it is where the interface changes form rather
than merely reflowing. Above it, tables are native `<table>` elements so columns auto-size to their
content, and hero panels place stats beside the title. Below it, every `responsive: true` table row
becomes its own labeled card with the column heading rendered as a `::before` prefix, and stats move
under the title. Button rows stack full-width below `md` (768px) — the one fact that breakpoint marks —
and sticky button rows pin to the bottom of the viewport on mobile with a spacer reserving their
height in flow.

### Named Rules

**The 1024 Fold Rule.** The responsive fold is written as `@media (width < theme(--breakpoint-lg))`
— the exact negation of Tailwind's `lg:`. A `max-width: 64rem` fold overlaps `lg:` at exactly
1024px, and content carrying `hidden lg:table-cell` beside an `lg:hidden` stand-in then belongs to
neither layout and renders nowhere. Never express this fold as `max-width`.

**The Top-Align Rule.** Table rows align to the top, set once on `:where(tbody)` so the specificity
stays at zero. When one cell holds a wrapped note and its neighbor holds a single date, middle
alignment floats the short cell away from the row's first line and the eye loses which value belongs
to which record.

## Elevation & Depth

Flat at rest. Depth comes from tonal layering through the `base-100` → `base-200` → `base-300`
stepping, not from stacked shadows. The single exception is a soft, wide, low-opacity shadow used to
lift a whole grouped region off the page — the `.box` container and the hero panel — which reads
less like elevation and more like a sheet of paper laid on a desk. Cards and table containers stay
at `shadow-xs` or `shadow-sm`; row hover is a background change, not a lift.

### Shadow Vocabulary

- **Region lift** (`box-shadow: 0px 0px 6px 4px rgba(0,0,0,0.1)`): The `.box` and `.me-hero-panel`
  containers only. Wide, diffuse, directionless.
- **Surface hint** (`shadow-xs` / `shadow-sm`): Cards and table containers. Barely perceptible; its
  job is to separate a surface from the page, not to raise it.

### Named Rules

**The Flat-By-Default Rule.** A new component gets no shadow. Region lift is reserved for containers
that group an entire section of a page; anything smaller separates itself with a border or a tonal
step.

## Shapes

Corners are consistently soft but never pill-like outside of badges: 8px is the everyday radius,
0.5rem for form fields and buttons, 0.75rem for table containers and boxes, 12–16px for cards and
lifted regions. Borders are a uniform 1px hairline in the Rule Line color.

The system's signature is not a corner but an edge: a **4px start border** in Signal Blue marks a
grouped region wherever one appears — form fieldsets (with a 5%-to-transparent gradient wash
trailing off it), the expanded detail cell under a table row, and accent boxes. Its meaning is
consistent: this block is a unit, and it hangs off the rule to its left.

### Named Rules

**The Left-Bar Rule.** A 4px start border means "these things are one group". Do not use it for
emphasis, for status, or as decoration — its value is that it means exactly one thing.

## Components

### Buttons

- **Shape:** Softly rounded (`0.5rem`, DaisyUI `--radius-field`), no internal icon gap (`gap: 0`).
- **Primary:** Signal Blue fill with white content. The only filled chromatic control on most pages.
- **Secondary:** Outlined graphite — `btn-secondary btn-outline`. **Tertiary / Ghost:** transparent.
- **Sizes:** `xs`/`sm`/`md`/`lg`/`xl` map to DaisyUI's scale, but `sm` is overridden to 9 size steps
  (36px) rather than DaisyUI's 8 (32px) so it clears the touch floor.
- **Dark mode error:** `btn-error` gets a darkened fill (`oklch(42% 0.15 25)`) because the bright
  error red that `text-error` needs for legibility is too hot as a large area of fill.
- **Rows:** `.button-row` wraps horizontally with viewport-relative gaps from `md` (768px) up, and
  stacks to full-width blocks below it — the one layout fact `md` marks.

### Cards / Containers

- **`card-standard`:** `base-100` fill, 1px Rule Line border, 12px radius, no shadow and no
  padding. `ui_card` renders this same utility, adding `shadow-xs` by default and a centered
  title. It is the app's one card.
- **`.box` / `ui_section`:** the workhorse region container — 16px radius, 1px border, region-lift
  shadow, 16px inset, title at 0.9rem rising to 1.1rem at `lg`.
- **Themed boxes:** success/warning/error/info variants pair a 5–10% tint fill with a matching
  border and text color. Warning boxes force `color: inherit` on their descendants — except buttons
  and badges — so muted text does not wash out inside them.

### Tables

- **Container:** `base-100` fill on a 0.75rem radius with a `base-300` border and horizontal
  overflow.
- **Header:** `base-200` fill, semibold, 6px padding, left-aligned unless explicitly centered.
- **Rows:** 1px bottom border; hover fills with `base-300`; striping alternates `base-100`/`base-200`.
- **Row state:** `t.row state:` is the only way a row says what it is — `:error` and `:warning` for
  one needing attention, `:success` for one the request just acted on, `:total` for a sum (`base-300`
  and semibold, because `base-200` is the stripe colour and a sum tinted like every even row is not
  marked at all). Severity tints come from `SeverityStyleHelper`, so a red row is red the same way
  everywhere. Every tint carries `!` — `odd:`/`even:` is `:nth-child` and outranks a plain background
  utility — which is exactly why call sites must not spell their own. A page whose own `:success`
  means "nothing to flag" stops before `state:` rather than tinting a healthy report green.
- **Detail rows:** an expanding full-width panel on `base-200` whose cell carries the 4px start
  border. Never striped — `odd:`/`even:` is `:nth-child` and a hidden detail row still counts, so a
  table using detail rows passes `striped: false` outright.
- **Toggle affordance:** the chevron on a detail toggle rotates 180° when `aria-expanded="true"`.
- **Below `lg`, with `responsive: true`:** the table becomes cards of labeled fields, header hidden to screen
  readers only. The fields wrap to the width available rather than stacking unconditionally —
  one per line on a phone, three or four on a tablet — so a tablet reads as a tablet instead
  of a tall phone. A field holding free text takes a line of its own.

### Inputs / Fields

- **Style:** DaisyUI `input`/`select` on a `0.5rem` radius; icon-prefixed fields take a 2.5rem
  inline-start pad. Minimum height 36px.
- **Fieldsets:** the grouping unit — 4px Signal Blue start border, a `primary/5`-to-transparent
  gradient, 24px bottom margin, and a legend that is full-width, semibold, 1.1rem, underlined by a
  `base-200` hairline. This is the ADHD-friendly chunking pattern, and it is why forms in this app
  never read as an undifferentiated column of inputs.
- **Construction:** forms are built through `AppFormBuilder` / `ui_form`; raw `form_with` is not
  used.

### Navigation

- **Sidebar:** dark chrome, context-tinted per world (Me/HQ/default), 40px rows with a top hairline,
  uppercase section headers, badges for counts.
- **Drill-down:** multi-level panes slide horizontally at 200ms `ease-out`, clipped with
  `overflow-clip` so focusing an off-canvas item never scrolls it into view. Motion is disabled
  under `prefers-reduced-motion`.
- **Mobile:** the drawer overlays; a ghost toggle and a circular close button appear below `lg`.

### Hero Panel

The signature component. A warm neutral panel (`base-200` / `base-300` in dark) ringed in a faint
amber (`ring-signature-edge`, the token holding amber-200/40 and its dark twin) with region-lift
shadow, carrying a page's title, one-sentence description, back link, year selector, optional stat
tiles, and an optional progress bar. Stats sit beside the
title above `lg` and beneath it below. Stat tiles are ring-outlined rather than filled, and they need an approved plan
(`design-rules` > Hero Panel Stats): the default home for summary numbers is a `ui_stat_row` in the
body, and only the /me dashboard banner still carries them in the hero. That warm outline, and the
amber tile the stat schemes can wear, are the only warm accents left in the content area, and they
are what make a Clubhouse page recognizable at a glance.

### Empty State

A dashed 1px border on a 6px radius with muted stone text — deliberately quieter than any real
content, so an empty region reads as "nothing here" rather than as a component that failed.

### Badges

DaisyUI badges throughout, used for status and counts. In dark mode `badge-soft badge-secondary` is
overridden to render as a neutral chip: the theme's secondary is a zero-chroma gray, and an 8% tint
of a gray on a near-gray surface produced gray-on-gray text inside a pill within 5% lightness of the
page. Colored soft variants survive on chroma; the gray one cannot.

## Do's and Don'ts

### Do:

- **Do** reach for `ButtonHelper` (`button_action`, `button_link`, `submit_button`, `delete_button`)
  and `AppFormBuilder` / `ui_form`. Raw `<button>` and bare `form_with` are not part of this
  system.
- **Do** wrap a group of related fields in a fieldset so it inherits the 4px start border and
  gradient — the chunking is an accessibility feature, not a decoration.
- **Do** hold every interactive element at 36px minimum, including `btn-sm`, which is explicitly
  bumped to 9 size steps for this reason.
- **Do** write the responsive fold as `@media (width < theme(--breakpoint-lg))`.
- **Do** pass `striped: false` on any table that uses detail rows.
- **Do** name a row's state with `t.row state:` rather than painting a background at the call site,
  and make the tinted row say why in words, a badge, or an icon as well.
- **Do** give every user-facing element a dark-mode result, and verify it by toggling both
  `data-theme` and the `.dark` class — the app uses a custom `dark` variant keyed on the class, so
  changing only one produces a false reading.
- **Do** state status in words as well as color, since color alone fails both colorblind users and a
  sunlit phone screen.
- **Do** spend a surface's chroma on what is still owed, not on what is finished. A completed step
  recedes to muted and keeps its glyph; the step that is next carries the accent, and any live state
  worth finding at a distance carries the semantic tone it already uses elsewhere on the page. A
  checklist whose only colored item is the one already done points the eye at the past.

### Don't:

- **Don't** use raw Tailwind color utilities anywhere. `text-gray-700`, `bg-white`, and
  `dark:bg-gray-800` are banned; semantic tokens and bridge tokens are the only vocabulary.
- **Don't** introduce a new component or a new color treatment without approval. The vocabulary is
  small on purpose.
- **Don't** add a shadow to a new component. Flat is the default; region lift belongs to `.box` and
  the hero panel.
- **Don't** use color for emphasis. Use `font-semibold` and a size step.
- **Don't** spend vertical space that carries no grouping meaning. Excess whitespace is a defect in
  a product where users scan hundreds of rows.
- **Don't** invent a second typeface, and don't set prose, headings, labels or table text in the
  mono cut — tables align their figures with `font-variant-numeric: tabular-nums`, not by
  changing face.
- **Don't** reach past `text-body-subtle` for a secondary line. It was an alias of `text-body` and
  communicated nothing; it is now a real step (`oklch(50% 0.012 60)` light, `oklch(66% 0.012 80)`
  dark) — lightness only, on base-content's own hue, set at the lightest step that still clears
  4.5:1 on the `base-300` row-hover fill.
- **Don't** extend the sidebar's literal hex palette to new surfaces. It is documented as existing
  chrome, not as an available color system.
