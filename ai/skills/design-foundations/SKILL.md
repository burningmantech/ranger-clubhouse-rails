---
name: design-foundations
description: Color tokens, typography scale, spacing, and dark mode patterns for Clubhouse 3. Use when applying colors, text sizes, spacing, or ensuring dark mode support in views and components.
---




# Design Foundations

## Color System

**CRITICAL:** Always use semantic color tokens. Never use direct Tailwind color values (e.g., `text-gray-700`) when a semantic token exists (e.g., `text-body`).

### Semantic Text Colors

| Token | Usage | Light Mode | Dark Mode |
|-------|-------|------------|-----------|
| `text-body` | Primary body text | `--color-body` | `--color-body` |
| `text-heading` | Headings | `--color-heading`, a real step above body | same |
| `text-stone-emphasis` | Emphasised body text | `--color-body` (weight carries the emphasis) | same |
| `text-stone-muted` | Muted/secondary text | 90% ink mixed toward paper | same |
| `text-stone-subtle` | Subtle / de-emphasised text | `--color-body-subtle` | same |
| `text-primary` | Brand-colored text (Signal Blue) | `--color-primary` | `--color-primary` |
| `text-success` | Success emphasis | `--color-success` | `--color-success` |
| `text-warning` | Warning emphasis | `--color-warning` | `--color-warning` |
| `text-error` | Danger emphasis | `--color-error` | `--color-error` |

### Semantic Background Colors

| Token | Usage | Light Mode | Dark Mode |
|-------|-------|------------|-----------|
| `bg-base-100` | Page and card backgrounds | base-100 | base-100 |
| `bg-default-soft` | Soft neutral (alias of base-100) | base-100 | base-100 |
| `bg-default` | Neutral inner boxes | base-200 | base-200 |
| `bg-default-strong` | Strong neutral, hover states | base-300 | base-300 |
| `bg-primary` | Brand color (Signal Blue) | primary | primary |
| `bg-success` | Success state | Green-500 | Green-600 |
| `bg-success/10` | Soft success tint | success @ 10% | success @ 10% |
| `bg-warning` | Warning state | Amber-500 | Amber-600 |
| `bg-warning/10` | Soft warning tint | warning @ 10% | warning @ 10% |
| `bg-error` | Danger state | Red-500 | Red-600 |
| `bg-error/10` | Soft danger tint | error @ 10% | error @ 10% |
| `bg-base-300` | Disabled state | base-300 | base-300 |

### Border and Ring Colors

| Token | Usage |
|-------|-------|
| `border-line` | Standard borders |
| `border-base-300` | Table and container borders |
| `border-primary/30` | Subtle brand borders |
| `border-success/30` | Success borders |
| `border-warning/30` | Warning borders |
| `border-error/30` | Danger borders |
| `ring-signature-edge` | The signature outline; carries its own dark value, so no `dark:` twin |

### Naming Rule (read this before inventing a token)

Semantic colours come from daisyUI: `primary`, `secondary`, `accent`, `neutral`,
`info`, `success`, `warning`, `error`, `base-100/200/300` — plus the bridge tokens
declared in `app/assets/tailwind/application.css`: `default`, `default-soft`,
`default-strong`, `body`, `body-subtle`, `heading`, `line`, plus the three that
carry the signature amber — `signature-edge`, `hero-tile`, `hero-tile-content` —
and the always-dark chrome set: `chrome`, `sidebar-content`, `sidebar-divider`,
`sidebar-active` (chrome stays dark in both themes and takes no `dark:` variant).
A utility is real only
if it is `<property>-<one of those>` — optionally with a Tailwind **opacity
modifier** (`bg-error/10`) or a variant (`dark:text-warning`).

Beyond that list there is **no `-soft`, `-strong`, or `-subtle` suffix and no
`fg-` infix** on colour utilities. `text-fg-warning-strong`, `bg-error-soft`,
`bg-error-softer` and `border-error-subtle` are not tokens; Tailwind silently
generates nothing for them and the element renders in the inherited colour. Use
`text-warning`, `bg-error/10`, `border-error/30`. (`bg-default-soft` and
`text-body-subtle` are real only because `default-soft` and `body-subtle` are
declared tokens.)

The neutral text scale (`text-stone-muted`, `text-body-subtle`, …) is the one
place suffixes are real, because those are hand-written `@utility` rules in
`app/assets/stylesheets/components/text-colors.css`. If a token is not in a
table above, grep that directory before using it.

To confirm any class actually compiles:

```bash
grep -c 'text-warning{' app/assets/builds/tailwind.css
```

### Color Usage Discipline

**CRITICAL**: Interfaces must not be "busy" in a color sense. Limit color usage to prevent distracting users.

**Color Allocation:**

| Element Type | Color Strategy | Example |
|--------------|----------------|---------|
| Body text | Warm neutral ink | `text-body`, `text-stone-emphasis` |
| Backgrounds | Warm paper surfaces | `bg-base-100`, `bg-default` |
| Primary CTAs | Brand color (Signal Blue) | `bg-primary` with `btn-primary` |
| Status indicators | Semantic (green/amber/red) only where status exists | `text-success`, `bg-warning/10` |
| Decorative elements | **AVOID** colored decoration | No colored borders/backgrounds for aesthetics |
| Icons | Neutral unless conveying status | `text-stone-muted` or status icon classes |

**The brand color is blue, not amber.** `--color-primary` is `oklch(0.52 0.2 262)` in light mode and
`oklch(0.68 0.19 262)` in dark — Signal Blue, the only chromatic color permitted in ordinary chrome. Amber is a
*status* color (`warning`). Three pieces of non-semantic amber are left, all documented legacy rather than a
palette to extend: the signature outline (`ring-signature-edge`) and the amber stat tile (`bg-hero-tile`,
`text-hero-tile-content`), which are theme tokens carrying their own dark values and so take no `dark:` twin;
the progress badge's warm gradient (`ui_progress_box_helper.rb`), still raw palette on purpose, because
turning it into a theme-derived mix repaints it; and the sidebar's active-item marker, the `sidebar-active` token (`#ffc107`). Surfaces
are warm (hue 80) in light mode and cool (hue 260) in dark; text is warm in both.

**AVOID:**
- Colored backgrounds for visual variety (use cards/sections with neutral backgrounds)
- Colored text for emphasis (use weight and size instead: `font-semibold`, `text-lg`)
- Multiple accent colors competing for attention
- Colorful borders, gradients, or decorative elements without semantic purpose

---

## Typography

### Font Families

**CRITICAL:** Do not introduce any new fonts.

**Default Font**: Atkinson Hyperlegible — the proportional cut, used for everything:
headings, labels, table cells, prose. This is `font-sans` and the unstyled default.

**Monospaced Font**: Atkinson Hyperlegible Mono — the monospaced cut of the same design,
applied with `font-mono`. Reserve it for content that needs aligned character cells or
reads as a literal string: `<code>`, document tags, client IDs, log output, format
examples. Never set prose, headings, labels, or ordinary table text in it.

Both are self-hosted variable fonts (weights 200–800, with italics) declared in
`app/assets/stylesheets/fonts.css`. Nothing is loaded from Google Fonts.

### Type Scale

**CRITICAL:** Default to `text-base` for body content. Never use smaller sizes for primary content.

The theme sets `text-base` to **0.9rem on a 1.2 line-height** (`--text-base` and
`--text-base--line-height` in `app/assets/tailwind/application.css`) — DESIGN.md's Tight
Leading Rule. Do not "fix" this to 16px or 1.5; buy row spacing with padding, not leading.

| Class | Size | Usage |
|-------|------|-------|
| `text-xs` | 0.75rem | **Restricted use** - see below |
| `text-sm` | 0.875rem | **Restricted use** - see below |
| `text-base` | 0.9rem | Body text, form labels, table content (default) |
| `text-lg` | 1.1rem | Section titles at `lg` and up, form legends |
| `text-xl` | 1.25rem | Card titles, `hero_panel` `:h2` titles |
| `text-2xl` | 1.5rem | Page titles (`hero_panel` `:h1`) |
| `text-3xl` | 1.875rem | Legacy `page_title` helper only |
| `text-4xl+` | 2.25rem+ | Hero text |

### When to Use `text-xs`

**AVOID** using `text-xs` except for these specific cases:

**Acceptable uses:**
- Button size variants (`btn-xs`)
- Badges (`ui_badge` defaults to `text-xs`; pass `size:` where a badge sits in a headline)
- Mobile-only labels in responsive tables
- Icon sizing within links
- Decorative/non-essential footer text
- Progress bar labels inside the bar element

**CRITICAL - Never use `text-xs` for:**
- Any content users need to read
- Warning or error messages
- Instructions or disclaimers
- Labels users need to understand
- List items with important information
- Notes or fine print that affects user actions

### When to Use `text-sm`

**PREFERRED** for secondary/supporting content only:

**Acceptable uses:**
- Compact navigation elements (sidebar items, dropdown menus)
- Button size variants (`btn-sm`)
- Status badges and pills
- Form help text and error messages (secondary/supporting info)
- Metadata (timestamps, "Posted by", etc.)
- Fine print or legal text

**CRITICAL - Never use `text-sm` for:**
- Body text or main content
- Table content (use `text-base`)
- Tab labels
- Form labels
- Primary information in cards
- Empty state messages
- Paragraph content

### Font Weights

| Class | Weight | Usage |
|-------|--------|-------|
| `font-normal` | 400 | Body text |
| `font-medium` | 500 | Labels, slight emphasis |
| `font-semibold` | 600 | Headings, buttons |
| `font-bold` | 700 | Strong emphasis |

### Heading Levels

**CRITICAL:** One style per level, whatever page it is on, set by one utility
(`app/assets/stylesheets/components/headings.css`). Never spell a size or weight on an
`<h2>`–`<h4>`: no `font-bold`, `text-lg`, `text-xl` or `text-2xl`.

| Level | Class | Is | Matches |
|-------|-------|----|---------|
| `<h1>` | from `hero_panel heading_level: :h1` | `text-2xl font-semibold` | DESIGN.md Display |
| `<h2>` | `heading-section` | `text-base lg:text-lg font-semibold` | the `ui_section` title (DESIGN.md Headline) |
| `<h3>`, `<h4>` | `heading-title` | `text-base font-semibold` | `ui_section_subheading`, action box, callout titles (DESIGN.md Title) |

```erb
<h2 class="heading-section text-heading mt-6 mb-2">Pods</h2>
<h3 class="heading-title text-success">Radio Authorized</h3>
```

Nothing inside a section may outweigh the section's title, so an `<h3>` never takes `text-lg`.
`ui_accent_card` follows its `heading_level:` (`TITLE_STYLES`). Colour stays free: a status
heading may be `text-success` or `text-error`. Surfaces with their own stylesheet keep it: the
mega menu, the login screen, the ROC photo board, print sheets, modal titles.

---

## Spacing

Follow Tailwind spacing conventions consistently:

| Scale | Value | Common Usage |
|-------|-------|--------------|
| `2` | 0.5rem | Tight spacing, inline elements |
| `3` | 0.75rem | Button padding, small gaps |
| `4` | 1rem | Standard padding, form gaps |
| `6` | 1.5rem | Section spacing |
| `8` | 2rem | Large section spacing |

**Common patterns:**
- Card padding: `p-4` or `p-2 lg:p-4`
- Section margin: `mb-4`
- Button row gaps: `gap-2` or `gap-4`
- Form field spacing: `mb-3` (the builder's wrapper)

---

## Touch Targets

**The floor is 36px — `min-h-9`.** This is the canonical statement; AGENTS.md
and every other doc defers here.

| Spelling | Value | Use |
|----------|-------|-----|
| `min-h-9` | 36px | The floor, where the element does not already have it |
| `min-w-9` | 36px | The width floor, where nothing else sets the width: a `<label>`, a bare span or slot |
| `btn-square` | 36px | Icon-only buttons, so the hit area is square |

**A button is already at the floor.** `accessibility.css` raises `.btn-sm` and
`.select-sm` to 36px, so every `ButtonHelper` control and every `select-sm`
clears the floor by being that size. Do not pass `class: "min-h-9"` to a button
helper — it changes nothing, and it reads as though the floor were in doubt.
`min-h-9` is for the elements nothing floors: a `<label>` wrapping a checkbox,
a hand-written `<summary>` (`ui_disclosure` and `ui_accordion` floor their own),
a bare link.

**An icon-only button takes `btn-square`, not `min-w-9`.** Its side padding
already makes a `btn-sm` holding one icon 41px wide, so `min-w-9` changes
nothing there either. `btn-square` sets the width to the button's own 36px and
drops the padding, so the icon sits in a 36px square and lines up with a 36px
empty slot beside it (`common/_move_buttons`). `min-w-9` is for the elements
nothing floors: a `<label>`, a bare span or slot. The navbar's search trigger
keeps it too: icon-only below `lg` with its padding cut to `px-2`, it comes to
33px, and `btn-square` would also fix the width of its labelled desktop form.

**Rules:**
- Never write `min-h-[36px]`, `min-h-11`, or a raw `min-height` for a touch
  target — one spelling keeps the value greppable and changeable in one pass.
- Put the class on the element that actually receives the tap. For a checkbox
  or radio, that is the wrapping `<label>`, not the box and not a sibling
  `<div>` — a min-height on a bare div is not clickable.
- Pair `min-h-9` with `min-w-9`, never with a different width step.
- When a control must sit below the floor, say so in a comment and give the
  reason. `LinkHelper::TABLE_LINK_CLASSES` (20px, dense table rows) is the one
  standing exception.

**Standards context:** 36px clears WCAG 2.5.8 Target Size (Minimum, AA, 24px)
with room to spare. It does not meet 2.5.5 Target Size (Enhanced, AAA, 44px);
that is a deliberate trade for information density on the report tables, taken
knowingly rather than by drift.

---

## Border Radius

| Class | Value | Usage |
|-------|-------|-------|
| `rounded-base` | 12px | Buttons, inputs |
| `rounded-lg` | 16px | Modals, panels that are not cards |
| `rounded-xl` | 12px | Alias of `rounded-base` -- the scale stops at `lg`, so `xl` falls through to Tailwind's 0.75rem |
| `rounded-2xl` | 16px | Alias of `rounded-lg`, same reason (1rem) |
| `rounded-full` | 9999px | Badges, avatars, pills |

---

## Shadows

| Class | Usage |
|-------|-------|
| `shadow-xs` | Cards, subtle elevation |
| `shadow-sm` | Buttons, dropdowns |
| `shadow-md` | Modals, overlays |
| `shadow-lg` | Popovers, menus |
| `shadow-xl` | Prominent overlays |

**Flat by default** (DESIGN.md): a new component gets no shadow. Region lift belongs to `.box`
and the hero panel; hover is a colour change, never a lift.

**Custom shadow (hero panels):**
```css
shadow-[0px_0px_6px_4px_rgba(0,0,0,0.1)]
```

---

## Interactive States

**CRITICAL:** Button helpers (`button_link`, `button_action`, `submit_button`, etc.) already include proper interactive states. Only apply these manually for custom interactive elements **outside** the helper system.

### State Modifiers

| Modifier | When to Use |
|----------|-------------|
| `hover:` | Clickable elements (links, buttons, cards) |
| `focus-visible:` | All focusable elements (keyboard navigation) |
| `active:` | Button press feedback |
| `disabled:` | Disabled controls |
| `group-hover:` | Child elements that change on parent hover |

### Focus Rings

Always use the two-part focus pattern for keyboard accessibility:

```erb
focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2
```

`focus-visible:`, not `focus:`: a `focus:` ring also appears on a mouse click and stays there,
which on a link that is also a selected tile (`ui_stat_link active:`) reads as a second selection.
A text field is the exception: daisyUI's `.input` rings on `:focus`, because the browser treats
typing focus as visible anyway.

Use `focus-visible:ring-4` for larger or more prominent elements.

**CRITICAL:** Use semantic color tokens for focus rings (e.g., `focus-visible:ring-primary`, `focus-visible:ring-error`) — never raw Tailwind colors like `focus-visible:ring-blue-500`.

The gap `ring-offset-2` leaves is painted `base-100` by default (`app/assets/stylesheets/base.css`),
the surface nearly every control sits on, so the pattern above needs no colour for it. On another
surface, add `focus-visible:ring-offset-<surface>` (e.g. `focus-visible:ring-offset-base-200`) so the gap matches what
is behind it.

### Transitions

| Pattern | When to Use |
|---------|-------------|
| `transition-colors duration-200` | Color-only changes (hover states, focus rings) |

```erb
<%# Color transition on a custom link %>
<a class="text-body hover:text-primary transition-colors duration-200">...</a>
```

Hover is a colour change, never a lift or a shadow step (DESIGN.md > Flat-By-Default).
Semantic tokens re-resolve per theme, so `hover:text-primary` needs no `dark:` twin; add a
`dark:` variant only where a raw value is unavoidable.

---

## Dark Mode

The application uses class-based dark mode. The `.dark` class is toggled on the `<html>` element.

**CRITICAL:** Every user-facing element must render correctly in dark mode. Semantic tokens
do this for free — they re-resolve per theme — so most markup needs no `dark:` variant at
all. Raw Tailwind colours (`bg-white dark:bg-gray-800`) are banned (AGENTS.md > Hard Rules);
a `dark:` pair is only for the rare raw value inside a component CSS file.

### Common Dark Mode Patterns

```erb
<%# Text: tokens carry both themes %>
class="text-heading"
class="text-body"
class="text-stone-muted"

<%# Surfaces %>
class="bg-base-100"
class="bg-base-200"
class="bg-warning/10"

<%# Borders %>
class="border-line"
class="border-warning/30"

<%# Status %>
class="text-success"
class="text-warning"
class="text-error"
```

Verify by toggling **both** `data-theme="dark"` and the `.dark` class on `<html>` — the app
keys its `dark` variant on the class, so flipping only one gives a false reading.

---

## Custom Utility Classes

The project defines custom `@utility` directives for frequently used pattern combinations.

### When to Extract a Custom Utility

Extract a custom utility when the **same 3+ classes** appear in **3+ places**.

**Where to add:** `app/assets/stylesheets/components/` (NOT `app/assets/tailwind/application.css`)

**Naming convention:** Lowercase, hyphenated (e.g., `flex-center`, `icon-success`)

**Syntax:**

```css
/* app/assets/stylesheets/components/flex-patterns.css */
@utility flex-center-gap-2 {
  @apply flex items-center gap-2;
}
```

**CRITICAL:** New utilities require user approval per `design-rules`. Always ask before creating a new utility.

### Existing Utilities

### Status Icon Colors

```erb
<%= fa_icon "circle-check", :solid, class: "icon-success" %>
<%= fa_icon "circle-exclamation", :solid, class: "icon-warning" %>
<%= fa_icon "triangle-exclamation", :solid, class: "icon-error" %>
<%= fa_icon "circle-info", :solid, class: "icon-info" %>
```

- `icon-success` → `text-success`
- `icon-warning` → `text-warning`
- `icon-error` → `text-error`
- `icon-info` → `text-info`

### Common Flex Patterns

```erb
<div class="flex-center">Content</div>
<div class="flex-center-gap-2">Icon and text</div>
<div class="inline-flex-center-gap-2">Badge content</div>
```

- `flex-center` → `flex items-center`
- `flex-center-gap-2` → `flex items-center gap-2`
- `inline-flex-center-gap-2` → `inline-flex items-center gap-2`

### Neutral Text Color System

Steps for text that is neither a heading nor a status. Each derives from the theme's own ink
(`--color-base-content`) and paper (`--color-base-100`) in
`app/assets/stylesheets/components/text-colors.css`, so they follow a theme change and need no
`dark:` variant. The `stone` in the names is historical; nothing about them is stone any more,
and none of them may be replaced by naming a palette colour at the call site.

Strongest ink first, OKLCH `L` light / dark, contrast against `base-300`:
`text-heading` 30/85 (10.8:1) → `text-body` 40/75 (7.3:1) → `text-stone-muted` 45.75/69.3
(5.7:1) → `text-stone-subtle` 50/66 (4.8:1). `text-heading-primary` is the same ink as
`text-heading`; `text-stone-icon` the same as `text-stone-subtle`.

```erb
<h1 class="text-heading-primary">Main Heading</h1>
<h2 class="text-heading">Section Heading</h2>
<p class="text-stone-emphasis">Important body text</p>
<span class="text-stone-muted">Secondary information</span>
<small class="text-stone-subtle">Fine print, labels</small>
<%= fa_icon "icon", :solid, class: "text-stone-icon" %>
```

---

## Related Skills

- **design-rules**: Critical rules, approval workflows
- **design-components**: Component helpers using these foundations
- **design-forms**: Form styling with semantic tokens
- **design-layouts**: Layout patterns and breakpoints
- **design-content**: Accessibility and ADHD-friendly patterns

## Full Documentation

For complete documentation, see [docs/DESIGN-GUIDE.md](../../docs/DESIGN-GUIDE.md) - Foundation Layer and Theme System sections.
