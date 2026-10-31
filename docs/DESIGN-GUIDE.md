# Clubhouse 3 UX/UI Design & Styling Guide

> A comprehensive design system guide for the Black Rock Rangers Secret Clubhouse application.
> For use by developers, designers, and LLMs working on the frontend interface.

**Related Documentation:**

- Design System Skills (auto-applied by agent):
    - [design-rules](../ai/skills/design-rules/SKILL.md) - Critical rules, approval workflows, anti-patterns
    - [design-foundations](../ai/skills/design-foundations/SKILL.md) - Colors, typography, spacing, dark mode
    - [design-components](../ai/skills/design-components/SKILL.md) - UI component helpers (buttons, cards, tables,
      modals)
    - [design-forms](../ai/skills/design-forms/SKILL.md) - Form builder patterns and field helpers
    - [design-layouts](../ai/skills/design-layouts/SKILL.md) - Page layouts, breakpoints, /me route patterns
    - [design-content](../ai/skills/design-content/SKILL.md) - Language rules, ADHD-friendly patterns,
      accessibility
- [UI Components API Reference](UI-COMPONENTS.md) - Complete helper method signatures and parameters
- [Form Helper Guide](form_helper.md) - Form builder API reference

**Sync Note:** The skill files under `ai/skills/` are the source of truth for rules (`.claude/skills` is a symlink to that
directory, so Claude Code reads the same files). When updating this guide, also update the corresponding skill files listed above, and vice versa. Each skill maps to
specific sections:

- **design-rules**: Rule Priority Guide, Development Workflow, Anti-Patterns, Quick Reference (Critical Rules)
- **design-foundations**: Foundation Layer, Theme System, Custom Utility Classes
- **design-components**: Component Library, Icon Usage
- **design-forms**: Form Patterns (entire section)
- **design-layouts**: Layout Patterns, Page Layouts, Responsive Breakpoints
- **design-content**: ADHD-Friendly Design Guidelines, Language & Content Guidelines

---

## Table of Contents

1. [Design Philosophy & Creative Direction](#design-philosophy--creative-direction)
    - [Interface Density & Scannability](#interface-density--scannability)
    - [Help Section & FAQ Pattern](#help-section--faq-pattern)
    - [Color Usage & Visual Restraint](#color-usage--visual-restraint)
2. [Development Workflow: Component & Styling Approval](#development-workflow-component--styling-approval)
    - [Hero Panel Stats Approval Workflow](#hero-panel-stats-approval-workflow)
    - [Hero Panel Description Rule](#hero-panel-description-rule)
    - [Styling Mechanism](#styling-mechanism)
3. [Foundation Layer](#foundation-layer)
4. [Theme System](#theme-system)
5. [Component Library](#component-library)
6. [Form Patterns](#form-patterns)
7. [Layout Patterns](#layout-patterns)
8. [Icon Usage](#icon-usage)
9. [ADHD-Friendly Design Guidelines](#adhd-friendly-design-guidelines)
10. [Language & Content Guidelines](#language--content-guidelines)
11. [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
12. [Quick Reference (LLM Cheat Sheet)](#quick-reference-llm-cheat-sheet)

---

## Rule Priority Guide

This document uses priority markers to indicate rule severity:

| Marker        | Meaning                                                                                 | Action                                        |
|---------------|-----------------------------------------------------------------------------------------|-----------------------------------------------|
| **CRITICAL**  | Must follow. Breaking this rule causes accessibility, usability, or consistency issues. | Never deviate without explicit user approval. |
| **PREFERRED** | Best practice. Follow unless there's a compelling reason not to.                        | Deviate only with good justification.         |
| **AVOID**     | Anti-pattern. Don't do this except in rare, documented exceptions.                      | Requires explicit justification if used.      |

---

## Design Philosophy & Creative Direction

This guide enables creation of distinctive, production-grade frontend interfaces that avoid generic "AI slop"
aesthetics. All implementations must deliver real working code with exceptional attention to aesthetic details and
creative choices.

### Design Thinking Process

Before coding any new interface or component, understand the context and commit to a **BOLD** aesthetic direction:

- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: The Clubhouse application serves Black Rock Rangers - a volunteer organization with a distinct culture. The
  aesthetic should feel: utilitarian yet warm, professional yet approachable, desert-inspired yet digital-native.
- **Constraints**: Technical requirements (Rails 8, Tailwind CSS, DaisyUI, Stimulus.js, accessibility, ADHD-friendly).
- **Differentiation**: What makes this UNFORGETTABLE? What's the one thing someone will remember?

**CRITICAL**: Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism
both work - the key is intentionality, not intensity.

### Implementation Complexity Matching

- **Maximalist designs**: Need elaborate code with extensive details and effects
- **Minimalist/refined designs**: Need restraint, precision, careful attention to spacing, typography, and subtle
  details
- Elegance comes from executing the vision well, not from complexity alone

### Interface Density & Scannability

**CRITICAL**: Interfaces must be as compact as possible while maintaining readability and pleasant aesthetics. Users are
terrible at scanning pages, and excessive scrolling reduces efficiency.

**Key Principles:**

- **Minimize vertical scrolling**: Consolidate information using appropriate spacing, avoid unnecessary whitespace
- **Optimize information density**: Present more information per screen without sacrificing readability
- **Maintain readability**: Compactness must never compromise text legibility or touch target sizes (36px minimum)
- **Pleasant aesthetics**: Dense layouts should still feel organized and visually appealing through proper hierarchy and
  grouping
- **Strategic whitespace**: Use whitespace purposefully for grouping and hierarchy, not decoration

**Scannability Enhancements:**

- **Visual hierarchy**: Use size, weight, and color to guide the eye to important information
- **Chunking**: Group related information in clearly defined sections
- **Consistent patterns**: Repeated layouts help users predict where to find information
- **Anchored help sections**: Link to FAQ/help sections from the top of pages (see Help Section Pattern below)

### Help Section & FAQ Pattern

**CRITICAL**: When pages include help sections, FAQs, or explanatory content positioned further down the page, they must
be clearly announced and linked at the top of the page.

This is the shape for a full page of instructions on a page the reader operates. A report or a log has no foot-of-page
help section: its explanations go in the one collapsed card under the stat row (see Hero Panel Description Rule).

**Implementation:**

```erb
<%# At top of page, after hero panel %>
<%= ui_callout_box :info, icon: "circle-info", icon_type: :solid do %>
Need help? View the <%= link_to "FAQ section", "#faq-section", class: "underline font-semibold" %> below.
<% end %>

<%# Later in the page %>
<%= ui_section "Frequently Asked Questions", id: "faq-section", icon: "circle-question", icon_type: :solid do %>
  <dl class="instruction-list">
<%# FAQ content %>
  </dl>
<% end %>
```

**Best Practices:**

- Use callout boxes or alert banners for help section announcements
- Include descriptive anchor text ("View FAQ section" not "Click here")
- Place links prominently before the main content begins
- Use consistent anchor IDs for help sections (`#faq-section`, `#help-section`, `#instructions`)

### Color Usage & Visual Restraint

**CRITICAL**: Interfaces must not be "busy" in a color sense. Limit color usage to prevent distracting users and
creating visual noise.

**Color Discipline:**

- **Semantic color only**: Use color to convey meaning (status, warnings, success), not decoration
- **Neutral dominance**: Most of the interface should use the warm-neutral paper surfaces (`base-100`
  through `base-300`). Light surfaces are warm (hue 80), dark surfaces are cool (hue 260), and text is warm in both
- **Brand accent sparingly**: **Signal Blue** — `--color-primary`, `oklch(0.52 0.2 262)` light /
  `oklch(0.68 0.19 262)` dark — for primary actions and key elements only. It is the *only* chromatic color
  permitted in ordinary chrome
- **Limit status colors**: Use success/warning/danger colors only where appropriate (alerts, status indicators, CTAs)
- **Avoid color variety**: Resist the temptation to use multiple colors for visual interest

**PREFERRED Color Allocation:**

| Element Type        | Color Strategy                                      | Example                                       |
|---------------------|-----------------------------------------------------|-----------------------------------------------|
| Body text           | Warm neutral ink                                    | `text-body`, `text-stone-emphasis`            |
| Backgrounds         | Warm paper surfaces                                 | `bg-base-100`, `bg-base-200`                  |
| Primary CTAs        | Brand color (Signal Blue)                           | `bg-primary` with `btn-primary`               |
| Status indicators   | Semantic (green/amber/red) only where status exists | `text-success`, `bg-warning/10`               |
| Decorative elements | **AVOID** colored decoration                        | No colored borders/backgrounds for aesthetics |
| Icons               | Neutral unless conveying status                     | `text-stone-muted` or status icon classes     |

**AVOID:**

- Colored backgrounds for visual variety (use cards/sections with neutral backgrounds)
- Colored text for emphasis (use weight and size instead: `font-semibold`, `text-lg`)
- Multiple accent colors competing for attention
- Colorful borders, gradients, or decorative elements without semantic purpose

**Where amber still appears:** amber is a *status* color (`warning`), not the brand. Three pieces of
non-semantic amber are left. The signature outline and the amber stat tile are theme tokens declared in
`app/assets/tailwind/application.css` -- `--color-signature-edge`, `--color-hero-tile`,
`--color-hero-tile-content` -- each carrying its own dark value, so `ring-signature-edge` needs no `dark:`
twin. The outline is worn by four things, only two of which are hero panels: `components/hero-panel.css`,
the hero stat tiles, the trophy badge in `common/_trophies.html.erb`, and the dashboard progress badge in
`ui_progress_box_helper.rb`. That badge's warm gradient is still raw palette on purpose, because turning it
into a theme-derived mix repaints it. Last is the sidebar's active-item marker, now the
`sidebar-active` token (`#ffc107`), kept as hex because its oklch does not round-trip bit-exactly. Treat all of it as documented legacy, not as a palette to extend.

---

## Development Workflow: Component & Styling Approval

**CRITICAL**: This section defines mandatory approval workflows for introducing new UI/UX components and color styling
that are not already documented in this design guide.

### New UI/UX Component Approval Process

**When approval is required:**

Any introduction of a new UI/UX component pattern that is not currently documented in this design guide requires
explicit user confirmation before implementation.

**Examples requiring approval:**

- New interaction patterns (accordions not in guide, carousels, slideovers, command palettes)
- New layout components (masonry grids, timeline views, kanban boards)
- New form controls not covered by `AppFormBuilder`
- New navigation patterns not covered by existing helpers
- New data visualization components (charts, graphs, diagrams)

**Approval workflow:**

1. **Identify the need**: Recognize that the component is not documented in the design guide
2. **Propose to user**: Explain why the new component is required for the specific use case
3. **Present alternatives**: Suggest alternative solutions using existing components if applicable
4. **Wait for approval**: Do not implement until user confirms or suggests alternative approach
5. **Implement as helper**: Once approved, create the component as a Ruby helper in `app/helpers/` or
   `app/helpers/ui_components/`
6. **Document in guide**: Update this design guide with:
    - Component description and purpose
    - When to use / when not to use
    - Code examples with ERB helper syntax
    - Accessibility considerations
    - Styling details (Tailwind classes, dark mode support)

**Example approval request:**

```
I need to display a timeline of volunteer events chronologically. The current design guide 
doesn't include a timeline component. I propose creating a vertical timeline component with:

- Icons for each event
- Connecting lines between events
- Timestamp and description for each entry

Alternatively, we could use the existing ui_section component with date headings, though 
this wouldn't show the visual connection between events.

Would you like me to proceed with the timeline component, or would you prefer the 
ui_section alternative?
```

### New Color Styling Approval Process

**When approval is required:**

Any introduction of new color styling that is not present in the semantic color tokens or documented custom utilities
requires explicit user confirmation before implementation.

**Examples requiring approval:**

- New semantic color tokens beyond those in the Foundation Layer
- New colored backgrounds not covered by existing tokens
- New border colors for specific purposes
- New status color variations
- New gradient combinations

**Approval workflow:**

1. **Identify the color need**: Determine that existing color tokens don't cover the use case
2. **Propose to user**: Explain why the new color styling is required
3. **Wait for approval**: Do not implement until user confirms
4. **DRY up with custom CSS**: Once approved, create a new CSS file in `app/assets/stylesheets/components/` for the
   component, or add to an existing component file if appropriate
5. **Document in guide**: Update this design guide with:
    - Custom utility class name and purpose
    - Use cases and when to apply
    - Tailwind composition (which utilities are combined)
    - Dark mode support
    - Code examples

**Implementation pattern:**

```css
/* In app/assets/stylesheets/components/[component-name].css */
@utility code-highlight-box {
    @apply bg-base-200 border-l-4 border-l-primary rounded-lg p-4;
}
```

Then add the import to `app/assets/stylesheets/utilities.css`:

```css
@import "./components/[component-name]";
```

**Example approval request:**

```
I need to highlight code snippets in the documentation section with a subtle tinted 
background. The theme has primary (Signal Blue), green (success), red (danger), amber 
(warning), and blue (info), but no neutral "reference material" highlight style. Blue is 
already spoken for twice over, so a code block tinted blue would read as a CTA or an alert.

I propose creating a `.code-highlight-box` utility with:
- base-200 background (bg-base-200)
- A left rule in the brand color (border-l-4 border-l-primary)
- Appropriate padding and rounded corners

This would be used specifically for code examples and technical documentation blocks.

May I proceed with this new styling?
```

**Note on existing color tokens:**

Before requesting approval, always verify that an existing semantic color token doesn't already solve the need. Review
the Foundation Layer > Color System section thoroughly.

### Hero Panel Stats Approval Workflow

**CRITICAL**: Do not place stats in the hero panel (`panel.hero_stats` / `panel.stat_badge`) unless the user has
approved a plan that specifies them there.

Hero stats compete with the page title for the reader's first fixation, and on mobile they stack beneath it and push
the content down. The default home for summary numbers is the **main body**, in a `ui_stat_row` above the content they
summarize:

```erb
<%= ui_stat_row do %>
  <%= ui_stat_box @report.trainee_count.to_s, "Trainees", variant: :warning %>
  <%= ui_stat_box @report.enrollment_count.to_s, "Sign-ups" %>
<% end %>
```

Only the /me dashboard welcome banner uses hero stats; put summary numbers in a body `ui_stat_row`. Reference
implementation: `app/views/training/multiple_enrollments/index.html.erb`.

### Hero Panel Description Rule

**CRITICAL**: `panel.description` is **one sentence** saying what the page does. Nothing else.

The hero is the page's first fixation and is size-constrained on mobile; a paragraph there pushes the actual content
below the fold. Background, caveats, eligibility rules, and especially step-by-step instructions go in the main
content: usually the collapsed card described next; a full page of instructions on a page the reader operates takes a
`ui_section` at the foot, announced from the top per the Help Section & FAQ Pattern. The Hero Panels component section
shows the correct/incorrect pair.

The usual home for a rule, legend or how-to that would have been the hero's second sentence is **one collapsed
`ui_disclosure … variant: :card` per page** holding an `instruction-list` — "About This Report" on a report or a log,
"How This Page Works" on a page the reader operates — under the stat row and above the filter bar, board or form
(directly under the hero where there is no stat row), never inside a `ui_section`. The page's controls decide the
label, not what its card holds: a control that changes a listed row, acts on a selection of them or adds to them
makes it a page the reader operates; filters, paging and export make it a report or a log, as do rows that open other
pages and one button that tidies the whole log (`design-rules` has the test). The card variant is required:
boxed, with a chevron, it reads as a control for the whole page, where the inline summary is a line of text with a
small triangle.

On a report or a log that card is the **only** home for an explanation. Counting rules, definitions, legends (samples
in the `<dd>`), how-tos and notes about one section (as a pair whose question names the section) all go in it, and no
Q&A list, explanatory paragraph or info callout of reference is left in the body. What stays visible is a message
rather than reference: a warning or an error, a privacy notice, a notice that appears only in one state of the data or
of the reader, a count, a caption on one figure, an empty state, a hint on one filter or form field (`help_text:`).
Folding never hides the page's subject: the year or period a report covers stays in the hero or the count line, and
how far back a log or a history goes is said again by its empty state. An icon whose only explanation is in the card
says its meaning itself: `fa_icon … label:` gives it a tooltip and a screen-reader sentence, and the legend's pair
carries the label's own words; a `title:` on a heading or a figure is said in the card too. On a page the reader
operates, a sentence joins a visible list, callout or section that fits, and a consequence of the page's action stays
visible as a callout beside the action. The Hero Panels component section has the snippet;
`test/views/hero_description_test.rb` guards the one-sentence rule.

### Styling Mechanism

**CRITICAL**: Prefer Tailwind and DaisyUI utility classes in markup. Write CSS only when utilities cannot express it.

- Custom CSS lives in `app/assets/stylesheets/components/<component>.css`, one component per file, imported from
  `components.css` or `utilities.css`
- Extract an `@utility` only when the same 3+ classes recur in 3+ places (see Custom Utility Classes)
- No inline `style=` attributes, no scoped or per-view CSS, no CSS outside `components/`
- A new component or colour treatment still needs approval first, whether built from utilities or a component file

---

## Foundation Layer

### Color System

**CRITICAL:** Always use semantic color tokens. Never use direct Tailwind color values (e.g., `text-gray-700`) when a
semantic token exists (e.g., `text-body`).

#### Semantic Text Colors

| Token              | Usage              | Light Mode       | Dark Mode         |
|--------------------|--------------------|------------------|-------------------|
| `text-body`        | Primary body text  | Stone/gray tones | Light gray tones  |
| `text-heading`     | Headings, emphasis | Darker stone     | White/light stone |
| `text-stone-emphasis` | Emphasised body text | Stone-700     | Stone-300         |
| `text-stone-muted` | Muted/secondary text | Stone-600      | Stone-400         |
| `text-stone-subtle` | Subtle / disabled-looking text | Stone-500 | Stone-400   |
| `text-primary`     | Brand-colored text (Signal Blue) | `--color-primary` | `--color-primary` |
| `text-success`     | Success emphasis   | `--color-success` | `--color-success` |
| `text-warning`     | Warning emphasis   | `--color-warning` | `--color-warning` |
| `text-error`       | Danger emphasis    | `--color-error`  | `--color-error`   |

#### Semantic Background Colors

| Token           | Usage                           | Light Mode        | Dark Mode         |
|-----------------|---------------------------------|-------------------|-------------------|
| `bg-base-100`   | Primary card and panel surfaces | Warm off-white    | Deep neutral      |
| `bg-base-200`   | Secondary/selected surfaces     | Light neutral     | Raised neutral    |
| `bg-base-300`   | Form fills and progress tracks  | Mid neutral       | Strong neutral    |
| `bg-primary`    | Brand emphasis and CTAs         | Brand tone        | Brand tone        |
| `bg-primary/10` | Soft brand emphasis             | Subtle brand tint | Subtle brand tint |
| `bg-success`    | Success state                   | Green             | Green             |
| `bg-success/10` | Soft success surfaces           | Pale green tint   | Dark green tint   |
| `bg-warning`    | Warning state                   | Amber             | Amber             |
| `bg-warning/10` | Soft warning surfaces           | Pale amber tint   | Dark amber tint   |
| `bg-error`      | Danger state                    | Red               | Red               |
| `bg-error/10`   | Soft danger surfaces            | Pale red tint     | Dark red tint     |

#### Border Colors

| Token               | Usage                   |
|---------------------|-------------------------|
| `border-line`    | Standard borders        |
| `border-base-300`   | Medium emphasis borders |
| `border-primary/30` | Subtle brand borders    |
| `border-success/30` | Success borders         |
| `border-warning/30` | Warning borders         |
| `border-error/30`   | Danger borders          |

### Typography

#### Font Families

Both faces are self-hosted from `app/assets/webfonts/` and declared in
`app/assets/stylesheets/fonts.css`. Nothing is fetched from Google Fonts.

```css
--font-sans: "Atkinson Hyperlegible", system-ui, -apple-system, "Segoe UI", Roboto,
             "Helvetica Neue", "Noto Sans", "Liberation Sans", Arial, sans-serif;
--font-mono: "Atkinson Hyperlegible Mono", ui-monospace, "SFMono-Regular", "Menlo",
             "Monaco", "Consolas", "Liberation Mono", "Courier New", monospace;
```

**Fonts in Use:**

- **Default**: Atkinson Hyperlegible — the proportional cut. Every heading, label, table
  cell, and paragraph in the app. This is what `font-sans` and the unstyled default give you.
- **Monospaced**: Atkinson Hyperlegible Mono — the monospaced cut of the same design, applied
  with `font-mono`. Use it only where character cells have to line up or a value is meant to
  be read as a literal string: `<code>`, document tags, client IDs, license plates, log
  output, and format examples. Do not set prose, headings, or ordinary table text in it.

Both are variable fonts spanning weights 200–800 with italics, so any `font-*` weight
utility renders a real cut rather than a synthesized one.

**CRITICAL:** Do not introduce any new fonts. Atkinson Hyperlegible and its mono cut are
the whole system — see "The One Typeface Rule" in `DESIGN.md`.

**Numeric alignment:** the proportional cut uses natural figure widths. Tables apply
`font-variant-numeric: tabular-nums` globally so numeric columns still line up; anywhere
else digits stack vertically, add the `tabular-nums` utility. This is the replacement for
setting numbers in the mono face.

#### Type Scale

**CRITICAL:** Default to `text-base` for body content. Never use smaller sizes for primary content.

The theme sets `text-base` to **0.9rem on a 1.2 line-height** (`--text-base` and `--text-base--line-height` in
`app/assets/tailwind/application.css`) — DESIGN.md's Tight Leading Rule. Do not "fix" this to 16px or 1.5; buy row
spacing with padding, not leading.

| Class       | Size     | Usage                                           |
|-------------|----------|-------------------------------------------------|
| `text-xs`   | 0.75rem  | **Restricted use** - see below                  |
| `text-sm`   | 0.875rem | **Restricted use** - see below                  |
| `text-base` | 0.9rem   | Body text, form labels, table content (default) |
| `text-lg`   | 1.1rem   | Section titles at `lg` and up, form legends     |
| `text-xl`   | 1.25rem  | Card titles, `hero_panel` `:h2` titles          |
| `text-2xl`  | 1.5rem   | Page titles (`hero_panel` `:h1`)                |
| `text-3xl`  | 1.875rem | Legacy `page_title` helper only                 |
| `text-4xl+` | 2.25rem+ | Hero text                                       |

#### When to Use `text-xs`

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

#### When to Use `text-sm`

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

#### Font Weights

| Class           | Weight | Usage                   |
|-----------------|--------|-------------------------|
| `font-normal`   | 400    | Body text               |
| `font-medium`   | 500    | Labels, slight emphasis |
| `font-semibold` | 600    | Headings, buttons       |
| `font-bold`     | 700    | Strong emphasis         |

#### Heading Levels

One style per level, one utility each (`components/headings.css`): `<h2>` takes `heading-section`
(`text-base lg:text-lg font-semibold`, the `ui_section` title's); `<h3>` and `<h4>` take
`heading-title` (`text-base font-semibold`). Nothing inside a section outweighs its title.
The full rule and its exemptions are in `design-foundations` > Heading Levels.

### Spacing

Follow Tailwind spacing conventions consistently:

| Scale | Value   | Common Usage                   |
|-------|---------|--------------------------------|
| `2`   | 0.5rem  | Tight spacing, inline elements |
| `3`   | 0.75rem | Button padding, small gaps     |
| `4`   | 1rem    | Standard padding, form gaps    |
| `6`   | 1.5rem  | Section spacing                |
| `8`   | 2rem    | Large section spacing          |

**Common patterns:**

- Card padding: `p-4` or `p-2 lg:p-4`
- Section margin: `mb-4`
- Button row gaps: `gap-2` or `gap-4`
- Form field spacing: `mb-3` (the builder's wrapper)

### Touch Targets

**The floor is 36px — `min-h-9`.** `design-foundations` holds the canonical statement; this is the summary.

- A `btn-sm` (so every `ButtonHelper` control) and a `select-sm` are already 36px — `accessibility.css` floors them.
  `min-h-9` is for what nothing floors: a `<label>`, a hand-written `<summary>` (`ui_disclosure` and `ui_accordion`
  floor their own), a bare link. Never `min-h-[36px]`, `min-h-11`, or a raw `min-height`
- An icon-only `ButtonHelper` button takes `btn-square`, which makes it 36px wide as well. Not `min-w-9`: the side
  padding already makes it 41px, so that floor never applies. `min-w-9` is for what nothing floors: a `<label>`, a bare
  span or slot
- Put the class on the element that receives the tap: for a checkbox or radio, the wrapping `<label>`
- `LinkHelper::TABLE_LINK_CLASSES` (dense table rows) is the one standing exception; comment any other
- 36px clears WCAG 2.5.8 Target Size (AA, 24px). It does not meet 2.5.5 (AAA, 44px) — a deliberate trade for density

### Border Radius

| Class          | Value   | Usage                       |
|----------------|---------|-----------------------------|
| `rounded-base` | 12px    | Buttons, inputs             |
| `rounded-lg`   | 16px    | Modals, panels not cards    |
| `rounded-xl`   | 12px    | Alias of `rounded-base`     |
| `rounded-2xl`  | 16px    | Alias of `rounded-lg`       |
| `rounded-full` | 9999px  | Badges, avatars, pills      |

### Shadows

| Class       | Usage                   |
|-------------|-------------------------|
| `shadow-xs` | Cards, subtle elevation |
| `shadow-sm` | Buttons, dropdowns      |
| `shadow-md` | Modals, overlays        |
| `shadow-lg` | Popovers, menus         |
| `shadow-xl` | Prominent overlays      |

**Custom shadow (hero panels):**

```css
shadow-[0px_0px_6px_4px_rgba(0,0,0,0.1)]
```

**Flat by default** (DESIGN.md): a new component gets no shadow. Region lift belongs to `.box` and the hero panel;
hover is a colour change, never a lift.

### Custom Utility Classes

The project defines custom `@utility` directives in organized CSS files within `app/assets/stylesheets/components/` for
frequently used pattern combinations:

#### Status Icon Colors

```erb
<%# Consistent icon colors for status states %>
<%= fa_icon "circle-check", :solid, class: "icon-success" %>
<%= fa_icon "circle-exclamation", :solid, class: "icon-warning" %>
<%= fa_icon "triangle-exclamation", :solid, class: "icon-error" %>
<%= fa_icon "circle-info", :solid, class: "icon-info" %>
```

**Maps to:**

- `icon-success` → `text-success`
- `icon-warning` → `text-warning`
- `icon-error` → `text-error`
- `icon-info` → `text-info`

Those four are the only `icon-*` utilities that exist (see
`app/assets/stylesheets/components/icons.css`). For a brand or neutral icon use
`text-primary` or `text-stone-icon` directly.

#### Common Flex Patterns

```erb
<%# Frequently used flexbox combinations %>
<div class="flex-center">Content</div>
<div class="flex-center-gap-2">Icon and text</div>
<div class="inline-flex-center-gap-2">Badge content</div>
```

**Maps to:**

- `flex-center` → `flex items-center`
- `flex-center-gap-2` → `flex items-center gap-2`
- `inline-flex-center` → `inline-flex items-center`
- `inline-flex-center-gap-2` → `inline-flex items-center gap-2`

#### Instruction Lists (ADHD-Friendly)

```erb
<%# Q&A style content with proper hierarchy %>
<dl class="instruction-list">
  <dt>Question or topic?</dt>
  <dd>Clear, concise answer.</dd>

  <dt>Next question?</dt>
  <dd>Another answer.</dd>
</dl>
```

**Write no classes on the `<dt>` or `<dd>`.** The spacing is the class's job:
4px between a question and its answer, 8px before the next question. Every one
of 111 views used to spell that second gap as `<dt class="mt-2">` and not one
of them ever rendered, because `space-y-1` sets `margin-block-start: 0` from
unlayered CSS, which beats a `mt-2` utility whatever its specificity.

**Styling** (`accessibility.css`):

- `<dl>`: `space-y-1 text-body`
- `<dt>`: `font-bold text-heading relative ps-5`, with a `Q:` prefix in `text-primary`
- `<dd>`: `text-body relative ps-5`, with an `A:` prefix in `text-stone-muted`
- `dd + dt`: `margin-block-start: calc(var(--spacing) * 2)`

**The prefixes are `::before` pseudo-elements, and they are decoration.** They are written
`content: "Q:" / ""` — the alt-text form, which draws the glyphs and hands assistive tech an
empty string. A `<dl>` already tells a screen reader which part is the question; a plain
`content: "Q:"` would make it announce that same fact a second time on every pair. Each one is
preceded by an unsuffixed `content` declaration as a fallback for anything that cannot parse the
alt form — that loses the suppression, not the prefix.

The `ps-5` gutter is what the prefix sits in, via `position: absolute; inset-inline-start: 0`.
Logical properties throughout, so the gutter follows the writing mode.

Inside a warning box the prefixes inherit the box's colour like everything else in it — see the
`.box-warning` rule in `components/boxes.css`, which has to name the pseudo-elements explicitly
because `*` does not match them.

**Purpose:** Provides clear visual hierarchy for instructional or informational content in a scannable Q&A format,
optimized for users with ADHD or those who prefer structured information presentation. The prefixes make it
immediately obvious which text is the question and which is the answer.

#### Card Patterns

There is one card utility, and `ui_card` renders it, so markup and the helper name the same thing:

```erb
<div class="card-standard p-4">Standard card</div>
```

**Maps to** (`components/cards.css`): `card bg-base-100 border border-line` — a 12px radius
(`--radius-box`) and a flex column, both from daisyUI's `card`.

Not `card-border`: it resolves to base-200, which against a base-100 card is invisible in light
mode, so a card's edge is `border-line` like every other container. No shadow, per DESIGN.md's
flat-by-default rule; a card that genuinely needs one adds `shadow-xs` at the call site. No
padding either — the call site keeps its own `p-*`. A card on another surface overrides the
background at the call site (`card-standard bg-base-200`), which works because Tailwind emits its
utilities after the component block.

#### Progress Bar Gradients

**Purpose:** Brand-themed gradient styling for progress bars and progress-related components.

**Progress Bar Fill:** (from `.progress-bar` in `app/assets/stylesheets/components/progress.css`)

```css
bg-linear-to-r from-primary to-warning
```

The gradient runs brand → warning, so it needs no `dark:` variant: both ends are semantic tokens that
re-resolve per theme.

**Progress Bar Pulse Effect (for incomplete progress):**

```css
bg-linear-to-r from-primary/50 to-warning/50 rounded-full animate-pulse
```

**Progress Icon Badge Background:** (`ICON_BADGE_BASE` in `ui_progress_box_helper.rb`)

```css
bg-linear-to-br from-amber-100 to-orange-100 dark:from-amber-900/40 dark:to-orange-900/40
```

This badge pairs with `icon-warning`, so its amber is the warning hue, not the brand. It is one of the few
raw-Tailwind color runs left in the system — don't copy the pattern into new components.

**Usage:**

- Used exclusively in progress components (`ui_progress_bar`, `ui_progress_box`, `hero_panel`)
- Provides visual consistency for progress indication across dashboard widgets
- Gradients have semantic purpose (progress visualization) and are not decorative

**When to use:**

- Progress bars showing completion percentage
- Icon badges in progress box components
- Hero panel progress indicators

**AVOID:**

- Using these gradients outside of progress-related components
- Applying to buttons, cards, or other non-progress elements

#### Search Hit

**Purpose:** marks what a search matched inside a result. One use so far: the mailbox's hits
(`MessagesHelper#message_search_marks`, `<mark class="search-hit">` around each matched word in a
hit's subject and snippet), and the cards of the thread a hit opens (`#message_body_marks`), where
the card the hit lands on is also ringed in the review pane's selection colour and brought into
view: its `data-landing` attribute switches on `data-landing:ring-2 data-landing:ring-primary
data-landing:scroll-mt-18 data-landing:scroll-mb-4` (the top margin clears the Match Stepper), which
every card carries, so the read-state morphs that redraw a card
with no search leave the ring where it was. Owner-approved 2026-10-18; the cards and the ring
2026-10-29, as design B of `.scratch/messages-search/PRD.md`.

```css
@utility search-hit { @apply bg-warning/30 text-inherit rounded-sm; }  /* components/messages.css */
```

Amber because unread is already warning vocabulary in the mailbox; 30% so it still reads on an
unread row (`bg-warning/10`) and on the selected row's primary tint. The text keeps the colour of
the line it sits in, so contrast is the line's own. It needs no `dark:` variant: the token
re-resolves per theme. A bare `<mark>` shows nothing — `components/lexxy.css` takes the browser's
highlighter off every one — so a mark always carries the class.

#### DaisyUI Component Utilities

Custom utility classes that provide semantic aliases for DaisyUI-inspired component patterns. These utilities abstract
away the raw Tailwind classes, making code more readable and maintainable.

##### Modal Utilities

```erb
<%# DaisyUI modal structure %>
<dialog class="modal modal-middle" open>
  <div class="modal-box">
    <h3 class="text-lg font-semibold">Title</h3>
    <div class="py-4">Content</div>
    <div class="modal-action">
      <button class="btn btn-secondary">Close</button>
      <button class="btn btn-primary">Confirm</button>
    </div>
  </div>
</dialog>
```

| Selector         | Description                                     |
|------------------|-------------------------------------------------|
| `dialog.modal`   | Outer dialog container and placement            |
| `.modal-box`     | Inner dialog surface with spacing and max width |
| `.modal-action`  | Action row aligned to the dialog footer         |
| `.modal-backdrop`| Optional click-outside close layer              |

##### Tab Navigation Utilities

```erb
<%# DaisyUI tab structure %>
<div class="tabs tabs-border" role="tablist" aria-label="Example tabs">
  <button class="tab tab-active" role="tab" aria-selected="true">Active Tab</button>
  <button class="tab" role="tab" aria-selected="false">Inactive Tab</button>
</div>
<div class="mt-4">Panel content</div>
```

| Selector            | Description                                 |
|---------------------|---------------------------------------------|
| `.tabs.tabs-border` | Tab row container with DaisyUI border style |
| `.tab`              | Base tab button styling                     |
| `.tab-active`       | Selected tab state                          |

##### Dropdown Menu Utilities

```erb
<%# DaisyUI dropdown structure %>
<div class="dropdown">
  <button class="btn btn-ghost" tabindex="0" role="button">Menu</button>
  <ul tabindex="0" class="menu dropdown-content bg-base-100 rounded-box z-1 w-52 p-2 shadow-sm">
    <li><a>Item 1</a></li>
    <li><a>Item 2</a></li>
    <li class="menu-disabled"><a>Disabled</a></li>
  </ul>
</div>
```

| Selector            | Description                 |
|---------------------|-----------------------------|
| `.dropdown`         | Positioning wrapper         |
| `.dropdown-content` | Positioned dropdown surface |
| `.menu`             | List styling for items      |
| `.menu-disabled`    | Disabled item appearance    |

##### Toast Notification Utilities

```erb
<%# Toast structure %>
<div class="toast-base toast-success">Success message</div>
<div class="toast-base toast-warning">Warning message</div>
<div class="toast-base toast-error">Error message</div>
<div class="toast-base toast-info">Info message</div>
```

| Utility         | Description                                     |
|-----------------|-------------------------------------------------|
| `toast-base`    | Base container (flex, padding, rounded, shadow) |
| `toast-success` | Green success colors                            |
| `toast-info`    | Blue info colors                                |
| `toast-warning` | Yellow/amber warning colors                     |
| `toast-error`   | Red error colors                                |

##### Badge Utilities

Badges are daisyUI classes, emitted by `BadgeHelper#ui_badge` as `badge badge-<variant> badge-soft text-<size>`.
There is no custom `badge-base`; `components/badges.css` only patches dark-theme contrast for the soft secondary and
error variants.

| Class             | Description                                     |
|-------------------|-------------------------------------------------|
| `badge`           | daisyUI base (padding, pill radius)             |
| `badge-soft`      | Tinted fill, applied to every variant           |
| `badge-primary`   | Signal Blue                                     |
| `badge-secondary` | Neutral gray                                    |
| `badge-success`   | Green                                           |
| `badge-warning`   | Amber                                           |
| `badge-error`     | Red                                             |

##### Sidebar/Drawer Utilities

```erb
<%# Sidebar structure %>
<div class="sidebar-backdrop"></div>
<aside class="sidebar-drawer">
  <button class="sidebar-close-btn">×</button>
  <h6 class="sidebar-section-header">Section</h6>
  <a class="sidebar-nav-item">Link</a>
  <span class="sidebar-badge">5</span>
</aside>
```

| Utility                  | Description                               |
|--------------------------|-------------------------------------------|
| `sidebar-backdrop`       | Semi-transparent overlay                  |
| `sidebar-drawer`         | Main drawer container (fixed, transition) |
| `sidebar-close-btn`      | Mobile close button                       |
| `sidebar-nav-item`       | Navigation link item                      |
| `sidebar-section-header` | Section title styling                     |
| `sidebar-badge`          | Notification count badge                  |

**PREFERRED:** Use these utility classes through helpers (`ModalHelper`, `NavigationHelper`, etc.) or DaisyUI-native
markup patterns rather than ad-hoc custom wrappers. Helpers ensure accessibility and consistency.

#### Button Classes

Buttons are daisyUI: `btn` plus a variant (`btn-primary`, `btn-secondary btn-outline`, `btn-ghost`, `btn-success`,
`btn-error`, `btn-warning`, `btn-neutral`, `btn-disabled`) plus a size (`btn-xs` … `btn-xl`), emitted by
`ButtonHelper`. There is no custom `btn-base`; `components/buttons.css` holds the `.button-row` rules and theme patches,
not a button base class.

**PREFERRED:** Use `ButtonHelper` methods (`button_link`, `button_action`, `submit_button`, etc.) instead of these
classes directly.

#### Neutral Text Color System

Text that is neither a heading nor a status. Every step derives from the theme's own ink
(`--color-base-content`) and paper (`--color-base-100`), so a theme change moves all of them and
none carries a `dark:` variant: in light the ink is dark and the paper light, in dark the reverse,
so "mix toward the paper" means "less contrast" in both themes by itself.

The steps live in `app/assets/stylesheets/components/text-colors.css`; the tokens they point at
live in `app/assets/tailwind/application.css`. Change a value in one of those two places, never at
a call site.

**Hierarchy, strongest ink first.** `L` is OKLCH lightness, light theme / dark theme. Contrast is
measured against `base-300`, the row-hover fill, because a neutral line inside a hovered table row
is the case that fails first.

| Utility                                                     | Resolves to                | L light / dark | Contrast on base-300 |
|-------------------------------------------------------------|----------------------------|----------------|----------------------|
| `text-heading`, `text-heading-primary`                        | `--color-heading`          | 30 / 85        | 10.8:1 / 9.2:1       |
| `text-body`, `text-stone-emphasis`                            | `--color-body`             | 40 / 75        | 7.3:1 / 6.6:1        |
| `text-stone-muted`                                            | 90% ink toward paper       | 45.75 / 69.3   | 5.7:1 / 5.3:1        |
| `text-body-subtle`, `text-stone-subtle`, `text-stone-icon`    | `--color-body-subtle`      | 50 / 66        | 4.8:1 / 4.7:1        |

```erb
<h2 class="text-heading">Section Heading</h2>
<p class="text-body">Body copy</p>
<span class="text-stone-muted">Secondary information</span>
<small class="text-stone-subtle">Fine print, labels</small>
<%= fa_icon "icon", :solid, class: "text-stone-icon" %>
```

**When to Use Each:**

| Utility                | Use Case                                       | Example                        |
|------------------------|------------------------------------------------|--------------------------------|
| `text-heading-primary` | Page titles, major headings, critical emphasis | Section titles, modal titles   |
| `text-heading`         | Standard headings, card titles                 | Agreement titles, team names   |
| `text-stone-emphasis`  | Emphasized body text, important info           | Shift descriptions, notices    |
| `text-stone-muted`     | Secondary information, helper text             | Timestamps, metadata           |
| `text-stone-subtle`    | Labels, fine print, less important text        | Form labels, "Required" labels |
| `text-stone-icon`      | Icons, placeholders, disabled states           | Status icons, separators       |

**Guidelines:**

- **PREFERRED:** Use semantic tokens (`text-heading`, `text-body`) first
- **PREFERRED:** Drop to `text-stone-muted` or `text-stone-subtle` only for a genuine secondary
  line. The `text-stone-*` names are historical -- nothing about them is stone any more
- **CRITICAL:** Be consistent - use the same utility for the same purpose across pages
- **AVOID:** Naming a palette colour (`text-stone-600`) at a call site. It cannot be re-themed,
  which is exactly why these utilities stopped doing it

---

## Theme System

### Dark Mode Implementation

The application uses class-based dark mode. The `.dark` class is toggled on the `<html>` element.

**Theme Controller**: `app/javascript/controllers/theme_controller.js`

```javascript
// Theme detection priority:
// 1. localStorage saved preference
// 2. System preference (prefers-color-scheme)
// 3. Default to light mode
```

**Key behaviors:**

- Theme persists in `localStorage` as `'theme'`
- System preference detected via `matchMedia('(prefers-color-scheme: dark)')`
- Toggle button shows sun icon in dark mode, moon icon in light mode

### Dark Mode Color Patterns

**CRITICAL:** Every user-facing element must render correctly in dark mode. Semantic tokens do this for free — they
re-resolve per theme — so most markup needs no `dark:` variant at all. Raw Tailwind colours (`bg-white dark:bg-gray-800`)
are banned (AGENTS.md > Hard Rules); a `dark:` pair is only for the rare raw value inside a component CSS file.

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

Verify by toggling **both** `data-theme="dark"` and the `.dark` class on `<html>` — the app keys its `dark` variant on
the class, so flipping only one gives a false reading.

### Theme-Specific Styling Examples

**Hero Panel (from `app/assets/stylesheets/components/hero-panel.css`):**

```css
.me-hero-panel {
    @apply shadow-[0px_0px_6px_4px_rgba(0,0,0,0.1)] block rounded mb-4;
    @apply relative rounded-lg bg-base-200 dark:bg-base-300
    ring-1 ring-signature-edge px-4 py-2;
}
```

The amber ring is the one piece of raw palette left here, and it stays: it is documented legacy
rather than a palette to extend. The surface under it is base-200/base-300 so it follows the theme.

**Muted text helper:**

```css
.me-muted {
    @apply text-stone-muted;
}
```

---

## Component Library

### Buttons

**Helper**: `ButtonHelper` (`app/helpers/button_helper.rb`)

**CRITICAL:** Always use `ButtonHelper` methods for buttons. Never write raw button HTML.

Buttons are daisyUI `btn` components. `ButtonHelper` emits `btn` + a variant class + a size class; there is no custom
base class.

#### Button CSS Architecture

Buttons are composed of three class types:

1. **Base class** (`btn`) - daisyUI core styling
2. **Variant class** (`btn-primary`, `btn-secondary btn-outline`, etc.) - Colors and borders
3. **Size class** (`btn-xs`, `btn-sm`, `btn-md`, `btn-lg`, `btn-xl`) - Padding and text size

Example output: `class="btn btn-primary btn-sm"` for a default primary button.

#### Button Variants

| Variant      | Usage                                     |
|--------------|-------------------------------------------|
| `:primary`   | Primary actions                           |
| `:secondary` | Secondary actions                         |
| `:tertiary`  | Alias of `:ghost` (legacy)                |
| `:success`   | Positive actions                          |
| `:error`     | Destructive actions                       |
| `:warning`   | Warning actions                           |
| `:dark`      | `btn-neutral` — dark-chrome contexts only |
| `:ghost`     | Minimal buttons                           |

**Styling Details:**

Variants are daisyUI `btn-*` classes, emitted by `ButtonHelper::VARIANT_CLASSES`
(`app/helpers/button_helper.rb`). Colour, hover and focus ring all come from the
daisyUI component — do not hand-apply `bg-*`/`ring-*` utilities to a button.

| Variant (symbol) | Emitted class            |
|------------------|--------------------------|
| `:primary`       | `btn-primary`            |
| `:secondary`     | `btn-secondary btn-outline` |
| `:tertiary`      | `btn-ghost`              |
| `:success`       | `btn-success`            |
| `:error`         | `btn-error`              |
| `:warning`       | `btn-warning`            |
| `:dark`          | `btn-neutral`            |
| `:ghost`         | `btn-ghost`              |
| disabled         | `btn-disabled`           |

#### Button Methods

```erb
<%# Generic button with Stimulus action %>
<%= button_action "Label", :primary, data: { action: "controller#method" } %>

<%# Link styled as button %>
<%= button_link "Label", :variant, url, options %>

<%# Common shortcuts %>
<%= submit_button "Save" %>
<%= cancel_button url %>    <%# or cancel_link (alias) %>
<%= edit_link url %>        <%# the one edit control: secondary + pen-to-square %>
<%= delete_button url %>    <%# includes confirmation %>

<%# Button row container %>
<%= button_row do %>
<%= submit_button "Save" %>
<%= cancel_button some_path %>
<% end %>

<%# Sticky button row (sticks to bottom on mobile) %>
<%= button_row do %>
<%= submit_button "Save" %>
<%= cancel_button some_path %>
<% end %>
```

#### Button Sizes

Buttons support size variants that adjust padding and text size proportionally. **Default size is `sm` (text-sm).**

| Size   | CSS Utility | Padding         | Text Size           |
|--------|-------------|-----------------|---------------------|
| `xs`   | `btn-xs`    | `px-2.5 py-1.5` | `text-xs`           |
| `sm`   | `btn-sm`    | `px-3 py-2`     | `text-sm` (default) |
| `base` | `btn-md`    | `px-4 py-2.5`   | `text-base`         |
| `lg`   | `btn-lg`    | `px-5 py-3`     | `text-lg`           |
| `xl`   | `btn-xl`    | `px-6 py-3.5`   | `text-xl`           |

**CRITICAL: Button Minimum Size Policy**

Buttons should **never be smaller than `text-sm`**. The `xs` size exists for exceptional cases only.

**AVOID** `xs` button size except for:

- Icon-only action buttons in dense table rows (e.g., edit/delete icons)
- Compact navigation elements in sidebars or toolbars
- Secondary actions in very constrained spaces (e.g., inline message actions)
- Developer/debug buttons not shown in production

**CRITICAL - Never use `xs` button size for:**

- Primary call-to-action buttons
- Form submit buttons
- Any button with user-facing text that users need to read
- Navigation buttons
- Action buttons in cards or sections

```erb
<%# Size options: xs, sm (default), base, lg, xl %>
<%# Omit size parameter to use the default (sm) %>
<%= button_link "Standard Button", :primary, url %>
<%= button_link "Large", :primary, url, size: "lg" %>

<%# With icon %>
<%= button_link "Edit", :primary, url, icon: "pen", icon_type: :solid %>

<%# Disabled state - adds btn-disabled class %>
<%= button_link "Disabled", :primary, url, disabled: true %>

<%# Full width responsive button %>
<%= button_link "Submit", :primary, url, class: "w-full lg:w-auto" %>
```

### Cards

**Helper**: `UiCardHelper` (`app/helpers/ui_components/ui_card_helper.rb`)

```erb
<%= ui_card do %>
<%= ui_card_title "Card Title", size: :lg %>
<%= ui_card_body do %>
    Card content goes here.
  <% end %>
  <%= ui_card_section "Section Title" do %>
    Section content.
<% end %>
<%= ui_card_footer do %>
<%= button_link "Action", :primary, url %>
<% end %>
<% end %>
```

**Options:**

- `shadow:` - Shadow size (`:xs`, `:sm`, `:md`, `:lg`, `:xl`, `:none`)
- `width:` / `height:` - Custom dimensions in pixels

### Accent Cards

**Helper**: `UiAccentCardHelper` (`app/helpers/ui_components/ui_accent_card_helper.rb`)

Accent cards feature a prominent left border for visual hierarchy. Used for dashboard tasks, qualifications, schedule
items, and other status-driven content.

```erb
<%# Basic usage %>
<%= ui_accent_card "Task Title", variant: :success do %>
Task content here.
<% end %>

<%# With icon %>
<%= ui_accent_card "Complete Training", 
    variant: :warning, 
    icon: "graduation-cap", 
    icon_type: :solid do %>
Training details and requirements.
<% end %>

<%# With badge %>
<%= ui_accent_card "Profile Setup", 
    variant: :error, 
    icon: "user", 
    icon_type: :solid,
    badge: ui_badge("urgent", :error) do %>
Please complete your profile information.
<% end %>

<%# With all options %>
<%= ui_accent_card "Shift Signup", 
    variant: :info, 
    icon: "calendar", 
    icon_type: :solid,
    badge: ui_badge("optional", :secondary),
    options: { id: "shift-123", class: "mb-4" } do %>
Shift details and signup button.
<% end %>
```

**Variants:**

- `:success` - Green border and background (completed, earned)
- `:warning` - Amber border and background (action needed, pending)
- `:error` - Red border and background (urgent, blocked)
- `:info` - Info-blue border and background (optional steps, notes, explanations, help)
- `:primary` - Brand border and background in Signal Blue (the next step, a call to action)
- `:secondary` - Neutral border and background (no status to signal)

**Options:**

- `variant:` - Color variant (default: `:primary`)
- `icon:` - FontAwesome icon name (optional)
- `icon_type:` - Icon style (`:solid`, `:regular`) - default `:solid`
- `badge:` - Badge HTML to display (optional)
- `heading_level:` - `:h2`, `:h3` or `:h4` (default: `nil`, a div). Renders the title as that heading
  with the same look; any other value raises `ArgumentError`
- `options:` - Hash of HTML options
    - `:id` - HTML id attribute
    - `:class` - Additional CSS classes
    - `:aria` - ARIA attributes hash
    - `:data` - Data attributes hash

**Headings:** a title that labels the card's content is a heading, so a screen reader can move
from card to card. Give it the level one below the nearest heading above the card: `:h3` for a
dashboard step under its group's `<h2>` or for a card inside a `ui_section`, `:h2` for a card at
page level. A notice, tip or banner keeps the default div.

```erb
<%= ui_accent_card step.title, variant: :warning, heading_level: :h3 do %>
Step details.
<% end %>
```

**When to use:**

- Dashboard task cards with status indicators
- Qualification progress displays
- Schedule item cards with visual priority
- Any content requiring left-border accent for visual hierarchy

### Stat Boxes

**Helper**: `UiStatBoxHelper` (`app/helpers/ui_components/ui_stat_box_helper.rb`)

Stat boxes display metrics with icon, value, and label. Used for dashboard statistics, summary metrics, and key
performance indicators.

```erb
<%# Basic usage %>
<%= ui_stat_box "95%", "Complete", variant: :success %>

<%# With icon %>
<%= ui_stat_box "12.5", "Credits Earned", 
    variant: :success, 
    icon: "circle-check", 
    icon_type: :solid %>

<%# Different sizes %>
<%= ui_stat_box "8", "Shifts", variant: :secondary, size: :sm %>
<%= ui_stat_box "24h", "Hours", variant: :secondary, size: :md %>
<%= ui_stat_box "100%", "Done", variant: :success, size: :lg %>

<%# Summary row -- always ui_stat_row, never a hand-rolled div or grid %>
<%= ui_stat_row do %>
  <%= ui_stat_box credit_format(@earned), "Earned",
      variant: :success, icon: "circle-check", icon_type: :solid %>
  <%= ui_stat_box hour_format(@scheduled), "Scheduled",
      variant: :secondary, icon: "clock", icon_type: :solid %>
  <%= ui_stat_box credit_format(@potential), "Potential",
      variant: :secondary, icon: "star", icon_type: :solid %>
<% end %>
```

**Variants:**

- `:success` - Green background with green text
- `:warning` - Amber background with amber text
- `:error` - Red background with red text
- `:secondary` - Neutral background with heading text (default)

**Sizes:**

- `:sm` - Small (text-lg value, text-xs label)
- `:md` - Medium (text-xl value, text-sm label) - default
- `:lg` - Large (text-2xl value, text-base label)

**Options:**

- `variant:` - Color variant (default: `:secondary`)
- `icon:` - FontAwesome icon name (optional)
- `icon_type:` - Icon style (`:solid`, `:regular`) - default `:solid`
- `size:` - Size variant (`:sm`, `:md`, `:lg`) - default `:md`
- `class:` - Additional CSS classes
- `aria:` - ARIA attributes hash

**When to use:**

- Dashboard statistics displays
- Summary metric grids
- Progress tracking (credits, hours, shifts)
- Key performance indicators

### Stat Row

**Helper**: `UiStatRowHelper` (`app/helpers/ui_components/ui_stat_row_helper.rb`)

`ui_stat_row` is the only container for a page's summary tiles: a wrapping flex row that tightens its gap below `lg`.
Never hand-roll the wrapper; a grid of stat boxes is a different pattern and needs approval. Full API:
`docs/UI-COMPONENTS.md`.

### Tables

**Helper**: `TableHelper` (`app/helpers/table_helper.rb`)

Tables are rendered with a responsive wrapper container that includes shadow, border, and horizontal scroll handling.
The table uses opaque backgrounds for proper visual hierarchy in both light and dark modes.

#### Standard Table

```erb
<%= ui_table full_width: true do |t| %>
<%= t.header do %>
<%= t.heading "Name" %>
<%= t.heading "Email" %>
<%= t.heading "Status", right: true %>
<% end %>
<%= t.body do %>
<% @users.each do |user| %>
<%= t.row do %>
<%= t.row_header user.name %>
<%= t.cell user.email %>
<%= t.cell user.status, right: true %>
<% end %>
<% end %>
<% end %>
<% end %>
```

#### Striped Table (ADHD-Friendly)

Use striped rows for improved readability, especially for data-dense tables:

```erb
<%= ui_table full_width: true, striped: true do |t| %>
<%= t.header do %>
<%= t.heading "Position" %>
<%= t.heading "Hours", right: true %>
<% end %>
<%= t.body do %>
<% @positions.each do |position| %>
<%= t.row do %>
<%= t.cell position.title %>
<%= t.cell position.hours, right: true %>
<% end %>
<% end %>
<% end %>
<% end %>
```

#### Table Options

| Option        | Type    | Default | Description                                        |
|---------------|---------|---------|----------------------------------------------------|
| `full_width:` | Boolean | `false` | Table spans full container width; otherwise its box fits its content, capped at its parent |
| `striped:`    | Boolean | `true`  | Alternating row backgrounds for better readability |
| `responsive:` | Boolean | `true`  | Below `lg`, each row folds into a card of labeled fields; `false` keeps a plain table |
| `caption:`    | String  | `nil`   | Table caption for accessibility                    |

#### Cell Alignment

Headings and cells support alignment options:

```erb
<%= t.heading "Amount", right: true %>     <%# Right-aligned %>
<%= t.heading "Status", center: true %>    <%# Center-aligned %>
<%= t.cell value, right: true %>           <%# Right-aligned cell %>
```

#### Table CSS Utilities

The table helper uses these custom utility classes (defined in `app/assets/stylesheets/components/tables.css`):

| Utility             | Description                                            |
|---------------------|--------------------------------------------------------|
| `table-container`   | Wrapper with overflow, shadow, border, rounded corners |
| `table-header`      | Header row with medium background                      |
| `table-row-base`    | Standard row with opaque background                    |
| `table-row-hover`   | Hover state with medium background                     |
| `table-row-striped` | Alternating row backgrounds                            |

#### Responsive Table

`ui_table` is responsive by default (since 2026-10-03): it keeps a native `<table>` on desktop —
columns auto-size to their widest content — while each row becomes a card of labeled fields below
the `lg` breakpoint (1024px).
Labels are read from `data-label` attributes the helper auto-derives from the column headings.
Note this pivots on **viewport** width, not container width: a table in a narrow sidebar or modal
stays tabular on a wide screen.

Inside the card the fields wrap rather than stack: each reserves a floor width and the row fits as
many across as the screen honestly affords, so a phone gets one field per line, a tablet gets three
or four, and a record just under 1024px is two lines instead of eight. There is no second breakpoint
doing this — `flex-wrap` asks the only question that matters, which is whether another field fits.
A field holding free text outgrows the floor and takes a line of its own rather than being capped at
a fraction of the row.

```erb
<%= ui_table full_width: true, striped: true do |t| %>
<% t.header do %>
<% t.heading "Name", width: "200px" %>
<% t.heading "Email" %>
<% t.heading "Status" %>
<% end %>
<% t.body do %>
<% @users.each do |user| %>
<% t.row do %>
<% t.row_header user.name %>
<% t.cell user.email %>
<% t.cell user.status %>
<% end %>
<% end %>
<% end %>
<% end %>
```

##### No Sub-Modes

The responsive layout has one behavior: a native `<table>` on desktop, becoming
cards of labeled fields below the `lg` breakpoint (1024px). There is no `mode:`
option — unrecognized keywords fall through to `**options` and are emitted as
raw attributes on the `<table>` element.

#### When to Pass `responsive: false`

**CRITICAL:** responsive is the default, including for admin reports. The wider the table, the more
it needs it.

A plain table puts its overflow behind a horizontal scroll inside the container. On a phone
that scrollbar is an overlay: it is invisible until something moves, so the columns past the fold
read as columns that do not exist. An eight-column log at 390px hid five of them — 55% of the row —
with nothing on screen to say so. That is why "admin, so desktop-first" is not a reason to skip it:
the Request Log, the ticketing reports, and the timesheet reports are all read on a phone on playa.

**Keep the default when:**

- The table has more columns than fit at 390px — in practice, five or more
- Any user-facing route, `/me` or otherwise
- Reports and logs an admin might open away from a desk

**Pass `responsive: false` when:**

- The grid itself is the point and sideways scrolling is the intended reading — a year-by-year
  matrix with a frozen first column, or a ledger sorted from its headings. Say so in a comment at
  the call site, as `timesheets/top_hour_earners` and `bmid/manage/_table` do
- It is a print sheet: the fold is a width query, and a printed page is narrower than `lg`, so a
  responsive table prints as cards
- The table is short enough to read as a table on a phone (roughly four columns or fewer). Plain
  is allowed there, not required

A fit-width table (`full_width: false`, the default) is no reason to opt out. Its box is sized to
its content but capped at its parent (`max-w-full`), so a value wider than a phone — an address, an
id list, a nowrap cell — scrolls inside the box like any plain table's overflow.

**Key Differences:**

| Feature         | `ui_table responsive: false` | `ui_table` (the default)                            |
|-----------------|-------------------------|----------------------------------------------------------|
| Narrow Strategy | Horizontal scroll       | Rows become cards of labeled fields, wrapping to width   |
| Pivot Trigger   | n/a                     | Media query below the `lg` breakpoint (1024px)           |
| Column Limit    | Unlimited               | Unlimited; the win grows with column count               |
| Implementation  | Standard HTML `<table>` | Standard HTML `<table>` + `.responsive-table`            |
| Striped Rows    | Yes (`:striped` option) | Yes (`:striped` option)                                  |
| Mobile Labels   | No                      | Yes, auto-derived `data-label` on each cell              |
| Use Case        | Narrow tables, deliberate matrices | Everything else                               |

#### Client-Side Sortable Headings

Sort on the server — a sort link that re-runs the query, as `bmid/manage` does — whenever the
server can produce the rows again. Sort in the browser only when it cannot: Salesforce Query's
rows come from a POST, and asking Salesforce again would cost two API calls a click.

There, `table_sort_controller.js` (`table-sort`) reorders the rows already on the page. Put
`data-controller="table-sort"` on an element that outlives the table; each `th` carries
`data-sort-type="number|text"` and holds a `<button type="button">` with
`data-action="table-sort#sort"`, styled with `Bmid::ManageHelper::SORT_LINK_CLASSES` (36px, with a
focus ring offset for the base-200 header). The raw button is a ruled exception (2026-10-05):
ButtonHelper always makes a `btn`.

- **Accessibility (WAI-ARIA sortable table):** the button's name is the column name; `aria-sort`
  sits only on the sorted `th`; an sr-only caption says the headings sort; a visible status line
  ("Sorted by Name, ascending.") is also written to `#live-region`, because screen readers do not
  announce a change of `aria-sort`
- **Icons change shape, not just colour:** a muted `fa-sort` on unsorted columns, `fa-caret-up` or
  `fa-caret-down` on the sorted one
- **Order:** numbers by value, text through `Intl.Collator` (case-insensitive, `R-9999` before
  `R-10000`), a `data-sort-value=""` cell (a null) last in both directions, ties in the server's
  order

BMID's server-sorted headings follow an older convention (`aria-sort="none"` on every heading and
a next-direction `aria-label`); the two coexist until a third sortable table extracts one helper.

#### Filtering Tables

**PREFERRED:** When a table page offers user-adjustable filters, use the
`filter_bar` helper (`app/helpers/ui_components/filter_bar_helper.rb`) above the
table — do not build ad-hoc filter forms, accordions, or chip rows.

It renders a slim always-visible row (a "Filters" disclosure button with an
active-count badge, one removable chip per applied filter, a clear-all link, an
optional result count, and the page's trailing actions) plus a collapsed panel
holding the page's filter form with batch Apply semantics. Chips are plain GET
links whose URLs drop that one filter. In use on Action Logs, Slots by Position,
and Asset Management.

**The page's CSV export belongs in `actions:`**, at the far end of that row —
not in a `button_row` above or below it. The export is scoped by the filters,
so it lives on the control that sets them, and a reader looking for either
finds both in one place. The 36px touch floor comes from `btn-sm` itself
(accessibility.css), so no call site spells it. Pass a conditional
straight through (`actions: (export if @rows.any?)`); a blank action renders
nothing. An export whose file is the whole year rather than the filtered view
still rides the bar and says so in its label ("Export All to CSV"); a second
export describing a different table on the page stays beside that table.

See `docs/UI-COMPONENTS.md` → `filter_bar` for the full API.

### Modals

**Helper**: `ModalHelper` (`app/helpers/modal_helper.rb`)

```erb
<%= modal id: "my-modal" do |m| %>
<%= m.title "Modal Title" %>
<%= m.body do %>
    Modal content here.
<% end %>
<%= m.footer do %>
<%= button_row do %>
<%= button_action "Confirm", :primary %>
<%= modal_close_button "Cancel" %>
<% end %>
<% end %>
<% end %>
```

**Opening modals**: Use Stimulus controller `data-controller="modal"`

### Accordions & Disclosures

Both helpers render native `<details>` / `<summary>` markup:

- `ui_accordion` — the DaisyUI collapse-arrow accordion preset (compact styling used on the person page).
  `unstyled: true` is reserved for fully custom shells with their own CSS component (e.g. the VC stage cards).
- `ui_disclosure` — plain disclosures: a bare inline expander (default, keeps the native triangle marker) or a
  boxed card with title, optional subtitle, and rotating chevron (`variant: :card`).

```erb
<%= ui_accordion("Positions (3 positions)") do %>
  <div class="grid grid-cols-2 gap-1 text-sm text-body">
    ...
  </div>
<% end %>

<%= ui_disclosure "Event categories", variant: :card, subtitle: "Show filter options" do %>
  ...
<% end %>
```

### Match Stepper

**Helper**: `UiComponents::UiMatchStepperHelper` (`app/helpers/ui_components/ui_match_stepper_helper.rb`).
Approved 2026-10-30 for the mailbox's search (slice 2 of `.scratch/messages-search/PRD.md`).

"Match 2 of 3" between a Previous and a Next button, joined (`join`, secondary outline, 36px square
icon buttons): how a reader walks a search's matches one at a time. The helper is the markup; a
Stimulus controller of the page's own counts, moves and scrolls.

```erb
<div class="sticky top-2 z-10 w-fit ms-auto mb-3 bg-base-100 rounded-field">
  <%= ui_match_stepper "search-matches", label: "Matches in this conversation", current: 1, total: 3 %>
</div>
```

- **One stop per record holding a match**, not per highlighted word: the mailbox steps message to
  message, and the ring that marks the current one is the landing ring a search already draws
  (`data-landing:ring-2 ring-primary`). No new colour.
- **Round past either end**, as a browser's Find does: Next on the last goes back to the first. With
  one match, either button brings it back on screen.
- **Pinned on its own row** over what it steps through (`sticky top-2`, right-aligned, on the
  surface's own `bg-base-100`), never in a header that scrolls away. A record it brings to the top
  stops clear of it: the mailbox's landing card takes `scroll-mt-18` (the pane's 16px padding, the
  stepper's 8px inset, its 36px and a 12px gap), and one under the stepper counts as out of view, so
  a step to it scrolls it clear. A step moves at once, never smoothly.
- **Drawn only when there is a match**, at the one the page opens on: the server knows the count and
  the landing, so nothing appears or jumps once the page has scrolled.
- **Accessibility**: a `role="group"` named by `label:`; the count is a polite `role="status"` a
  screen reader announces as it changes; the buttons are named "Previous match" and "Next match",
  and keep focus, so Enter steps again.

### Tabs

**Helper**: `TabsHelper` (`app/helpers/tabs_helper.rb`)

```erb
<%= tab_navigation "my-tabs", :first_tab do |tabs| %>
  <% tabs.pane "First Tab", :first_tab do %>
    Content for first tab.
  <% end %>
  <% tabs.pane "Second Tab", :second_tab do %>
    Content for second tab.
  <% end %>
  <%# Remote tab (loads via Turbo) %>
  <% tabs.pane "Remote Tab", :remote_tab, href: remote_content_path %>
<% end %>
```

The helper renders the DaisyUI `tabs tabs-border` markup with the ARIA roles wired up; do not hand-write it.

### Toasts & Notifications

**Helper**: `UiComponents::NoticeBoxHelper` (`app/helpers/ui_components/notice_box_helper.rb`)

#### Flash Messages (automatic)

Flash messages are automatically rendered in the layout. Set via controller:

```ruby
flash[:success] = "Note added."
flash[:error] = "The shift could not be removed. Reload the page and try again."
flash[:warning] = "Firecracker is already signed up for this shift."
flash[:info] = "No changes were submitted."
```

The wording rules (`<Thing> <past participle>.` for a success) are in
[Flash Messages](#flash-messages) under Language & Content.

Rails' own `notice:` and `alert:` keys work too: `notice` shows as success and `alert` as error. A
message that only says nothing happened ("No changes were submitted") is `info`, not `notice`.

How long a toast stays, and how a screen reader hears it, follows its type (`TOAST_TYPES` in
`toast_helper.rb`):

| Type | Stays | Screen reader |
|---|---|---|
| `success`, `notice`, `info` | Six seconds; hovering pauses it | `role="status"`: read once it finishes what it is reading |
| `warning` | Six seconds; hovering pauses it | `role="alert"`: interrupts |
| `error`, `alert` | Until closed; no countdown bar | `role="alert"`: interrupts |

#### Unread Messages Envelope (navbar)

The navbar's envelope (`app/views/application/_navbar_messages.html.erb`) is the one place outside the mailbox
that says a message is waiting: a 36px `btn-square` ghost button with a `ui_badge … :warning` count, linking to the
Unread folder. The count is the Unread tab's. It shows only while the count is above zero and only to Rangers and
Echelon (`Person#mailbox_user?`). It is never a toast: it stays on the bar until the threads are read.

- The daisyUI `indicator` is a wrapper `<span>`, never a class on the `.btn`: `.indicator` sets `width: max-content`
  from the utilities layer and would shrink a `btn-square` to its icon, under the 36px floor.
- The count is in the link's `aria-label` ("2 unread messages"); the badge is what a sighted reader sees.
- A message that arrives while the page is open replaces the envelope with the new count (a Turbo Stream over
  Action Cable) and adds one line, "Firecracker sent you a message.", to the layout's `#live-region`, which is the
  screen-reader half. Something the server pushes changes a persistent indicator like this one; it does not pop a
  toast.

#### Callout Boxes

```erb
<%# Basic callout %>
<%= ui_callout_box :success do %>
Your changes have been saved.
<% end %>

<%# With title %>
<%= ui_callout_box :warning, title: "Attention Required" do %>
Please review the information below.
<% end %>

<%# Accent style (left border emphasis) %>
<%= ui_callout_box :error, accent: true do %>
This action cannot be undone.
<% end %>

<%# Custom icon %>
<%= ui_callout_box :info, icon: "lightbulb", icon_type: :solid do %>
Pro tip: You can do this faster.
<% end %>
```

**Variants**: `:success`, `:info`, `:warning`, `:error`, `:secondary`

#### Alert Banners

```erb
<%= ui_alert_banner "Important Notice", :warning do %>
Banner content with prominent styling.
<% end %>
```

#### Copy Confirmation

**Helper**: `UiComponents::ClipboardHelper` (`app/helpers/ui_components/clipboard_helper.rb`)

A copy is confirmed where it was asked for: a "Copied" tip over the control for two seconds. It is not a
toast — a toast answers in the corner of the page, away from the thing just pressed.

```erb
<%= clipboard_button person.email, label: "Copy email address" do %>
  <%= mail_to person.email %>
<% end %>
```

- **Styling**: `.copy-tip` in `components/buttons.css`, dressed as a daisyUI tooltip (`bg-neutral`,
  `text-neutral-content`, `text-sm`) with no tail. No entrance or exit animation.
- **Placement**: a popover anchored to the control — above it, centred, shifted to stay inside the window,
  below when there is no room above. The top layer keeps a table or a scrolling box from clipping it. A
  browser without CSS anchor positioning gets a plain box above the control instead.
- **Accessibility**: the tip is `aria-hidden`; screen readers are told by a line added to `#live-region`
  (`aria-live="polite"`) in the application layout. Focus stays on the control.

API and the full-button form: `docs/UI-COMPONENTS.md` > `clipboard_button`.

### Hero Panels

**Helper**: `UiHeroPanelHelper` (`app/helpers/ui_components/ui_hero_panel_helper.rb`)

Hero panels are the standardized page header component used across all /me routes. They provide a consistent, visually
distinctive header: a warm neutral surface (`bg-base-200 dark:bg-base-300`) inside a soft amber ring
(`ring-signature-edge`, the token holding amber-200/40 and its dark amber-700/30 twin). That ring is the one place
amber survives as decoration rather than as a warning signal.

**Structure:**

```erb
<%= hero_panel icon: "calendar", heading_level: :h1, id: "unique-id" do |panel| %>
<% panel.title do %>
    Page Title
  <% end %>
  
  <% panel.description do %>
    Brief description of the page's purpose.
  <% end %>
  
  <% panel.back_to do %>
    <%= back_to "Previous Page", previous_path %>
  <% end %>
  
  <% panel.year_selector year: @year, years: current_user.years_combined %>
  
  <% panel.hero_stats do %>
    <%= panel.stat_badge "Label", "Value", color: :default %>
    <%= panel.stat_badge "Urgent", "5", color: :warning %>
  <% end %>
  
  <% panel.progress completed: 8, total: 10, start_label: "Tasks", end_label: "80%" %>
  
  <% panel.progress_status do %>
    Custom status content.
<% end %>
<% end %>
```

**Options:**

- `icon:` (required) - FontAwesome icon name
- `heading_level:` - `:h1` or `:h2` (default: `:h2`)
- `id:` - Unique ID for accessibility (auto-generated if not provided)

**Panel Methods:**

- `title` - Main page title (required)
- `description` - Page description — **one sentence only**, see below
- `back_to` - Back navigation link
- `year_selector` - Year dropdown (desktop: compact, mobile: full)
- `hero_stats` - Statistics badges (beside the title on desktop, beneath it on mobile) — **approval required**, see below
- `stat_badge` - Individual stat badge within hero_stats

**CRITICAL — hero stats need an approved plan**: Do not use `hero_stats` /
`stat_badge` unless the user approved a plan that puts stats in the hero. They compete
with the page title, and on mobile they stack beneath it and push the content down.
Summary numbers belong in the main body as a `ui_stat_row` above the content they
summarize:

```erb
<%= ui_stat_row do %>
  <%= ui_stat_box @report.trainee_count.to_s, "Trainees", variant: :warning %>
  <%= ui_stat_box @report.enrollment_count.to_s, "Sign-ups" %>
<% end %>
```

Only the /me dashboard welcome banner uses hero stats. See
[Hero Panel Stats Approval Workflow](#hero-panel-stats-approval-workflow).

**CRITICAL — description is one sentence**: `description` says what the page does in a
single sentence, and nothing more. The hero is the first fixation and is
size-constrained on mobile; a paragraph there pushes the real content below the fold.
Background, caveats, and especially step-by-step instructions go in the main content —
usually the collapsed card shown further down; a full page of instructions on a page the
reader operates takes a `ui_section` at the foot, announced from the top per the Help
Section & FAQ Pattern:

```erb
<%# Hero: one sentence %>
<% panel.description do %>
  Claim your ticket to use it this year, or bank it for a future event.
<% end %>

<%# Main content: everything longer %>
<%= ui_callout_box :info, icon: "circle-info", icon_type: :solid do %>
  New to ticketing? Read the <%= link_to "instructions", "#instructions", class: "underline font-semibold" %> below.
<% end %>

<%= ui_section "How Ticketing Works", id: "instructions", icon: "circle-question" do %>
  <dl class="instruction-list"><%# steps, caveats, contact info %></dl>
<% end %>
```

That is the shape for a page of instructions. For the usual one or two sentences of rule
or how-to, the house pattern is one collapsed card under the stat row, closed by default:

```erb
<%= ui_stat_row do %> … <% end %>

<%# "About This Report" on a report or a log; "How This Page Works" on a page the reader operates %>
<%= ui_disclosure "About This Report", variant: :card, class: "my-4" do %>
  <dl class="instruction-list">
    <dt>Where are the radios?</dt>
    <dd>Handheld radios are left out by default; choose Radio in the filters to include them.</dd>
  </dl>
<% end %>

<%= filter_bar … %>
```

Reference: `app/views/asset_management/asset_history/index.html.erb`, and
`app/views/ticketing/access_documents/index.html.erb` for a card that holds a legend with
samples. See `design-rules` > Hero Panel Description Rule, and its "Where a Rule or a How-To
Goes" for what belongs in the card and where it sits; `test/views/hero_description_test.rb`
guards the one-sentence rule.
- `progress` - Progress bar with labels
- `progress_status` - Custom content below progress bar

### Progress Bars

**Helper**: `UiProgressBarHelper` (`app/helpers/ui_components/ui_progress_bar_helper.rb`)

```erb
<%# Basic progress bar %>
<%= ui_progress_bar 75 %>

<%# With variant %>
<%= ui_progress_bar 50, :success %>

<%# With label %>
<%= ui_progress_bar 60, :warning, label: "Loading…" %>

<%# Show percentage %>
<%= ui_progress_bar 80, label: true %>

<%# Size options: :sm, :md, :lg, :xl %>
<%= ui_progress_bar 90, size: :lg %>
```

### Sections

**Helper**: `UiSectionHelper` (`app/helpers/ui_components/ui_section_helper.rb`)

Sections are card-like containers for grouping related content. They feature rounded corners, subtle shadows, and
semantic backgrounds.

```erb
<%# Basic section %>
<%= ui_section "Section Title" do %>
Section content.
<% end %>

<%# With icon %>
<%= ui_section "Profile", icon: "user", icon_type: :solid do %>
Profile content.
<% end %>

<%# Without border padding %>
<%= ui_section "Table Section", border: false do %>
<%= ui_table do |t| %>
<%# Table content %>
<% end %>
<% end %>

<%# With custom ID for anchor links %>
<%= ui_section "Team Members", id: "team-123" do %>
Member content.
<% end %>

<%# Two columns: the flex wrapper does the work, no option needed %>
<div class="flex flex-col lg:flex-row gap-4">
  <%= ui_section "Left Column" do %>
    Left content.
  <% end %>
  <%= ui_section "Right Column" do %>
    Right content.
  <% end %>
</div>
```

**Styling:**

- Base: `.box` class with `rounded-xl`, border, shadow
- Body: `bg-base-100` with `rounded-b-xl` (matches parent corners)
- Default padding: `px-4 pb-2` (omitted when `border: false`)
- Section title: `px-4 py-2` with responsive text sizing

**Options:**

- `icon:` - FontAwesome icon name
- `icon_type:` - Icon style (`:solid`, `:regular`)
- `border:` - Set to `false` to remove padding (useful for tables)
- `id:` - Custom ID for the section
- `badge:` / `badge_color:` - Badge in the title row
- `edit_link:` - Path for an edit button in the title row
- `class:` - Additional CSS classes for the outer box
- `body_class:` - Additional CSS classes for the body div

### Badges

**Helper**: `BadgeHelper` (`app/helpers/ui_components/badge_helper.rb`)

```erb
<%# Basic badges %>
<%= ui_badge "New", :primary %>
<%= ui_badge "Approved", :success %>
<%= ui_badge "Pending", :warning %>
<%= ui_badge "Rejected", :error %>
<%= ui_badge "Draft", :secondary %>

<%# With icons %>
<%= ui_badge "Completed", :success, icon: "circle-check", icon_type: :solid %>
<%= ui_badge "Action Needed", :warning, icon: "circle-exclamation", icon_type: :solid %>
<%= ui_badge "Blocked", :error, icon: "triangle-exclamation", icon_type: :solid %>

<%# Size options %>
<%= ui_badge "Small", :primary, size: "xs" %>
<%= ui_badge "In a text-lg headline", :primary, size: "base" %>
```

**Options:**

- `icon:` - FontAwesome icon name (optional)
- `icon_type:` - Icon style (`:solid`, `:regular`) - default `:solid`
- `size:` - Text size (`"xs"`, `"sm"`, `"base"`) - default `"xs"`; `"md"` is not a Tailwind text size
- `class:` - Additional CSS classes
- `aria:` - ARIA attributes hash

### Sidebar

**Helper**: `SidebarHelper` (`app/helpers/sidebar_helper.rb`)

The sidebar is a DaisyUI-inspired drawer component that serves as the primary navigation for the application. It
features a mobile-responsive design that slides in from the left, with dark theme-specific styling and support for
sections, submenus, and badges.

#### Basic Usage

```erb
<%= sidebar_menu "me" do %>
<%= sidebar_section "Navigation", theme: "me" do %>
<%= sidebar_item "Dashboard", me_root_path, icon: "home", theme: "me", root: true %>
<%= sidebar_item "Schedule", me_schedule_path, icon: "calendar", theme: "me" %>
<% end %>

<%# A submenu is a heading followed by indented items -- it takes no block %>
<%= sidebar_submenu "Settings", icon: "gear", icon_type: :solid, theme: "me" %>
<%= sidebar_submenu_item "Profile", me_profile_path, theme: "me" %>
<%= sidebar_submenu_item "Password", me_password_path, theme: "me" %>
<% end %>
```

#### Sidebar Structure

The sidebar is composed of several key components:

1. **Backdrop** - Semi-transparent overlay (mobile only)
2. **Drawer** - Main sidebar container with navigation items
3. **Close button** - X button for mobile (hidden on desktop)
4. **Toggle button** - Hamburger menu button (placed in navbar)
5. **Sections** - Titled groups of navigation items
6. **Items** - Individual navigation links
7. **Submenus** - Collapsible groups of related links
8. **Badges** - Notification counts on items

**HTML Structure:**

```erb
<%# Backdrop (mobile only) %>
<div class="sidebar-backdrop"></div>

<%# Drawer container %>
<aside class="sidebar-drawer">
<%# Close button (mobile only) %>
<button class="sidebar-close-btn">×</button>

<%# Section with header %>
  <div>
    <h6 class="sidebar-section-header">Section Title</h6>
    <a class="sidebar-nav-item">Link</a>
    <span class="sidebar-badge">5</span>
  </div>
</aside>
```

#### Theme Variants

`sidebar_menu` accepts `"me"`, `"admin"`, or `"hq"`; any other value falls back to `"me"` (`SidebarHelper::THEME_CONFIGS`).
Two palettes are in use (`components/sidebar.css`).

**"me" and "hq" themes** (`sidebar-link-default` / `sidebar-group-title-default`):

- Section background: `bg-chrome` (`#000000`) with `text-sidebar-content` (`#f0f0f0`)
- Item background: `bg-sidebar-link` (`#3e4348`, slate)

**"admin" theme** (`sidebar-link-hq` / `sidebar-group-title-hq`):

- Section background: `bg-sidebar-title-hq` (`#3d2503`, dark brown)
- Item background: `bg-sidebar-link-hq` (`#524737`, khaki)

**Common to all themes:**

- Drawer background: `bg-chrome` (`#000000`)
- Border: `border-sidebar-divider` (`#101010`)
- Text: `text-sidebar-content` (`#f0f0f0`)
- Active state: `!text-sidebar-active` (`#ffc107`) with a 5px right border

#### Sidebar Options

**`sidebar_menu` options:**

```erb
<%= sidebar_menu theme, id: "sidebar-drawer", width: "w-65 lg:w-45" do %>
...
<% end %>
```

| Option       | Type    | Default            | Description                                    |
|--------------|---------|--------------------|------------------------------------------------|
| `theme`      | String  | `"me"`             | Color theme: `"me"`, `"admin"`, or `"hq"`      |
| `id:`        | String  | `"sidebar-drawer"` | Drawer ID for CSS toggle                       |
| `width:`     | String  | `"w-65 lg:w-45"`   | Drawer width classes                           |

**`sidebar_item` options:**

```erb
<%= sidebar_item "Title", url, 
    icon: "icon-name", 
    icon_type: :solid, 
    badge: "5", 
    badge_variant: :error,
    theme: "me",
    root: false,
    active_prefix: false,
    use_turbo: false,
    active: nil %>
```

| Option           | Type    | Default    | Description                                            |
|------------------|---------|------------|--------------------------------------------------------|
| `icon:`          | String  | `nil`      | FontAwesome icon name                                  |
| `icon_type:`     | Symbol  | `:regular` | Icon style (`:solid`, `:regular`)                      |
| `badge:`         | String  | `nil`      | Badge text/number to display                           |
| `badge_variant:` | Symbol  | `:error`   | Badge color: `:error`, `:success`, `:warning`, `:info`, `:default` |
| `theme:`         | String  | `"me"`     | Color theme for styling                                |
| `root:`          | Boolean | `false`    | Root path for active state detection                   |
| `active_prefix:` | Boolean | `false`    | Keep the item active for descendant routes with the same path prefix |
| `use_turbo:`     | Boolean | `false`    | Enable Turbo navigation                                |
| `active:`        | Boolean | `nil`      | Manually set active state (auto-detects if `nil`)      |

#### Active State Styling

Active navigation items receive distinctive amber styling:

**Active item classes:**

- Text color: `!text-sidebar-active` (`#ffc107`) with `!important`
- Right border: `5px` solid `!border-r-sidebar-active` (`#ffc107`)
- Background: Same as theme (no change)

```erb
<%# Active state is automatically detected with current_page? %>
<%= sidebar_item "Dashboard", me_root_path, theme: "me" %>

<%# Or keep a schedule item active for nested schedule pages %>
<%= sidebar_item "Schedule", me_schedule_path, active_prefix: true, theme: "me" %>

<%# Or manually set active state %>
<%= sidebar_item "Current", path, active: true, theme: "me" %>
```

#### Submenu Pattern

Submenus are rendered as section titles to group related navigation items:

```erb
<%= sidebar_submenu "Settings", icon: "gear", icon_type: :solid, theme: "me" %>
```

**Submenu features:**

- Renders the title with optional FontAwesome icon
- Applies theme-aware text and background styling
- Designed for simple grouping (no interactive disclosure)

#### Badge Variants

Badges display notification counts on sidebar items:

```erb
<%# Danger badge (red) - default %>
<%= sidebar_item "Messages", messages_path, badge: "5", badge_variant: :error %>

<%# Success badge (green) %>
<%= sidebar_item "Completed", tasks_path, badge: "12", badge_variant: :success %>

<%# Warning badge (amber) %>
<%= sidebar_item "Pending", pending_path, badge: "3", badge_variant: :warning %>

<%# Info badge (blue) %>
<%= sidebar_item "New", new_items_path, badge: "2", badge_variant: :info %>
```

**Badge styling:**

- Danger: Red text, red background, red border
- Success: Green text, green background, green border
- Warning: Amber text, amber background, amber border
- Info: Brand text, background, and border in Signal Blue

#### Mobile Behavior

The sidebar uses a CSS-only toggle mechanism with progressive enhancement:

**Mobile (< 1024px):**

- Drawer is hidden by default (`-translate-x-full`)
- Backdrop appears when drawer is open
- Close button (X) visible in top-right
- Checkbox state controls visibility (`peer-checked:translate-x-0`)

**Desktop (≥ 1024px):**

- Drawer is always visible (`lg:translate-x-0`)
- Backdrop is hidden (`lg:hidden`)
- Close button is hidden (`lg:hidden`)
- Toggle button is hidden (`lg:hidden`)

**Positioning:**

- Drawer starts below navbar: `top-[64px]`
- Height: `calc(100vh - 64px)` (full viewport minus navbar)
- Fixed positioning on mobile
- Z-index: `40` (drawer), `30` (backdrop)

#### Utility Classes

Custom utility classes defined in `app/assets/stylesheets/components/sidebar.css`:

| Utility                  | CSS Composition                                                                                                                             | Usage                    |
|--------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|--------------------------|
| `sidebar-backdrop`       | `fixed inset-0 top-[64px] bg-gray-900/50 dark:bg-gray-900/80 z-30 hidden peer-checked:block lg:hidden`                                      | Semi-transparent overlay |
| `sidebar-drawer`         | `fixed z-40 overflow-y-auto transition-transform top-[64px] h-[calc(100vh-64px)]`                                                           | Main drawer container    |
| `sidebar-close-btn`      | `bg-transparent hover:bg-white/10 rounded-lg w-9 h-9 absolute top-2.5 end-2.5 flex items-center justify-center lg:hidden`                   | Close button (X)         |
| `sidebar-nav-item`       | `block h-10 flex items-center p-3 text-sm transition-colors no-underline border-t border-sidebar-divider`                                   | Navigation link base     |
| `sidebar-section-header` | `p-3 font-semibold uppercase tracking-wider overflow-hidden text-ellipsis`                                                                  | Section title styling    |
| `sidebar-badge`          | `inline-flex items-center justify-center w-auto min-w-[1.125rem] h-4.5 ms-2 px-1.5 text-xs font-medium rounded-full`                        | Notification count badge |

#### Logo Area

The sidebar includes a footer logo area at the bottom:

**Features:**

- Ranger logo image: `180px × 180px`
- Top border: `1px solid border-sidebar-divider` (`#101010`)
- Top padding/margin: `10px` (pt-10, mt-10)
- Centered alignment
- Bottom margin: `10px` (mb-10)
- Does not scroll (uses `shrink-0`)

#### Toggle Button Placement

The sidebar toggle button should be placed in the navbar/header:

```erb
<%# In application/_top_menu.html.erb %>
<label for="sidebar-drawer" class="inline-flex items-center p-2 text-sm ...">
<%= fa_icon "bars", :solid %>
<span class="ms-1 text-sidebar-content">Sidebar</span>
</label>
```

#### Accessibility Features

- **ARIA labels**: Drawer has `aria-label="Sidebar navigation"` and `aria-labelledby`
- **ARIA expanded**: Toggle button indicates expand/collapse state
- **Keyboard navigation**: Full keyboard support for all interactive elements
- **Focus management**: Visible focus states with ring outline
- **Screen reader text**: "Open sidebar" / "Close sidebar" labels
- **Role presentation**: Backdrop has `role="presentation"`

#### When to Use

**Use the sidebar when:**

- Building primary navigation for /me or /admin routes
- Need collapsible navigation on mobile
- Want consistent dark-themed navigation
- Require section grouping and submenus

**Component locations:**

- Layouts: `app/views/layouts/me.html.erb`, `app/views/layouts/admin.html.erb`
- Helper: `app/helpers/sidebar_helper.rb`
- Utility CSS: `app/assets/stylesheets/components/sidebar.css`
- Controller: `app/javascript/controllers/sidebar_controller.js`

### Empty States

**Helper**: `UiComponents::NoticeBoxHelper` (`app/helpers/ui_components/notice_box_helper.rb`)

```erb
<%# Basic usage %>
<%= ui_empty_state "No items found." %>

<%# With icon %>
<%= ui_empty_state "No messages yet.", icon: "envelope", icon_type: :regular %>

<%# With custom class %>
<%= ui_empty_state "No results.", class: "text-lg" %>

<%# With block for complex content %>
<%= ui_empty_state do %>
No upcoming shifts found. <%= link_to "Browse available shifts", available_shifts_path %>.
<% end %>
```

### Navigation Dropdowns

**Helper**: `NavigationHelper` (`app/helpers/navigation_helper.rb`)

```erb
<%# Native <details> dropdown: the label is the trigger button (variant: a ButtonHelper
    variant, default :secondary); class: takes DaisyUI placement modifiers;
    menu_label: names the list when the label is a greeting ("Hello Firecracker") %>
<%= dropdown_menu "Menu", class: "dropdown-end", menu_class: "w-64" do %>
<%= dropdown_item "Profile", profile_path %>
<%= dropdown_item "Settings", settings_path %>
<%= dropdown_divider %>
<%= dropdown_item "Logout", logout_path, data: { turbo_method: :delete } %>
<% end %>

<%# Disabled item %>
<%= dropdown_item_disabled "Coming Soon" %>
```

### Autocomplete Component

CSS utility classes for autocomplete dropdowns:

- `ac-results` - Results dropdown container
- `ac-option` - Individual selectable option (36px min-height for touch targets)
- `ac-option-active` - Keyboard-selected option with brand ring
- `ac-group` - Group container with separator
- `ac-group-header` - Uppercase group label
- `ac-filter-bar` - Filter chips container
- `ac-filter-chip` / `ac-filter-chip-active` - Filter toggle pills
- `ac-empty` - Empty state message
- `ac-error` - Error state message
- `ac-keyboard-help` - Keyboard shortcut footer

All classes support dark mode and respect `prefers-reduced-motion`.

### Onboarding Tour Popover (driver.js)

The first-sign-in tour on `/me` (approved 2026-10-17) is the one guided tour in the
app: a dimmed page with one element cut out and a popover beside it, drawn by the
vendored driver.js (`app/javascript/vendor/driver-1.10.1.js`, pinned in
`config/importmap.rb`) and driven by `onboarding_controller.js` from the step
templates in `app/views/me/dashboard/_onboarding.html.erb`. It is not a helper and
not for reuse on other pages without approval: a second tour is a second place the
reader is interrupted.

**Styling:** driver's sheet (`app/assets/stylesheets/driver.css`, verbatim, imported
in `@layer components`) draws the overlay, the cutout and the popover's geometry; `app/assets/stylesheets/components/driver.css`
re-themes the popover in tokens — `bg-base-100`, `text-body`, `border-line`,
`rounded-box`, the title at `text-lg` heading ink — so both themes follow. The
Back and Next/Done buttons are daisyUI's own `btn btn-sm` (ghost and primary), put on
by the controller: daisyUI compiles `btn` into the utilities layer, where it beats the
vendored rule, while an `@apply btn` lands in daisyUI's nested components sublayer and
loses to it. The close button is a 36px square with the app's focus ring.
driver's own fade and cutout glide are off (`animate: false`); the tour's only motion is
the smooth scroll to a step, off under `prefers-reduced-motion`.

**Copy:** each step is a Title Case heading and one or two short sentences, written
in the templates, so `design-content` review reads it where it lives.

---

## Form Patterns

**Builder**: `AppFormBuilder` (`app/helpers/form_helper.rb`)

### Compact, WCAG-Compliant Form Design

The form builder balances accessibility with compact layouts to minimize scrolling:

- **Touch targets**: 36px minimum (`min-h-9`), clearing WCAG 2.5.8's 24px AA floor
- **Compact spacing**: `mb-3` between fields, `mb-1` label gap, `space-y-1` for radio groups
- **Clear visual hierarchy**: Prominent labels always visible (never placeholder-only)
- **Strong focus states**: 2px ring with offset for keyboard navigation (WCAG 2.4.7)
- **Required field indicators**: Red asterisk with screen reader text "(required)"
- **Smooth transitions**: 150ms transitions for state changes
- **Immediate feedback**: Inline validation with role="alert" for screen readers
- **Semantic grouping**: Fieldsets with legends for related fields

### Basic Usage

```erb
<%# Using ui_form helper (recommended) %>
<%= ui_form(@user, users_path) do |f| %>
<%= f.text_field :name, label: "Full Name", required: true %>
<%= f.email_field :email, label: "Email Address", help_text: "We'll never share this" %>
<%= f.password_field :password, label: "Password", help_text: "Minimum 8 characters" %>

<%= button_row do %>
<%= f.submit "Save" %>
<%= cancel_button users_path %>
<% end %>
<% end %>

<%# Or using form_with directly %>
<%= form_with model: @user, builder: AppFormBuilder do |f| %>
<%= f.text_field :name, label: "Name" %>
<% end %>
```

### Layout Modes

```erb
<%# Vertical layout (default) - Best for mobile and accessibility %>
<%= ui_form(@user, users_path) do |f| %>
<%= f.text_field :name, label: "Name" %>
<% end %>

<%# Horizontal layout - Better for desktop dense forms %>
<%= ui_form(@user, users_path, layout: :horizontal) do |f| %>
<%= f.text_field :name, label: "Name" %>
<% end %>

<%# Auto layout - Vertical on mobile, horizontal on desktop (lg: breakpoint) %>
<%= ui_form(@user, users_path, layout: :auto) do |f| %>
<%= f.text_field :name, label: "Name" %>
<% end %>

<%# Per-field layout override %>
<%= f.text_field :name, label: "Name", layout: :horizontal %>
<%= f.text_field :name, label: "Name", layout: :auto %>

<%# Side-by-side fields with form_row %>
<%= form_row do %>
<%= f.text_field :first_name, label: "First", wrapper_class: "flex-1" %>
<%= f.text_field :last_name, label: "Last", wrapper_class: "flex-1" %>
<% end %>
```

### Field Options

All fields support these common options:

| Option           | Type    | Description                                                 |
|------------------|---------|-------------------------------------------------------------|
| `label:`         | String  | Label text (always use - never placeholder-only)            |
| `required:`      | Boolean | Shows red asterisk and adds `required` attribute            |
| `help_text:`     | String  | Supportive text below the field                             |
| `help_mode:`     | Symbol  | `:inline` (default) or `:tooltip` for help text display     |
| `layout:`        | Symbol  | `:vertical`, `:horizontal`, or `:auto`                      |
| `wrapper_class:` | String  | Custom classes for wrapper div                              |
| `wrapper_id:`    | String  | ID for wrapper div                                          |
| `width:`         | String  | Custom width classes (e.g., `"w-32"` or `"w-full sm:w-48"`) |
| `hidden:`        | Boolean | Adds `hidden` class to wrapper                              |
| `wrapper:`       | Boolean | Set to `false` to skip wrapper entirely                     |
| `hide_label:`    | Boolean | Visually hide the label                                     |
| `show_counter:`  | Boolean | Display character counter for fields with `maxlength`       |

### Field Types

```erb
<%# Text inputs %>
<%= f.text_field :name, label: "Name", required: true %>
<%= f.email_field :email, label: "Email" %>
<%= f.password_field :password, label: "Password" %>
<%= f.number_field :age, label: "Age" %>
<%= f.telephone_field :phone, label: "Phone" %>
<%= f.url_field :website, label: "Website" %>
<%= f.search_field :query, label: "Search" %>

<%# Text input with character counter %>
<%= f.text_field :callsign, label: "Callsign", maxlength: 20, show_counter: true %>

<%# Text input with responsive width %>
<%= f.text_field :preferred_name, label: "Preferred Name", width: "w-full sm:w-48" %>

<%# Text input with tooltip help text %>
<%= f.email_field :email, label: "Email", 
    help_text: "We'll never share your email with third parties", 
    help_mode: :tooltip %>

<%# Date/Time (with Vanilla Calendar Pro on desktop) %>
<%= f.datetime_field :starts_at, label: "Start Time" %>
<%= f.date_field :birth_date, label: "Birth Date" %>
<%= f.time_field :reminder, label: "Reminder Time" %>

<%# Textarea (120px minimum height) %>
<%= f.text_area :bio, label: "Biography", help_text: "Tell us about yourself" %>

<%# Rich text -- formatted body copy stored as HTML (Lexxy) %>
<%= f.rich_text_area :message, label: "Message", required: true %>

<%# Textarea with character counter (already supported) %>
<%= f.text_area :reason, label: "Reason", maxlength: 1000, data: input_counter_data %>

<%# Select %>
<%= f.select :role, [["Admin", "admin"], ["User", "user"]], { label: "Role" } %>
<%= f.collection_select :department_id, @departments, :id, :name, { label: "Department" } %>

<%# Checkboxes (36px tap target) %>
<%= f.check_box :terms, label: "I agree to the terms of service" %>
<%= f.check_box :newsletter, label: "Subscribe to newsletter", help_text: "Weekly updates" %>

<%# Radio buttons (36px tap target) %>
<%= f.radio_button :status, "active", label: "Active" %>
<%= f.radio_button :status, "inactive", label: "Inactive" %>
<%= f.collection_radio_buttons :priority, Priority.all, :id, :name, { label: "Priority" } %>

<%# File upload (styled upload button) %>
<%= f.file_field :avatar, label: "Profile Photo" %>
```

#### Rich Text Area

**When to use:** body copy an author needs to format — bold, lists, links,
headings, tables. Announcements are the first caller.

**When not to use:** anything short, single-line, or machine-read. A subject
line, a reason, a note — use `text_field` or `text_area`. Rich text stores HTML,
so it costs sanitizing on every render.

```erb
<%= f.rich_text_area :message, label: "Message", required: true,
                     help_text: "Keep it short. Bold the key point." %>
```

**Accessibility:** the label targets the editor, which carries `aria-describedby`
for help text and errors. The editor is form-associated, so `required:` blocks
submit natively, and Lexxy sets `aria-required` itself. Keyboard and screen-reader
support come from Lexxy itself.

**Styling:** three vendored sheets (`lexxy-variables.css`, `lexxy-content.css`,
`lexxy-editor.css`) draw the editor, and `app/assets/stylesheets/components/lexxy.css`
re-themes it by pointing Lexxy's `--lexxy-*` variables at the app's tokens, so
both themes are covered. Everything is in `@layer components`, so the error state
is a plain `border-error border-2` utility. Coloured text and uploads are off.

**Rendering saved text:** wrap in `.lexxy-content` and pass the HTML through
`rich_text`, which sanitizes. Without the class, lists render as unmarked lines
and tables have no borders.

Full API and caveats: `docs/form_helper.md` > Rich Text Area.

#### Callsign Chips Field

`f.callsign_chips_field` holds several callsigns as removable chips in one input box, over the
autocomplete. Owner-approved 2026-10-18 for the messages compose form's recipients.

**When to use:** a form that takes one or more people by callsign, where a suggestion list helps
and the server checks each callsign on submit.

**When not to use:** exactly one person, chosen from a list (`autocomplete_field`), or a person
the form must know is valid before submit.

**Accessibility:** the label targets the input, whose `aria-label` is "Add a callsign" and whose
`aria-describedby` names the help and error line. Each chip's remove button is 36px and labelled
"Remove ‹callsign›"; removing returns the focus to the input. Enter makes a chip, never a submit. A
press anywhere else in the box puts the caret in the text, as on a plain field.

**Styling:** chips are `rounded-full border border-line bg-base-200 text-sm text-body`, so both
themes come from the tokens. Full API: `docs/UI-COMPONENTS.md` > Callsign Chips Field.

### Form Grouping: Fieldsets vs UI Sections

**Two approaches for grouping form fields:**

#### When to Use `f.fieldset`

Best for semantic grouping of form controls with compact layout:

**Appropriate use cases:**

- Radio button and checkbox groups (semantic HTML standard)
- Correction/request forms with multiple distinct sections
- Forms where visual density is beneficial
- Related fields that need compact presentation

**Caution:** Screen readers announce the legend text for every input when tabbing through the fieldset. Avoid overuse
with many text inputs.

**Basic usage:**

```erb
<%= f.fieldset "Personal Information" do %>
<%= f.text_field :first_name, label: "First Name", required: true %>
<%= f.text_field :last_name, label: "Last Name", required: true %>
<%= f.email_field :email, label: "Email Address", required: true %>
<% end %>
```

**With icon (enhanced visual consistency):**

```erb
<%= f.fieldset "Vehicle Description", icon: "car", icon_type: :solid do %>
<%= f.select :vehicle_class, Vehicle::CLASS_OPTIONS, label: "Vehicle Class" %>
<%= f.text_field :vehicle_make, label: "Make" %>
<% end %>
```

**With Q&A explanations:**

```erb
<%= f.fieldset "Contact Information" do %>
  <dl class="instruction-list mb-3">
    <dt>Why do we need this?</dt>
    <dd>Used to contact you if email fails.</dd>
  </dl>
<%= f.text_field :phone, label: "Phone Number" %>
<% end %>
```

#### When to Use `ui_section`

Best for card-based grouping with generous whitespace and ADHD-friendly design:

**Appropriate use cases:**

- Profile edit forms with multiple logical sections
- Forms requiring extensive explanatory content
- User-facing editable profile data
- When visual distinction and breathing room are priorities

**Advantages:**

- Avoids screen reader verbosity with multiple text inputs
- Clear visual hierarchy with icons
- Better support for Q&A explanations
- Card-based chunking reduces cognitive load

**Basic usage:**

```erb
<%= ui_form(@person, path) do |f| %>
<%= ui_section "Legal Name", icon: "id-card", icon_type: :solid do %>
    <dl class="instruction-list mb-3">
      <dt>Why do we need this?</dt>
      <dd>Used for ticketing, mailings, and Motor Vehicle Record requests.</dd>
    </dl>
<%= form_row do %>
<%= f.text_field :first_name, label: "First Name", width: "w-full sm:w-48" %>
<%= f.text_field :last_name, label: "Last Name", width: "w-full sm:w-48" %>
<% end %>
<% end %>
<% end %>
```

**Hybrid approach (for complex forms):**

```erb
<%= ui_section do %>
<%= ui_form(@object, path) do |f| %>
<%= f.fieldset "Credentials" do %>
<%= f.password_field :old_password, label: "Old Password" %>
<%= f.password_field :password, label: "New Password" %>
<% end %>
<% end %>
<% end %>
```

### Error States

Errors are automatically displayed with ADHD-friendly prominence:

- **Field highlighting**: daisyUI `input-error` (error border and tint, both themes)
- **Error badge**: Small red circle with "!" for visual scanning
- **Error messages**: Displayed below field with `role="alert"` for screen readers
- **Label color change**: Red label indicates which field needs attention
- **Error summary**: `ui_form` shows all errors at top in callout box
- **Automatic focus**: First error field receives focus automatically on validation failure

```erb
<%# Error summary is automatic with ui_form %>
<%= ui_form(@user, users_path) do |f| %>
<%# Fields with errors automatically show error styling %>
<%= f.text_field :email, label: "Email" %>
<% end %>

<%# Skip error summary if desired %>
<%= ui_form(@user, users_path, no_error_summary: true) do |f| %>
...
<% end %>
```

**Error Focus Management:**

Forms automatically focus the first error field on validation failure, scrolling it into view for immediate correction.
This behavior is implemented via the `form` Stimulus controller.

### Accessibility Features

The form builder includes built-in accessibility:

- **Labels**: Always visible, properly associated with inputs via `for` attribute
- **Required fields**: Visual indicator (asterisk) plus screen reader text "(required)"
- **Help text**: Connected via `aria-describedby`
- **Error messages**: Use `role="alert"` for screen reader announcement
- **Focus states**: High-contrast 2px ring with offset, meets WCAG 2.4.7
- **Touch targets**: Minimum 36px height for all interactive elements
- **Keyboard navigation**: Full support with visible focus indicators

### ADHD-Friendly Form Page Patterns

These patterns document page-level structure for building scannable, ADHD-friendly edit forms. Use these in combination
with the field-level patterns above.

#### Form Page Structure

Standard structure for edit form pages:

```erb
<%# 1. Hero Panel with description and back navigation %>
<%= hero_panel icon: "icon-name", heading_level: :h1, id: "page-id" do |panel| %>
<% panel.title do %>Edit [Entity Name]<% end %>
<% panel.description do %>Brief summary of what can be edited.<% end %>
<% panel.back_to do %><%= back_to "Parent Page", parent_path %><% end %>
<% end %>

<%# 2. Contextual callouts (if needed) %>
<%= ui_callout_box :info, icon: "lightbulb", icon_type: :solid do %>
<strong>Lead with the key point.</strong> Supporting details follow.
<% end %>

<%# 3. Form with sectioned content %>
<%= ui_form(@model, submit_path) do |f| %>
<%= ui_section "Section Title", icon: "icon-name", icon_type: :solid do %>
<%# Q&A explanation + fields %>
<% end %>
<%# More sections... %>
<%# Sticky action buttons %>
<% end %>
```

#### Section Organization with Icons

Each logical group of fields should be wrapped in `ui_section` with a descriptive icon:

| Section Type        | Icon       | Usage                         |
|---------------------|------------|-------------------------------|
| Legal Name          | `id-card`  | Government ID fields          |
| Contact Information | `envelope` | Email, phone, address         |
| Personal Details    | `user`     | Gender, pronouns, preferences |
| Preferences         | `sliders`  | Settings, options             |
| Dates/Schedule      | `calendar` | Date/time fields              |
| Comments/Notes      | `comment`  | Text areas, descriptions      |

#### Q&A Style Explanations

Replace paragraphs with scannable Q&A format using `instruction-list`. On a report or a log the list goes inside the
page's one collapsed card, never visible in the body; the visible form below is for forms and pages the reader operates:

```erb
<dl class="instruction-list mb-3">
  <dt>Why do we need this?</dt>
  <dd>Concise answer in one sentence.</dd>
  <dt>Is this required?</dt>
  <dd>No, this field is optional.</dd>
</dl>
```

**Common questions to answer:**

| Question               | Purpose             |
|------------------------|---------------------|
| "Why do we need this?" | Explain purpose     |
| "Is this required?"    | Clarify optionality |
| "What happens if...?"  | Address concerns    |
| "Where is this used?"  | Explain visibility  |

#### Field Width Guidelines

Constrain field widths based on expected content instead of using full-width fields. **Always use responsive width
classes** to ensure proper display on mobile devices.

| Field Type                 | Width Class      | Pixels       | Notes                   |
|----------------------------|------------------|--------------|-------------------------|
| Names (first/last)         | `w-full sm:w-48` | Full → 192px | Responsive for mobile   |
| Middle initials            | `w-20`           | 80px         | Small enough for mobile |
| Phone numbers              | `w-full sm:w-44` | Full → 176px | Responsive for mobile   |
| Email addresses            | `w-full sm:w-72` | Full → 288px | Responsive for mobile   |
| Short text (pronunciation) | `w-full sm:w-64` | Full → 256px | Responsive for mobile   |
| Select dropdowns           | `w-full sm:w-44` | Full → 176px | Responsive for mobile   |

**Mobile-First Approach:**

- Use `w-full` for mobile to prevent horizontal scrolling
- Add `sm:` prefix for desktop widths (640px and above)
- Fields narrower than `w-32` don't need responsive classes
- `sm:` is otherwise an AVOID breakpoint (see Responsive Breakpoints); field `width:` is its one sanctioned use

```erb
<%# Responsive width for better mobile UX %>
<%= f.text_field :preferred_name, label: "Preferred Name", width: "w-full sm:w-48" %>
<%= f.text_field :email, label: "Email", width: "w-full sm:w-72" %>

<%# Small fields don't need responsive widths %>
<%= f.text_field :mi, label: "Middle Initial", width: "w-20" %>
```

#### Conditional Field Layout

When a select triggers a custom text field (e.g., "Something else" option), place them side-by-side:

```erb
<div class="flex flex-col lg:flex-row lg:items-start gap-2 lg:gap-4">
<%= f.select :field, OPTIONS, { label: "Label" },
    { class: "w-44", data: { controller: "conditional-show", ... } } %>
<%= f.text_field :custom_field, label: "Custom Value",
    width: "w-64", wrapper_id: "custom-block", hidden: !show_custom? %>
</div>
```

Key classes:

- `lg:items-start` - Align labels at top (not bottom)
- `gap-2 lg:gap-4` - Tight mobile spacing, comfortable desktop spacing

#### Sub-section Dividers

Use border dividers to separate related field groups within a section:

```erb
<div class="mt-4 pt-3 border-t border-line">
  <dl class="instruction-list mb-3">...</dl>
<%# Related fields %>
</div>
```

#### Sticky Save Button (Mobile)

Keep save/cancel buttons accessible on mobile devices by using the `sticky: true` option on `button_row`:

```erb
<%= button_row do %>
<%= f.submit "Save Changes" %>
<%= cancel_link back_path %>
<% end %>
```

**Behavior:**

- Mobile: Button row is fixed to the bottom of the viewport with:
    - Solid opaque background (white/gray-900) for strong contrast
    - Upward shadow for visual separation from content
    - Strong border for clear delineation
    - Full-width edge-to-edge coverage
    - Automatic spacer element to prevent content overlap
- Desktop (`lg:` breakpoint and above): Normal static positioning with no extra styling

**When to use:**

- Forms that may scroll on mobile devices
- Edit pages where the save/cancel buttons might be off-screen
- Any form where users need easy access to submit actions while scrolling

**Note:** The helper automatically adds a spacer element on mobile to prevent the fixed button row from covering
the last form section. This spacer is hidden on desktop.

The spacer's height is **derived, never chosen** — there is no height option to pass. The helper counts the controls it
rendered (each top-level element in the block; hidden fields draw nothing and are skipped) and hands the count to CSS as
`--button-row-controls`. `.button-row-spacer` in `components/buttons.css` adds up the row's own box from it: border and
padding, one control height per line, the `1.5vh` gaps between them, and the home-indicator inset. A form that gains a
conditional Delete button gets the taller spacer on the request that renders it.

Two refinements:

- The control height is not restated anywhere. The spacer wears the row's tallest DaisyUI size class (`btn-sm` unless a
  control passes `size: "base"`, `"lg"` or `"xl"`) purely to read `--size` from it — the same number the buttons get,
  36px floor included. A row that mixes sizes therefore reserves slightly more than it covers — never less.
- Full-width bars (`full_width: true`) stay one to a line until `lg`, so their spacer keeps the stacked height through
  the tablet band instead of dropping to one line at `md`.

Keep a sticky row to controls. Free text or a wrapped group inside one is counted as a single control-height line, and
the spacer will be wrong by whatever it really takes.

#### Content Writing Guidelines

| Guideline                   | Example                                                           |
|-----------------------------|-------------------------------------------------------------------|
| Lead with key point in bold | `<strong>Key point.</strong> Details follow.`                     |
| Use short sentences         | Max 15-20 words per sentence                                      |
| Avoid jargon                | "Motor Vehicle Record" not "MVR"                                  |
| Be specific                 | "Used for ticketing and mailings" not "Used for various purposes" |
| Answer "why"                | Users with ADHD need to understand purpose to stay engaged        |

---

## Layout Patterns

### Responsive Breakpoints

**PREFERRED:** Write for **mobile and desktop**, and let `lg:` carry the difference. That is still
the shape of almost every page in this app, and a layout that needs a third tier usually needs a
simpler layout instead.

Two things sit outside that rule, and both are documented below rather than left to judgement: the
point at which controls stop fitting side by side, and the HQ window's own screens.

#### Breakpoint Policy

| Breakpoint | Size     | Usage                     | Priority                                        |
|------------|----------|---------------------------|-------------------------------------------------|
| (none)     | < 1024px | Mobile/default styles     | **PREFERRED** - always start here               |
| `lg:`      | ≥ 1024px | Desktop styles            | **PREFERRED** - the structural fold             |
| `xl:`      | ≥ 1280px | Large desktop             | Optional refinements only                       |
| `sm:`      | 640px    | Field widths via `width:` | **AVOID** elsewhere - one sanctioned use        |
| `md:`      | 768px    | The phone/not-phone floor | **AVOID** - two sanctioned uses only, see below |

**`lg` is the structural fold.** Tables fold to cards, the sidebar drawer overlays, sticky button
rows go static. Always write it as `(width < theme(--breakpoint-lg))`, never `max-width: 1024px` —
both bounds are inclusive, so a `max-width` fold matches at exactly 1024px at the same moment `lg:`
does, and content carrying `hidden lg:table-cell` belongs to neither layout and renders nowhere.

#### Prefer content-driven adaptation to any breakpoint

Before reaching for a breakpoint at all, ask whether the content can answer the question itself. A
tablet is a real admin device in this app — an 820pt screen has room for two or three things per
line — but the width where that becomes true depends on the content, not the device.

```css
/* PREFERRED: the layout asks whether the next item fits */
.button-row { display: flex; flex-wrap: wrap; }

/* PREFERRED: a floor width, so short fields align and long ones take their own line */
.responsive-table tr > td { min-width: 11rem; }
```

This is how the responsive table fold packs fields into columns on a tablet and one-per-line on a
phone without naming either device (`tables.css`). It sizes itself, and it cannot be wrong about a
screen no one tested.

#### The two sanctioned uses of `md`

`md` is not a general-purpose breakpoint and must not be used for layout tiers, grid columns, or
show/hide. It marks exactly one fact: **below 768px, controls cannot sit side by side.**

1. **`.button-row` stacking** (`components/buttons.css`). Below `md` the row stacks each control
   onto its own line; from `md` up it wraps instead. This rule previously ran to `lg`, which stacked
   three buttons on an 820pt tablet that had room for all three.
2. **The sticky button-row spacer** (`.button-row-spacer`, `components/buttons.css`). The spacer
   reserves the height of the fixed row it stands in for, and that height changes when the row stops
   stacking, so it has the row's three states: one line per control below `md`, a single line from
   `md`, and `display: none` at `lg` where the row is static. The line count comes from
   `ButtonHelper#button_row`, which counts what it rendered.

Anything else wanting a tablet tier should use the content-driven patterns above.

#### The one sanctioned use of `sm`

Form field widths. `AppFormBuilder`'s `width:` option takes `w-full sm:w-48` and friends: full width on a phone so the
field cannot force a horizontal scroll, its measured width from 640px up so a tablet or desktop form does not stretch a
name field across the page. That is the only place `sm:` appears by design; anything else reaching for it should use
`lg:` or let the content decide.

#### The HQ shared-display tier

The HQ window is read in two scenes the `lg` fold does not cover: a tablet on a stand at the window,
and a large screen the shift crew reads together from several feet back. `components/hq-window.css`
adds one tier for the second case, scoped to `.hq-shell` and the HQ sidebar only.

| Width     | Treatment                                                                |
|-----------|--------------------------------------------------------------------------|
| ≥ 1800px  | `zoom: 1.15`; content column caps at `64rem`, prose at `68ch`             |
| ≥ 2400px  | `zoom: 1.35`                                                             |

Above 1800px the extra width is spent on legibility rather than line length — at 1920 the page was
1701px wide with 14.4px table cells and a 1454px reading line, which is simultaneously too small to
read at that distance and too long to track back to the start of. `zoom` rather than a per-element
type scale so type, spacing, icons, and the 36px touch floor all grow together and no element is
left behind. The threshold clears a 16" laptop's 1728pt default width; viewing distance is not
something CSS can ask about, so physical width is the honest proxy.

These rules are `@media screen` only — a print run must never inherit them.

**Examples:**

```erb
<%# Correct: Mobile-first with desktop breakpoint %>
<div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
  Content columns
</div>

<%# Correct: Stacked on mobile, side-by-side on desktop %>
<div class="flex flex-col lg:flex-row gap-4">
  <div class="w-full lg:w-1/2">Left</div>
  <div class="w-full lg:w-1/2">Right</div>
</div>

<%# Correct: Show/hide based on screen size %>
<div class="lg:hidden">Mobile only content</div>
<div class="hidden lg:block">Desktop only content</div>

<%# WRONG: md: as a layout tier. Use lg:, or let the content decide with flex-wrap %>
<div class="grid md:grid-cols-2">...</div>
<div class="md:hidden">...</div>
```

#### Progressive Grid Columns

For grids that need more columns on larger screens:

```erb
<%# Two tiers: mobile and desktop %>
<div class="grid grid-cols-2 lg:grid-cols-4 gap-4">...</div>

<%# Three tiers: mobile, desktop, large desktop %>
<div class="grid grid-cols-2 lg:grid-cols-4 xl:grid-cols-6 gap-4">...</div>
```

### Page Headers

All pages use the `hero_panel` component for consistent page headers (see Hero Panels section above for full
documentation).

**Standard pattern:**

```erb
<%= hero_panel icon: "icon-name", heading_level: :h1, id: "page-header" do |panel| %>
<% panel.title do %>Page Title<% end %>
<% panel.description do %>Page description<% end %>
<% end %>
```

### Year Selector

Year selectors are integrated into hero panels for pages that need year filtering:

```erb
<%= hero_panel icon: "calendar", heading_level: :h1, id: "schedule-header" do |panel| %>
<% panel.title do %>Schedule<% end %>
<% panel.year_selector year: @year, years: current_user.years_combined %>
<% end %>
```

**Behavior:**

- Desktop: Compact selector appears inline in header
- Mobile: Full selector appears below description
- Form auto-submits on change
- Uses semantic tokens for consistent styling

### Back Navigation

Back links are integrated into hero panels using the `back_to` method:

```erb
<%= hero_panel icon: "user", heading_level: :h1, id: "profile-header" do |panel| %>
<% panel.title do %>Edit Profile<% end %>
<% panel.back_to do %>
<%= back_to "Profile", me_profile_path %>
<% end %>
<% end %>
```

**Behavior:**

- Desktop: Appears on the far right of the header
- Mobile: Appears above the title
- Uses text link style with left arrow icon
- Muted color with hover state

### Responsive Columns

```erb
<%# Two columns on desktop, stacked on mobile %>
<div class="flex flex-col lg:flex-row gap-4">
  <div class="w-full lg:w-1/2">Left column</div>
  <div class="w-full lg:w-1/2">Right column</div>
</div>

<%# Grid layout %>
<div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
  <div>Column 1</div>
  <div>Column 2</div>
  <div>Column 3</div>
</div>
```

### Empty States

Always use the helper — never a hand-rolled dashed box:

```erb
<%= ui_empty_state "No items found." %>
<%= ui_empty_state "No messages yet.", icon: "envelope", icon_type: :regular %>
```

---

## Icon Usage

**Helper**: `IconHelper` (`app/helpers/icon_helper.rb`)

### Icon Policy

**CRITICAL:** Use only FontAwesome Free v7.1 icons via the `fa_icon` helper.

**CRITICAL:** The regular style draws only the icons in `lib/fontawesome/regular-icons.txt`. Font Awesome Free's
regular font has no glyph for any other name, so the browser draws a crossed box in its place. Pass `:solid` for any
icon not on the list: `fa_icon` raises in development and test when one is asked for in regular, its default style.
The list is generated from the font by `node bin/fontawesome_regular_icons.js`, never edited by hand.

**AVOID - Never do these:**

- Use FontAwesome Pro icons
- Create custom SVG icons
- Use inline SVG markup in views
- Use data URI SVGs (except for CSS background-image where FontAwesome icons cannot be used directly)

When SVG data URIs are unavoidable (e.g., CSS `background-image` for form controls), use the official FontAwesome icon
paths from Free v7.1. See `AppFormBuilder` for examples of properly sourced FontAwesome SVG paths.

### Basic Usage

```erb
<%# Regular style (default): draws only the icons in lib/fontawesome/regular-icons.txt %>
<%= fa_icon "user" %>

<%# Solid style %>
<%= fa_icon "user", :solid %>

<%# With size %>
<%= fa_icon "star", :solid, size: "lg" %>
<%= fa_icon "star", :solid, size: "2x" %>

<%# With margin -- for an icon beside text in ordinary markup only.
    Inside a button the gap is already there: .btn is a flex row with
    gap: .375rem, so a margin here adds a second space to the first. %>
<%= fa_icon "arrow-right", :solid, start: 2 %> <%# margin-start %>
<%= fa_icon "arrow-left", :solid, end: 2 %>   <%# margin-end %>

<%# With custom class %>
<%= fa_icon "check", :solid, class: "icon-success" %>
```

### Common Icons by Category

Most of these have no regular glyph and draw only with `:solid`. Check `lib/fontawesome/regular-icons.txt` before
leaving one in the regular style.

**Navigation:**

- `home`, `arrow-left`, `arrow-right`, `chevron-down`, `chevron-up`
- `bars` (hamburger menu), `times` (close)

**Actions:**

- `pen`, `trash`, `plus`, `minus`, `check`, `times`
- `download`, `upload`, `share`, `link`

**Status:**

- `circle-check` (success), `circle-exclamation` (warning)
- `triangle-exclamation` (danger), `circle-info` (info)
- `hourglass-half` (pending), `circle-xmark` (blocked)

**Objects:**

- `user`, `users`, `calendar`, `clock`, `envelope`
- `file`, `folder`, `image`, `camera`

---

## ADHD-Friendly Design Guidelines

The Clubhouse serves users with varying attention profiles. These guidelines are **CRITICAL** for accessibility.

### Visual Hierarchy

- **CRITICAL:** Use clear, consistent heading hierarchy (h1 > h2 > h3)
- **CRITICAL:** Ensure a single, clear primary action per view
- **PREFERRED:** Highlight the most important action on each screen
- **PREFERRED:** Group related information visually with cards and sections
- **PREFERRED:** Use whitespace to reduce cognitive load

### Content Structure

- **CRITICAL:** Lead with the key information (inverted pyramid style)
- **CRITICAL:** Keep paragraphs to 2-3 sentences maximum
- **PREFERRED:** Use bullet points and short paragraphs
- **PREFERRED:** Break long forms into logical sections with fieldsets
- **PREFERRED:** Provide clear progress indicators for multi-step processes

### Typography for Accessibility

- **CRITICAL:** Use `text-base` (0.9rem in this theme) as the minimum for body text
- **CRITICAL:** Sufficient contrast ratios (WCAG AA minimum)
- **PREFERRED:** Keep the theme's 1.2 body leading; add row padding for grouping instead of loosening line-height (DESIGN.md > Tight Leading Rule)
- **PREFERRED:** Clear visual distinction between headings and body text
- **AVOID:** Justified text alignment
- **AVOID:** `text-sm` for primary content (see Type Scale section)

### Interaction Design

- **CRITICAL:** Minimum 36px touch targets for all interactive elements
- **CRITICAL:** Support keyboard navigation throughout
- **PREFERRED:** Provide immediate feedback for user actions (toasts, inline validation)
- **PREFERRED:** Use clear, descriptive button labels
- **AVOID:** Time-sensitive interactions

### Reducing Distractions

- **CRITICAL:** Motion is functional only. The approved set: `animate-spin` loading spinners, the progress-bar pulse,
  `animate-pulse` on urgent badges, and the sidebar drill-down slide. All of it must honor `prefers-reduced-motion`
- **AVOID:** Decorative motion — hover lifts, entrance animations, parallax
- **AVOID:** Auto-playing media or carousels
- **AVOID:** Flashing or blinking content
- **PREFERRED:** Use muted colors for secondary information
- **PREFERRED:** Keep navigation consistent across pages
- **Exception:** Login page ambient animations are permitted but must respect `prefers-reduced-motion`

### Color and Contrast

- **CRITICAL:** Never rely on color alone to convey information
- **CRITICAL:** Use icons alongside colored status indicators
- **PREFERRED:** Ensure sufficient contrast in both light and dark modes
- **PREFERRED:** Test with color blindness simulators

---

## Page Layouts

Patterns 1–5 are the baseline every user-facing page under the `/me` namespace follows.
Pattern 6 is the admin records shape and applies to management sections outside `/me`.

### Layout Pattern Selection

**PREFERRED:** Use this decision tree to select the correct layout pattern:

| If the page...                     | Use Pattern        | Key Components                                           |
|------------------------------------|--------------------|----------------------------------------------------------|
| Shows overview with stats/progress | **Dashboard**      | hero_panel + stats + progress + quick actions + sections |
| Lists multiple items to browse     | **Directory/List** | hero_panel + optional scroll nav + item sections         |
| Shows detail for a single item     | **Detail**         | hero_panel + back_to + info sections                     |
| Collects user input                | **Form**           | hero_panel + back_to + ui_form + sticky buttons          |
| Manages many records in a few categories | **Records Management** | category index of `ui_drill_down_row` → per-category `filter_bar` + `ui_table` |
| Reads many records one at a time | **Review Pane** | sections of one-line links → the selected record's history in a sticky pane, its own Turbo frame |
| Doesn't fit above patterns         | **Special**        | hero_panel + tabs or custom layout                       |

### Pattern 1: Dashboard (Overview + Stats)

**When to use:** Main landing pages, schedule views, dashboards with metrics.

```erb
<%= hero_panel icon: "icon", heading_level: :h1 do |panel| %>
<% panel.title do %>Page Title<% end %>
<% panel.description do %>Description<% end %>
<% panel.year_selector year: @year, years: years %> <%# Optional %>
<% panel.progress completed: x, total: y %>
<% end %>

<%# Summary numbers live in the BODY, not the hero -- hero_stats needs an
    approved plan (Hero Panel Stats Approval Workflow). %>
<%= ui_stat_row do %>
  <%= ui_stat_box @count.to_s, "Label" %>
  <%= ui_stat_box @urgent.to_s, "Urgent", variant: :warning %>
<% end %>

<div class="mb-4">
<%= button_link "Primary Action", :primary, path %>
</div>

<%= ui_section "Section Title" do %>
Content...
<% end %>
```

**Existing pages:** Dashboard, Schedule, Timesheet Dashboard, Tickets, Awards

### Pattern 2: Directory/List

**When to use:** Browsing collections, directories, message lists, agreement lists.

```erb
<%= hero_panel icon: "icon", heading_level: :h1 do |panel| %>
<% panel.title do %>List Title<% end %>
<% panel.description do %>Purpose<% end %>
<% end %>

<%= dropdown_scroll_list @items %> <%# Optional quick nav %>

<% @items.each do |item| %>
<%= ui_section item.title, id: "item-#{item.id}" do %>
    Item content...
<% end %>
<% end %>
```

Its links are plain fragments (`data-turbo="false"`): Turbo would treat each as a full
visit of the same URL, refetching the page and dropping any unapplied filter text.

**Existing pages:** Directory, Announcements, Agreements, Messages

### Pattern 3: Detail

**When to use:** Viewing a single record, profile pages, history views.

```erb
<%= hero_panel icon: "icon", heading_level: :h1 do |panel| %>
<% panel.title do %>Detail Title<% end %>
<% panel.description do %>Context<% end %>
<% panel.back_to do %>
<%= back_to "Back", path %>
<% end %>
<% end %>

<%= ui_section "Information Section" do %>
Detailed content...
<% end %>
```

**Existing pages:** Profile, Mentoring, Work History, Event Summary, Agreements Show

### Pattern 4: Form (New/Edit)

**When to use:** Any page collecting user input.

```erb
<%= hero_panel icon: "icon", heading_level: :h1 do |panel| %>
<% panel.title do %>Form Title<% end %>
<% panel.back_to do %>
<%= back_to "Back", path %>
<% end %>
<% end %>

<%= ui_form(@object, submit_path) do |f| %>
<%= ui_section "Section", icon: "icon", icon_type: :solid do %>
    <dl class="instruction-list mb-3">
      <dt>Why do we need this?</dt>
      <dd>Clear explanation.</dd>
    </dl>
<%= f.text_field :field, label: "Field" %>
<% end %>

<%= button_row do %>
<%= f.submit "Save" %>
<%= cancel_link back_path %>
<% end %>
<% end %>
```

**Existing pages:** Photo upload/crop, Language forms, Vehicle forms, Profile edits, Password change

### Pattern 5: Special

**When to use:** Tabbed content, confirmation flows, unique layouts.

```erb
<%= hero_panel icon: "icon", heading_level: :h1 do |panel| %>
<% panel.title do %>Special Page<% end %>
<% end %>

<%= tab_navigation "tabs-id", :first_tab do |tabs| %>
<% tabs.pane "Tab 1", :first_tab do %>Content<% end %>
<% tabs.pane "Tab 2", :second_tab do %>Content<% end %>
<% end %>
```

**Existing pages:** Event Info, Timesheet Final Confirmation, Vehicle MVR Submit

### Pattern 6: Records Management (Drill-Down)

**When to use:** an admin section managing many records of one kind that fall into a small,
stable set of categories — assets by type, slots by position, sign-ups by position. Two
levels; do not put both on one page.

**Do not use** when there is no natural category, when a category holds only a handful of
records, or when the reader's real question spans categories ("who still has gear checked
out?"). Those are flat reports — use a single filtered `ui_table` page instead.

**Level 1 — category index.** No filter bar, no table. Just the categories and how big each
one is.

```erb
<%= hero_panel icon: "icon", heading_level: :h1, id: "page-header",
               title: "Section Title",
               description: "Browse by <category> to view, filter, and export its records." do |panel| %>
  <% if @available_years.any? %>
    <% panel.year_selector year: @year, years: @available_years %>
  <% end %>
<% end %>

<div class="my-4">
  <%= button_row do %>
    <%= button_link "Add Record", :primary, new_path(year: @year), icon: "plus", icon_type: :solid %>
    <%= button_link "Export CSV", :secondary, index_path(year: @year, format: :csv),
                    icon: "file-csv", icon_type: :solid %>
  <% end %>
</div>

<%# present?, not any?: a nullable category column makes this [nil], and [nil].any? is false. %>
<% if @categories.present? %>
  <div class="text-lg">
    Showing <%= pluralize @categories.size, "category" %> with <%= pluralize @total, "record" %>
  </div>
  <div class="lg:w-3/4">
    <% @categories.each do |category| %>
      <% flagged = @flagged_counts[category].to_i %>
      <%= ui_drill_down_row category_path(category, year: @year), category_label(category),
                            meta: pluralize(@counts[category], "record"),
                            badges: (ui_badge("#{flagged} expired", :warning, size: "base") if flagged.positive?) %>
    <% end %>
  </div>
<% else %>
  <%= ui_empty_state "No records have been added yet.", icon: "icon", icon_type: :solid %>
<% end %>
```

**Level 2 — category page.**

```erb
<%= hero_panel icon: "icon", heading_level: :h1, id: "page-category-header",
               title: "#{@year} #{category_label(@category)} Records",
               description: "Review these records, filter them, and export them as CSV.",
               back_to: ["Section Title", index_path(year: @year)] %>

<%= ui_stat_row do %>
  <%= ui_stat_box @total_count.to_s, "Records" %>
  <%= ui_stat_box @expired_count.to_s, "Expired", variant: :warning %>
<% end %>

<div class="my-4">
  <%= button_row do %>
    <%= button_link "Add Record", :primary, new_path(category: @category, year: @year),
                    icon: "plus", icon_type: :solid %>
  <% end %>
</div>

<% if @total_count.positive? %>
  <%# The export rides the bar that scopes it -- never a button_row of its own. %>
  <%= filter_bar id: "record-filters",
                 chips: record_filter_chips(@filter_params, @category, @year),
                 clear_url: category_path(@category, year: @year),
                 count: "Showing #{@records.size} of #{pluralize(@total_count, "record")}",
                 actions: (button_link("Export CSV", :secondary,
                                       category_path(@category, **@index_params, format: :csv),
                                       icon: "file-csv", icon_type: :solid) if @records.any?),
                 url: category_path(@category) do |f| %>
    <%= hidden_field_tag :year, @year %>
    <%# ...selects for every filter EXCEPT the category... %>
  <% end %>
<% end %>

<% if @records.any? %>
  <%= ui_table do |t| %><%# no category column -- the category is the page %><% end %>
<% elsif @total_count.positive? %>
  <%= ui_empty_state "No records match the current filters.", icon: "filter", icon_type: :solid %>
<% else %>
  <%= ui_empty_state "No #{category_label(@category).downcase} records were found for #{@year}.",
                     icon: "icon", icon_type: :solid %>
<% end %>
```

**Rules:**

- **The category is the page, never a filter.** It gets no select on level 2 and no
  removable chip — a chip that drops it has nowhere to land. Build every chip URL against
  the category page so removing one keeps both the year and the category.
- **Drop the category column** from the level-2 table. Every row has the same value.
- **Level 1 gets no filter bar.** Filters narrow rows, and there are no rows here.
- **Counts on level 1 are plain text**, not stat boxes: one `text-lg` summary line, plus
  `meta:` on each row. Constrain the row list to `lg:w-3/4`.
- **Badge only the exception count** on a row (`N expired`, `N inactive`), `size: "base"`,
  and omit it entirely at zero. A badge on every row is noise.
- **Level-2 totals describe the category, not the filtered view** — `filter_bar count:`
  already reports the filtered slice as "Showing X of Y".
- **The export follows the filters.** Level 1 has no bar, so its Export CSV sits in the
  `button_row` beside Add Record. Level 2 has one, so its export moves into
  `filter_bar actions:` and that `button_row` keeps only Add Record.
- **Two empty states on level 2**, and they say different things: filters matched nothing
  vs. the category is empty for this year. One message for both strands the reader.
- **Return links follow the category.** Detail, edit, and delete all come back to the
  category page the reader came from with its filters intact, not to level 1. Resolve the
  path from the record's own category so a create lands on the category it created.

**Traps:**

- A nullable category column makes level 1 crash: `ui_drill_down_row` raises on a blank
  title, and `[nil].any?` is `false`, so the bucket silently vanishes. Give blank its own
  label and URL sentinel, and guard the list with `present?`.
- A finder that skips blank filter values returns **every** category when handed a blank
  one. Narrow the blank bucket explicitly.
- Adding the level-2 action to the controller does not gate it. Add it to the
  `authorize_ability ... only:` list in the same edit.

**Existing pages:** Asset Inventory (`asset-management/records`), Slots
(`scheduling/slots`), Available Sign-Ups, Position Credits, Swag

> Every one of these carries its level-2 totals in a body `ui_stat_row`, as shown above.
> Nothing in the app puts drill-down totals in the hero any more — see
> [Hero Panel Stats Approval Workflow](#hero-panel-stats-approval-workflow) in the approval workflow.

### Pattern 7: Review Pane (List + History)

**When to use:** a reviewer reads many records one at a time and acts on each — a
coordinator reading intake histories and filing notes, a mentor reviewing a season's
class. One line per record on the left; the selected record's whole history on the
right, so the list never moves while the pane is read. Approved 2026-10-14 for the three
Unified Flagging pages.

**Do not use** when each record has only a line's worth of detail (that is a `ui_table`
or a card list), or when the reader acts on records in bulk (a `bulk_select` table).

#### Shape

```erb
<% pane = render "common/unified_flagging/review_pane", summary: @selected, history: @history, year: @year %>
<%= render layout: "common/unified_flagging/review_workspace", locals: { pane: } do %>
  <%= ui_section meta[:title], icon: meta[:icon], icon_type: :solid,
                 badge: rows.size.to_s, badge_color: meta[:badge_color] do %>
    <%= render "common/unified_flagging/review_list", rows: rows, year: @year, selected_id: @selected_id %>
  <% end %>
<% end %>
```

The pane holds its own `turbo_frame_tag "uf-pane"` with `data-turbo-action="advance"` and
`target: "_top"`, and each line is a link to the same page with `?person=` (the active filters
kept) that names that frame with `data-turbo-frame`. Selecting a line fetches the pane alone
(`UnifiedFlaggingConcern#render_review_pane` answers a `Turbo-Frame: uf-pane` request with the
partial, no list and no layout), swaps only the pane, and lands the selection in the address bar
and in history. The list is never re-rendered, so the link the reader activated keeps focus.
The server renders the selection, only among the rows shown
(`UnifiedFlaggingConcern#review_selection`). `review_pane_controller` moves the line's
`aria-current` to whoever the pane shows (the line states in `components/review-pane.css` key on
it) and, below `lg`, parks the pane under that line; from `lg` up the pane is sticky in the
second column, capped so a long history scrolls inside it.

The generic pieces are the frame shape, `review_pane_controller` and the `review-pane` and
`review-line` classes. The partials are the intake pipeline's (`summary:` hashes from `Intake`); a second
kind of record gets its own line and pane partials in the same shape.

#### Rules

- **One line per record**: name, what stands out, one coloured chip. Status, former
  handles, mentors and the history wait in the pane. A line that wraps on a laptop has too
  much on it.
- **The pane's header is the record's own**: the shared `_name_line` with the chips, the
  gray `_signal_line`, the Personnel warning when a flag is raised, the Add-note buttons
  (`_note_buttons`), then `_history`, its team sections in the gray line's team order. A
  flagged person's line is tinted red (`review-line-flagged`) unless selected.
  A read-only page renders no buttons and no Edit or Delete, from
  `unified_flagging_writable_teams`.
- **Select only what is on the page**: a `?person=` the filters hide, a stale id or an
  array-shaped param selects nothing, and the pane shows its empty state
  (`ui_empty_state "Select a name to read their history."`).
- **The controller keeps the line in view**: on connect (a full load, a redirect back from a
  note form, a Back restore) it scrolls the selected line to the top, since this layout scrolls
  an inner element whose position neither a load nor Turbo's snapshot keeps. Below `lg`, moving
  the pane from above the new line would lift that line out of view, so it scrolls the line
  back in. No `scroll-to-element` marker.
- **A page with its own `#index` answers the pane itself**: call `review_selection` first, then
  `return render_review_pane(**extras) if review_pane_request?` before building the list,
  passing whatever the page adds to the pane (Post Season's `PANE_EXTRAS`).
- **Return with `?person=`, never `#person-N`**: a fragment is dropped after a form
  submission (Returning the Reader to One Record). The note controller's `ORIGIN_RETURNS`
  marks these pages `selects: true`.
- **Explain it in the card**: the `_review_legend` pair ("How do I read someone's
  history?") joins the page's About This Report list beside the lead and rank legends.

#### Traps

- No frame may wrap the pane's. Turbo hands a method link (the note Delete) to the nearest
  frame without a target, and an outer one takes it as a frame submission even when the
  pane's own frame targets `_top`, throwing away the redirect's flash.
- `active_links_controller` restamps `aria-current` from an exact query-string match, which a
  hand-typed URL (no year, another order) never makes. It skips any link that names a frame
  other than `_top`, which is what leaves the lines to this pattern.
- A frame load is not a page visit: `ApplicationController#track_page_visit` skips frame
  requests, or every name opened would bump the mega menu's Recent list.
- Never move the pane while its frame is loading. Moving a `<turbo-frame>` disconnects it, which
  cancels its request: before the render Turbo fetches the `src` again, and after it the page
  visit Turbo makes of an advancing frame visit loses the response, with the snapshot a later
  Back would restore. The controller marks the line on `turbo:before-frame-render` and moves the
  pane on `turbo:load`.
- Chrome's scroll anchoring hides the below-`lg` jump that Safari shows; the system test turns
  it off (`overflow-anchor: none`) to see what an iPhone sees.
- Two pages sharing the workspace wrapper are two occurrences of its class strings to the
  CSS ratchet, which is why the wrapper, the list, the name line and the gray line are
  partials rather than markup repeated per page.
- The pane's frame is `uf-pane`; `uf-frame-<id>` belongs to the Convert Prospectives table's
  lazy detail frame, which `#detail` answers.

**Existing pages:** VC › Unified Flagging, In-Person Training › Unified Flagging (read-only),
People › Unified Flagging (read-only; anyone the teams wrote about in a year, any status),
Mentoring › Post Season Summary, Potential Alphas and Alpha Status (read-only) —
`app/views/common/unified_flagging/_review_workspace.html.erb` and its siblings; the controller
and the partial locals are in `docs/UI-COMPONENTS.md` › review-pane.

### Common Layout Elements

**Quick Actions:**

```erb
<div class="mb-4">
<%= button_link "Primary", :primary, path, icon: "icon" %>
<%= button_link "Secondary", :secondary, path %>
</div>
```

**Two-Column Responsive:**

```erb
<div class="flex flex-col lg:flex-row gap-4">
  <%= ui_section "Left" do %>...<% end %>
  <%= ui_section "Right" do %>...<% end %>
</div>
```

**ADHD-Friendly Q&A Display:**

```erb
<dl class="instruction-list">
  <dt>Question?</dt>
  <dd>Clear, concise answer.</dd>
</dl>
```

**Collapsible Content:** Use `data-controller="read-more"` for expandable sections.

**Status Indicators:** Always combine borders, backgrounds, badges, AND icons. **CRITICAL:** Never rely on color alone.

---

## Language & Content Guidelines

### Audience

All interface text should be written for a mixed audience of ADHD users and typical web users. Content must be:

- Concise and scannable
- Clear and unambiguous
- Action-oriented where appropriate

### Terminology Rules

**CRITICAL - Never use these terms:**

- "work" or "working"
- "job" (in the employment sense)
- "employee" or "staff"

**PREFERRED alternatives:**

- "volunteer efforts" / "volunteering"
- "ranger" (as verb or noun)
- "rangering"
- "shift" / "shifts"
- "service" / "service hours"
- "volunteer" / "volunteers"

**Examples:**

- ❌ "Your work hours" → ✅ "Your volunteer hours"
- ❌ "Working shifts" → ✅ "Scheduled shifts"
- ❌ "Work history" → ✅ "Volunteer history" or "Service history" (except the Work History pages, below)

### Exception: genuinely paid positions

The ban exists because calling a volunteer an employee is wrong. Where the
relationship **is** employment, the employment word is accurate and is
**preferred** — "volunteer" would be the error.

This covers payroll and Paycom surfaces only:

| Context | Use |
|---------|-----|
| A position's paycode (paid positions draw payroll) | "Paycom employee code" |
| A person's Paycom identifier | "Paycom Employee ID" |
| Payroll hour adjustments | "employee", "payroll" as needed |

The exception is narrow. It does **not** license "work", "working", or "job"
anywhere, and it does not extend to shift, schedule, timesheet, or service-hour
copy — those describe volunteering even on a paid position.

### Exception: proper names

A named thing keeps its name. "Staff Credential" and "Staff Credentialing" are ticket
and process names, printed as-is wherever they appear. The ban is on describing
volunteers as staff, not on quoting a product name.

### Exception: the Work History pages

By the owner's ruling (2026-10-06), the page of a person's hours by position and
event year is named **Work History**, on purpose, against the ban above:

- `/me/timesheet/work-history` (`Me::WorkHistoryController`), and its button and
  card on Me › Timesheet
- `/person/:id/work-history` (`Person::WorkHistoryController`) and its Person menu item
- the drill-down pages both share (`app/views/common/work_history/`), whose back
  link reads "Work History"
- the ART Training Session trainee dialog
  (`Training::Sessions::WorkHistoriesController`) and its button on the trainee card

The exception is the name only. It does not license "work" in those pages' body
copy or anywhere else.

### Status Values

**CRITICAL — never `.titleize` a person's status.** `person.status` already
holds the words the Clubhouse uses (`active`, `inactive extension`, `past
prospective`). Print the value itself wherever it appears: badges, table cells,
filter selects, chips, CSV cells, preview messages. Title-casing it on one page
and not on the next makes one status look like two, and a chip that re-cases
what its own select spelled disagrees with the control that set it.

```erb
<%= t.cell row.status %>                   <%# ✅ %>
<%= t.cell row.status.titleize %>          <%# ❌ %>
```

A status stored as a code rather than a word — badge status is `in_prep`,
`do_not_print` — is the exception: print it through its label map
(`Bmid::ManageHelper::STATUS_LABELS.fetch(status, status)`), never through
`titleize`, which would invent a spelling no control uses.

### Writing Style

- Use active voice
- Address the user directly ("You have 3 shifts scheduled")
- Be specific over vague ("Save profile" not "Submit")
- Use Title Case for every heading and button label — see [Title Case](#title-case) below
- Avoid jargon unless widely understood by Rangers

### Title Case

**CRITICAL:** Every heading and every button label is Title Case. That covers
`hero_panel` titles, `ui_section` titles, `ui_card` titles, `ui_callout_box`,
`ui_alert_banner` and modal `title:` strings, table column headers, tab labels,
and all `ButtonHelper` labels — every string a reader *scans as a label* rather
than *reads as prose*.

Capitalize every word except articles (`a`, `an`, `the`), coordinating
conjunctions (`and`, `but`, `or`, `nor`, `for`, `so`, `yet`) and prepositions of
four letters or fewer (`in`, `on`, `to`, `for`, `with`, `from`) — unless the
word is first or last.

| Wrong — sentence case | Right |
|---|---|
| "Adjust your choices" | "Adjust Your Choices" |
| "Before you save" | "Before You Save" |
| "Asset check in / out history" | "Asset Check In / Out History" |
| "Claim your event ticket first" | "Claim Your Event Ticket First" |
| "All claimed items" | "All Claimed Items" |

**A question is not an exemption.** "All set?" and "Accidentally ended the
shift?" read like prose because they *are* prose — which is the signal that they
belong in the body, not in a heading. Name the thing in the heading and move the
question down:

```erb
<%# WRONG -- the heading is a sentence %>
<%= ui_section "Accidentally ended the shift?" do %>
  <p>Ask HQ to reopen it.</p>
<% end %>

<%# RIGHT -- the heading is a label; the question is body copy %>
<%= ui_section "Reopening a Shift" do %>
  <p>Accidentally ended the shift? Ask HQ to reopen it.</p>
<% end %>
```

**Exceptions — text that keeps the casing it already has:**

- Person statuses, printed exactly as stored (`inactive extension`) — see
  *Status Values Are Shown As Stored* above
- Proper and product names ("Staff Credential", "Motor Vehicle Record")
- Interpolated data — `"#{@training.title} Sessions"`; the interpolated half
  carries its own casing
- Body copy, help text, form hints, error messages, empty-state sentences and
  `panel.description` — these are prose and stay sentence case

### One Verb per Action

**CRITICAL:** An action gets the same verb on every page (owner's ruling, 2026-10-23).

| Action | Say | Never |
|---|---|---|
| Open the form that creates a record | "Add [Entity]" | "New [Entity]", "Create [Entity]" |
| Submit that form, new or edit | "Save [Entity]" | "Update [Entity]", "Create [Entity]", "Submit" |
| Get rid of a record | "Delete [Entity]" | "Remove", "Trash", "Destroy" |
| Take something out of a group | "Remove from [Group]" | "Delete" |
| Leave the page | "Back to [Page]" | a bare "Back" |

**Delete or Remove?** Ask whether the thing still exists afterwards. A deleted passkey is gone:
"Delete Passkey". A shift you leave is still on the schedule: "Remove from Schedule". A submit
that does more than store the record keeps its own verb: "Send Message", "Claim Ticket",
"Create Account".

### Flash Messages

**CRITICAL — the type matches the outcome.** A failure is `error:` (or `alert:`), never
`success:`. A success message is the thing, then what happened to it: `<Thing> <past participle>.`

| Wrong | Right |
|---|---|
| "The note has been successfully added." | "Note added." |
| "Swag was deleted." | "Swag deleted." |
| "Deleted 3 bug reports." | "3 bug reports deleted." |
| "Agreement has been signed. Thank you!" | "Agreement signed." |

No "successfully", no "has been", no exclamation mark. Name the thing as the page names it
("Timesheet entry #123 deleted."). Add a second sentence only for what the reader needs next. An
error flash follows [Validation and Error Messages](#validation-and-error-messages).

### Confirm Dialogs

Ask with the action, then say what follows from it: `<Verb> <thing>?` plus a sentence on whether
it can be undone. "Delete this note? This cannot be undone.", not "Are you sure you want to delete
this note?" or "Really delete this note?". `delete_button` makes the confirm button red; a dialog
built from `confirm_modal` passes `variant: :error`.

### Validation and Error Messages

`config/locales/en.yml` sets `errors.format: "%{message}"`, so Rails never puts the field name in
front of a message, and the form's error summary shows the message on its own. Write every
`errors.add` and `message:` string as a whole sentence: sentence case, a period at the end, and the
field named in the reader's words, never by its column name.

```ruby
errors.add(:left_on, "must be on or after joined_on date")                         # ❌
errors.add(:left_on, "The left on date must be on or after the joined on date.")  # ✅
```

Rails' own messages already do this: `config/locales/en.yml` rewrites them as `"%{attribute} can't
be blank."` and names awkward columns under `activerecord.attributes`. A page that calls a field
something else builds the message with `ValidationMessage.naming(error, "Email address")`. Messages
end in a period, so join them with a space (`full_messages.join(" ")`), never `", "` or
`to_sentence`. A message that needs `%{attribute}` inside a validator that adds strings as written
(phonelib) is a locale key: `message: :phone_invalid`.

### Punctuation and Spelling

- **Ellipsis** is one character, `…`, never three periods, placeholders included.
- **Noun with a hyphen, verb in two words:** "your sign-up", "sign up for a shift"; "the check-in",
  "check in the radio". Never "signup" or "checkin".
- **"un-submit"**, not "unsubmit". **An empty value** prints "—".
- **No exclamation marks** in flash messages or error messages.

### Dates, Times and Prices

**CRITICAL:** Format dates with `DateTimeHelper`, never `strftime` in a view.

| Showing | Format |
|---|---|
| Date and time | `Thu Jan 8 @ 14:30` |
| Date and time in another year | `Thu Jan 8, 2026 @ 14:30` |
| Date | `Jan 8, 2026` |
| Day label | `Thu Jan 8` |
| In running copy | `January 8`, `January 8, 2026` |
| Long form | `Thursday, January 8, 2026` |
| A chip with no room | `Thu 1/8 14:30` |
| Admin logs, CSV, form field values | `2026-01-08 14:30:00`, `2026-01-08` |

Never zero-pad the day. The year goes after the date, before the time. 24-hour clock everywhere. A
timestamp already written into stored text (a record's comments column) keeps its format.

**Prices:** `dollars(amount)` prints `$40`, or `$12.50` when there are cents. Never `"%g"`, and never
a `$` glued to `number_with_delimiter`.


---

## Anti-Patterns to Avoid

**AVOID** all patterns listed below. These cause consistency, accessibility, or brand issues.

### Generic AI Aesthetics

- Overused font families (Inter, Roboto, Arial as primary fonts)
- Cliched color schemes (purple gradients on white backgrounds)
- Hand-picked blue CTAs (`bg-blue-600`, `btn-info`) instead of the brand token — the brand *is* a blue
  (Signal Blue), so a raw blue reads as an off-key copy of it. Use `bg-primary` / `btn-primary`

### Technical Anti-Patterns

- Inline Tailwind classes when helpers exist
- Direct color values when semantic tokens are available
- Raw HTML when ERB helpers provide the same functionality
- Inconsistent dark mode support
- Missing ARIA attributes on interactive elements

### Content Anti-Patterns

- Walls of text without visual breaks
- Ambiguous button labels ("Click here", "Submit")
- Missing error messages or unclear validation feedback
- Inconsistent terminology across pages
- Using the word "work" or its variants

### Interface Density Anti-Patterns

- Excessive vertical whitespace creating unnecessary scrolling
- Decorative padding that doesn't serve hierarchy or grouping purposes
- Sparse layouts that display minimal information per screen
- Missing help section links at top of pages with FAQ content below
- Unanchored help sections without top-of-page navigation

### Color Usage Anti-Patterns

- Using multiple accent colors for visual variety
- Colored backgrounds for decoration rather than semantic purpose
- Colorful borders or gradients without status meaning
- Colored text for emphasis (use weight/size instead)
- "Rainbow" interfaces with too many competing colors
- Relying on color alone to convey information (always pair with icons/text)

### Workflow Anti-Patterns

- Implementing new UI components not in the design guide without user approval
- Creating custom color styling without user approval
- Failing to implement approved components as reusable helpers
- Missing documentation updates after adding new components or styling
- Inline component code instead of helper abstraction

---

## Key Files Reference

### Core Styling

**Main File:**

- `app/assets/tailwind/application.css` - Central import file with theme configuration

**Organized Style Files:**

- `app/assets/stylesheets/base.css` - Base element styles (turbo-frame, main, p, links)
- `app/assets/stylesheets/utilities.css` - Index file importing utility components
- `app/assets/stylesheets/components.css` - Index file importing component styles
- `app/assets/stylesheets/accessibility.css` - Accessibility features (scrollbars, reduced-motion, ADHD patterns)
- `app/assets/stylesheets/login.css` - Login page specific styles
- `app/assets/stylesheets/fontawesome-subset.css` - FontAwesome icon subset, generated by `bin/rails fontawesome:subset`
- `app/assets/stylesheets/vanilla-calendar-pro.css` - Calendar component styles

**Component Files (in `app/assets/stylesheets/components/`):**

- `autocomplete.css` - Autocomplete search functionality
- `badges.css` - Badge component utilities
- `boxes.css` - Box components and theme variants
- `buttons.css` - Button system with variants and sizes
- `callsign-list.css` - Multi-column callsign lists
- `cards.css` - Card container patterns
- `dropdowns.css` - Dropdown menu system
- `empty-state.css` - Empty state pattern
- `flex-patterns.css` - Common flex patterns
- `forms.css` - Form fieldset styling
- `hero-panel.css` - Hero panel for /me pages
- `hq-window.css` - HQ window device tiers (tablet summary strip, shared-display scale)
- `icons.css` - Status icon colors
- `messages.css` - Messages interface system
- `modals.css` - Modal component utilities
- `sidebar.css` - Sidebar/drawer system with theme variants
- `tables.css` - Table system utilities
- `text-colors.css` - Stone text color system
- `toasts.css` - Toast/notification system

### Helper Files

- `app/helpers/button_helper.rb` - Button components
- `app/helpers/modal_helper.rb` - Modal dialogs
- `app/helpers/ui_components/notice_box_helper.rb` - Callout boxes, alert banners, and empty states
- `app/helpers/ui_components/toast_helper.rb` - Toasts
- `app/helpers/tabs_helper.rb` - Tab navigation
- `app/helpers/table_helper.rb` - Standard tables
- `app/helpers/sidebar_helper.rb` - Sidebar navigation
- `app/helpers/navigation_helper.rb` - Navigation dropdown menus
- `app/helpers/icon_helper.rb` - Icons
- `app/helpers/ui_components/badge_helper.rb` - Badges
- `app/helpers/form_helper.rb` - Form builder and form components
- `app/helpers/ui_components/*.rb` - UI component helpers

### JavaScript Controllers

- `app/javascript/controllers/theme_controller.js` - Dark mode toggle
- `app/javascript/controllers/modal_controller.js` - Modal behavior
- `app/javascript/controllers/tabs_controller.js` - Tab switching
- `app/javascript/controllers/toast_controller.js` - Toast auto-dismiss

### Layout

- `app/views/layouts/application.html.erb` - Main layout template

---

## Quick Reference (LLM Cheat Sheet)

This section provides a condensed reference for common decisions. Use this for quick verification before implementing.

### Critical Rules (Must Follow)

| Rule              | Correct                                     | Wrong                                    |
|-------------------|---------------------------------------------|------------------------------------------|
| Body text size    | `text-base` (0.9rem on 1.2 leading)         | `text-sm` or `text-xs` for body          |
| Breakpoints       | `lg:` for desktop; `flex-wrap` in between; `sm:` only in field `width:` | `md:` as a layout tier |
| Icons             | FontAwesome Free 7.1                        | Pro icons, custom SVGs                   |
| Colors            | Semantic tokens (`text-body`, `bg-primary`) | Direct values (`text-gray-700`)          |
| Buttons           | Use `ButtonHelper` methods                  | Raw HTML buttons                         |
| Forms             | Use `AppFormBuilder` / `ui_form`            | Raw `form_with` without builder          |
| Dark mode         | Semantic tokens (re-resolve per theme)      | Light-only styling; `dark:` pairs on raw colors in markup |
| Touch targets     | Minimum 36px                                | Smaller interactive areas                |
| Interface density | Compact layouts, minimize scrolling         | Excessive whitespace, decorative padding |
| Color usage       | Neutral dominance, semantic color only      | Colorful decoration, busy color schemes  |
| Help sections     | Link from top with `#anchor`                | Help content without top-of-page link    |
| New components    | Get approval, implement as helper, document | Implement without approval               |
| New color styling | Get approval, DRY with custom CSS, document | Implement without approval               |
| Summary stats     | `ui_stat_row` of `ui_stat_box` in the main body | `panel.hero_stats` without an approved plan |
| Table exports     | `filter_bar actions:` when the page has a filter bar | An Export `button_row` above or below the bar |
| Hero description  | One sentence on what the page does          | Paragraphs or instructions in the hero   |
| Styling           | Tailwind + DaisyUI utilities; component CSS in `components/<name>.css` only when utilities can't express it | Inline styles, scoped CSS, ad-hoc CSS outside `components/` |

### Typography Quick Reference

| Element        | Size                   | Weight          |
|----------------|------------------------|-----------------|
| Page titles    | `text-2xl`             | `font-semibold` |
| Section titles | `text-base lg:text-lg` | `font-medium`   |
| Form legends   | `text-lg`              | `font-semibold` |
| Body text      | `text-base`            | `font-normal`   |
| Form labels    | `text-base`            | `font-medium`   |
| Help text      | `text-sm`              | `font-normal`   |
| Badges         | `text-xs` default; `size: "sm"`/`"base"` | daisyUI `badge` |

### Component Helper Quick Reference

| Need                      | Helper           | Example                                                 |
|---------------------------|------------------|---------------------------------------------------------|
| Link as button            | `button_link`    | `button_link "Save", :primary, path`                    |
| Form submit               | `submit_button`  | `submit_button "Save"`                                  |
| Cancel action             | `cancel_button`  | `cancel_button back_path`                               |
| Delete with confirm       | `delete_button`  | `delete_button path`                                    |
| Page header               | `hero_panel`     | See Hero Panels section                                 |
| Card container            | `ui_card`        | `ui_card { content }`                                   |
| Accent card (left border) | `ui_accent_card` | `ui_accent_card "Title", variant: :success { content }` |
| Section box               | `ui_section`     | `ui_section "Title" { content }`                        |
| Data table                | `ui_table`       | See Tables section                                      |
| Alert message             | `ui_callout_box` | `ui_callout_box :warning { msg }`                       |
| Alert with left border    | `ui_callout_box` | `ui_callout_box :error, accent: true { msg }`           |
| Status badge              | `ui_badge`       | `ui_badge "New", :primary`                              |
| Badge with icon           | `ui_badge`       | `ui_badge "Done", :success, icon: "check"`              |
| Stat display              | `ui_stat_box`    | `ui_stat_box "95%", "Complete", variant: :success`      |
| Empty state               | `ui_empty_state` | `ui_empty_state "No items."`                            |
| Walk a search's matches   | `ui_match_stepper` | `ui_match_stepper "search-matches", label:, current:, total:` |
| Credit rate over time     | `credit_timeline_chart` | `credit_timeline_chart @timeline`               |
| HQ shifts over a day      | `hq_forecast_gantt` | `hq_forecast_gantt @report, day`                    |

### Breakpoint Decision Tree

```
Is it mobile-specific styling?
  → Use no prefix (default)

Is it desktop-specific styling?
  → Use `lg:` prefix

Does it need to adapt somewhere between the two?
  → Let the content decide: flex-wrap, or a min-width floor on the items.
    No breakpoint. This is how the table fold packs fields on a tablet.

Is it a form field's width?
  → `w-full sm:w-48` via the builder's `width:` option — the one sanctioned `sm:` use.

Is it tablet-specific styling anyway?
  → Almost certainly DON'T. `md:` is reserved for the phone/not-phone floor
    (.button-row stacking and its sticky spacer) and nothing else.

Is it the HQ window on a big shared screen?
  → Already handled in components/hq-window.css at 1800px / 2400px.
    Don't add a second tier for it.
```

### Color Token Quick Reference

| Need               | Light Token                                           | Purpose               |
|--------------------|-------------------------------------------------------|-----------------------|
| Primary text       | `text-body`                                           | Body content          |
| Headings           | `text-heading`                                        | Titles, emphasis      |
| Muted text         | `text-stone-muted`                                    | Secondary info        |
| Success            | `text-success`                                        | Positive status       |
| Warning            | `text-warning`                                        | Caution status        |
| Danger             | `text-error`                                          | Error/negative status |
| Page/card surface  | `bg-base-100`                                         | Page and card backgrounds |
| Brand background   | `bg-primary`                                          | CTAs, emphasis        |
| Soft alert         | `bg-success/10`, `bg-warning/10`, `bg-error/10`       | Alert backgrounds     |

### Terminology Quick Reference

| Never Use       | Use Instead                        |
|-----------------|------------------------------------|
| work, working   | volunteer, volunteering, rangering |
| job             | shift, position, role              |
| employee, staff | volunteer, ranger                  |
| work hours      | volunteer hours, service hours     |
| work history    | volunteer history, service history (except [Work History](#exception-the-work-history-pages)) |

Exception: on payroll and Paycom surfaces "employee" is the accurate word and is
preferred — see [Language & Content Guidelines](#language--content-guidelines).

### Page Layout Decision Tree

```
What type of page is this?

Dashboard/Overview with stats?
  → Hero panel + stats + progress + quick actions + sections
  
List/Directory page?
  → Hero panel + optional scroll nav + list of sections/cards
  
Detail/Show page?
  → Hero panel with back_to + info sections
  
Form/Edit page?
  → Hero panel with back_to + ui_form + ui_sections + sticky buttons

Reads many records one at a time?
  → Sections of one-line links + the selected record's history in a sticky pane (Review Pane)
  
Special/unique page?
  → Hero panel + tabs or custom layout
```
