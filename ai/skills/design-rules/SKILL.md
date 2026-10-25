---
name: design-rules
description: Critical design rules and approval workflows for Clubhouse 3. Use when creating or modifying any frontend views, components, or styling. Enforces approval requirements for new components and color styling.
---

# Design Rules & Approval Workflows

## Rule Priority Markers

This design system uses priority markers to indicate rule severity:

| Marker | Meaning | Action |
|--------|---------|--------|
| **CRITICAL** | Must follow. Breaking this rule causes accessibility, usability, or consistency issues. | Never deviate without explicit user approval. |
| **PREFERRED** | Best practice. Follow unless there's a compelling reason not to. | Deviate only with good justification. |
| **AVOID** | Anti-pattern. Don't do this except in rare, documented exceptions. | Requires explicit justification if used. |

---

## Component Approval Workflow

**CRITICAL**: Any new UI/UX component pattern not documented in the design guide requires explicit user confirmation before implementation.

### When Approval is Required

**Examples requiring approval:**
- New interaction patterns (accordions not in guide, carousels, slideovers, command palettes)
- New layout components (masonry grids, timeline views, kanban boards)
- New form controls not covered by `AppFormBuilder`
- New navigation patterns not covered by existing helpers
- New data visualization components (charts, graphs, diagrams)

### Approval Process

1. **Identify the need**: Recognize that the component is not documented in the design guide
2. **Propose to user**: Explain why the new component is required for the specific use case
3. **Present alternatives**: Suggest alternative solutions using existing components if applicable
4. **Wait for approval**: Do not implement until user confirms or suggests alternative approach
5. **Implement as helper**: Once approved, create the component as a Ruby helper in `app/helpers/` or `app/helpers/ui_components/`
6. **Document in guide**: Update the design guide with component description, usage, examples, accessibility, and styling

---

## Color Styling Approval Workflow

**CRITICAL**: Any new color styling not present in semantic color tokens requires explicit user confirmation before implementation.

### When Approval is Required

**Examples requiring approval:**
- New semantic color tokens beyond those in the Foundation Layer
- New colored backgrounds not covered by existing tokens
- New border colors for specific purposes
- New status color variations
- New gradient combinations

### Approval Process

1. **Identify the color need**: Determine that existing color tokens don't cover the use case
2. **Propose to user**: Explain why the new color styling is required
3. **Wait for approval**: Do not implement until user confirms
4. **DRY up with custom CSS**: Once approved, create a new CSS file in `app/assets/stylesheets/components/` for the component, or add to an existing component file
5. **Document in guide**: Update the design guide with custom utility class name, use cases, Tailwind composition, dark mode support, and examples

### Before Requesting Approval

Always verify that an existing semantic color token doesn't already solve the need. Review the Foundation Layer > Color System section thoroughly.

**See**: `design-foundations` skill for complete semantic color token reference.

---

## Hero Panel Stats Approval Workflow

**CRITICAL**: Do not place stats in the hero panel (`panel.hero_stats` /
`panel.stat_badge`) unless the user has approved a plan that specifies them there.

Hero stats compete with the page title for the reader's first fixation, and on
mobile they stack beneath it and push the content down. The default home for
summary numbers is the **main body**, in a `ui_stat_row` above the content they
summarize:

```erb
<%= ui_stat_row do %>
  <%= ui_stat_box @report.trainee_count.to_s, "Trainees", variant: :warning %>
  <%= ui_stat_box @report.enrollment_count.to_s, "Sign-ups" %>
<% end %>
```

Hero stats remain available for pages whose plan the user approved with stats in the
hero. Only the /me dashboard welcome banner uses them. Put summary numbers in a body
`ui_stat_row` unless an approved plan says otherwise.

**See**: `design-components` for `ui_stat_row` and `ui_stat_box`; `app/views/training/multiple_enrollments/index.html.erb`
for the reference implementation.

---

## Hero Panel Description Rule

**CRITICAL**: `panel.description` is **one sentence** saying what the page does. Nothing else.

The hero is the page's first fixation and is size-constrained on mobile. A paragraph
there pushes the actual content below the fold and buries the one line the reader
needed.

Anything longer than a sentence — background, caveats, eligibility rules, and
especially step-by-step instructions — goes in the main content: usually the one
collapsed card described below; a full page of instructions on a page the reader
operates takes a `ui_section` at the foot, announced from the top per the Help Section &
FAQ Pattern.

```erb
<%# CORRECT %>
<% panel.description do %>
  Claim your ticket to use it this year, or bank it for a future event.
<% end %>

<%# WRONG -- instructions in the hero %>
<% panel.description do %>
  Review each ticket below. If you want to use a ticket this year, click Claim.
  If you would rather save it, click Bank -- banked tickets stay available for
  three years. Contact the Ranger Ticketing Team if a ticket is missing.
<% end %>
```

Move the instructions down instead:

```erb
<%= ui_callout_box :info, icon: "circle-info", icon_type: :solid do %>
  New to ticketing? Read the <%= link_to "instructions", "#instructions", class: "underline font-semibold" %> below.
<% end %>

<%= ui_section "How Ticketing Works", id: "instructions", icon: "circle-question" do %>
  <dl class="instruction-list">
    <%# steps, caveats, contact info %>
  </dl>
<% end %>
```

### Where a Rule or a How-To Goes: the Collapsed Card

A foot-of-page section with a top link is for a page of instructions. For the usual
case — the rules, legends, caveats and how-tos that explain a page — the house pattern is
**one collapsed `ui_disclosure` card per page**, holding an `instruction-list` in which each
sentence answers a short question:

```erb
<%= ui_stat_row do %> … <% end %>

<%= ui_disclosure "About This Report", variant: :card, class: "my-4" do %>
  <dl class="instruction-list">
    <dt>Where are the radios?</dt>
    <dd>Handheld radios are left out by default; choose Radio in the filters to include them.</dd>
  </dl>
<% end %>

<%= filter_bar … %>
```

- **Two labels, Title Case**: "About This Report" on a report or a log, "How This Page Works"
  on a page the reader operates. The label names the page, not the sentence, and the page's
  controls decide it: a page with a control that changes a row it lists, acts on a selection
  of them, or adds to them (a row's Revoke, a bulk Convert, Print Selected, a New Reserved
  Handle button) is one the reader operates. Any other page is a report or a log — whatever
  its card holds, wherever its rows lead (a drill-down, an Edit), and even when one button
  tidies the whole list (the Request Log's "Delete Old Entries"), which acts on no row and
  no selection.
- **`variant: :card`, never the inline default.** Both clear the 36px touch floor, but the
  inline summary is a line of text with a small triangle, which reads as a detail of the
  content around it. The card's summary is boxed, 48px, with a chevron — a control for the
  whole page — and the call site carries nothing but the one-token `my-4`.
- **It sits where the explanation is needed**: under the stat row and above the filter bar
  on a report; above the board or the form on a page the reader operates; never inside a
  `ui_section`. With no stat row it sits directly under the hero, after any picker that swaps
  what the page reports on (a shift, a period); a form of report parameters counts as the
  filter bar. Under a stat row it shares the stat row's branch — that is placement, not a
  guard.
- **Guard it on the page's rows**: the card, when a legend for rows is all it holds
  (`<% if @total.positive? %>`) — a card whose every pair explains the table, be it a row, a
  column or a cell, counts as one; the pair, when the legend sits among reference pairs
  (`<%= render "summary_legend" if @total_count.positive? %>`). Either guard reads the
  page's rows, not the filtered view's, or a filter that matches nothing takes the
  explanation from above its own bar. A pair that applies in only one state keeps its own
  condition, unless the branch the card sits in already implies it. Reference data and a
  rule about what belongs on a list (it matters most while the list is empty) stay
  unguarded, and so does a column definition that sits among them.
- **Bare `class="instruction-list"`**, no classes on `<dt>` or `<dd>`, no "Q:"/"A:" in the
  copy (`accessibility.css` draws them). The answer is plain prose; a sentence moved into
  the card keeps its wording wherever it still reads as an answer — less whatever the hero
  already says: an answer does not open with the hero's sentence. The question is short and
  in sentence case. One that quotes a label the page prints (a heading, a column, a button)
  reads it from where the page prints it — a constant, or a template local both read — so
  the two cannot drift.
- **Closed by default.** `open: true` exists for a page where the explanation must not be
  missed; none uses it — a disclosure that is always open is just a box. On paper a closed
  card is left out, and one the reader opened prints open (`components/disclosure.css`).
- **On a report or a log, the card is the only home for an explanation.** A counting rule, a
  definition, a legend, a how-to and a note about one section all go in it; no Q&A list,
  explanatory paragraph or info callout of reference is left in the body. A legend is a pair
  like any other, with its samples in the `<dd>` (a lone icon may sit in the question that
  asks about it); one that two pages share is a partial holding the pair, rendered inside
  each page's own list. A note about one section becomes a pair whose question names the
  section ("Who is under “Resolve first”?"), because the answer does not sit under its
  heading. An icon whose only explanation is in the card says its meaning itself: `fa_icon …
  label:` gives it a tooltip and a screen-reader sentence; the legend's pair carries the
  label's own words and reads whole with the sample left out, since a screen reader skips it
  ("Bounced: …"). A `title:` is no home either, on a heading or a figure: what it says is
  said in the card too, both reading one local (Training Capacity, On Duty).
- **What stays visible is a message, not reference**: a warning or an error, a privacy
  notice, a notice that appears only in one state of the data or of the reader (a prior year,
  a restricted scope, a truncated list, a missing setting), a count, a caption on one
  figure, an empty state, and a hint about one filter or form field, which is `help_text:`
  on the field on either kind of page. A sentence that explains one figure, icon or column
  in one state is still reference — a pair on that condition; it stays visible only when it
  changes what the whole page is showing. Folding never takes the page's subject out of
  sight: the year or period a report covers stays in the hero's sentence or the count line.
  How far back a log or a history goes — its retention, the date it starts — is said again
  by the empty state, where it may be the whole reason nothing is listed.
- **On a page the reader operates**, a sentence **joins** a visible list, callout or
  section that fits instead of starting a card beside it. A consequence of the page's action
  stays visible as a `ui_callout_box :warning` or `:info` beside the action.

Reference implementations: `app/views/asset_management/asset_history/index.html.erb`, and
`app/views/ticketing/access_documents/index.html.erb` for a card that holds a legend with
samples.

**Guarded**: `test/views/hero_description_test.rb` fails on any `hero_panel` description
under `app/views` that renders more than one sentence, judging a branching description one
path at a time. Data-driven descriptions are guarded where their data lives. The card rule
has no guard test (it would need a list of which pages are reports); a card or a pair on a
condition is asserted in the page's controller test through `ReportCardTestHelper`.

**See**: `design-layouts` > Help Section & FAQ Pattern; `design-content` for
`instruction-list`; `design-components` > Hero Panels.

---

## Critical Rules Summary

These rules are **CRITICAL** and must be followed:

| Rule | Correct | Wrong |
|------|---------|-------|
| Body text size | `text-base` (0.9rem on 1.2 leading) | `text-sm` or `text-xs` for body |
| Breakpoints | `lg:` for desktop; `flex-wrap` in between; `sm:` only in field `width:` | `md:` as a layout tier |
| Icons | FontAwesome Free 7.1 | Pro icons, custom SVGs |
| Colors | Semantic tokens (`text-body`, `bg-primary`) | Direct values (`text-gray-700`) |
| Buttons | Use `ButtonHelper` methods | Raw HTML buttons |
| Forms | Use `AppFormBuilder` / `ui_form` | Raw `form_with` without builder |
| Headings & buttons | Title Case everywhere ("Adjust Your Choices") | Sentence case ("Adjust your choices") |
| Copy (`design-content`) | "Add X" / "Save X"; success flash "Note added."; `DateTimeHelper` dates (`Jan 8, 2026`) | "New X" / "Update X"; "has been successfully added!"; `strftime` in a view |
| Dark mode | Semantic tokens, which re-resolve per theme; `dark:` only for a raw value in a component CSS file | Light-only styling; `bg-white dark:bg-gray-800` pairs in markup |
| Touch targets | Minimum 36px | Smaller interactive areas |
| Interface density | Compact layouts, minimize scrolling | Excessive whitespace, decorative padding |
| Color usage | Neutral dominance, semantic color only | Colorful decoration, busy color schemes |
| Help sections | Link from top with `#anchor` | Help content without top-of-page link |
| New components | Get approval, implement as helper, document | Implement without approval |
| Summary stats | `ui_stat_row` of `ui_stat_box` in the main body | `panel.hero_stats` without an approved plan |
| Table exports | `filter_bar actions:` when the page has a filter bar | An Export `button_row` above or below the bar |
| Hero description | One sentence on what the page does | Paragraphs or instructions in the hero |
| New color styling | Get approval, DRY with custom CSS, document | Implement without approval |
| Styling | Tailwind + DaisyUI utilities; component CSS in `components/<name>.css` only when utilities can't express it | Inline styles, scoped CSS, ad-hoc CSS outside `components/` |

**See**: `design-foundations` for colors/typography, `design-components` for helpers, `design-forms` for forms, `design-layouts` for breakpoints

---

## Styling Mechanism

**CRITICAL**: Prefer Tailwind and DaisyUI utility classes in markup. Write CSS only when
utilities cannot express it.

- Custom CSS lives in `app/assets/stylesheets/components/<component>.css`, one component
  per file, imported from `components.css` or `utilities.css` (AGENTS.md > Styles)
- Extract an `@utility` only when the same 3+ classes recur in 3+ places
  (`design-foundations` > Custom Utility Classes)
- No inline `style=` attributes, no scoped or per-view CSS, no CSS outside `components/`
- A new component or a new colour treatment still needs approval first (workflows above),
  whether it is built from utilities or from a component file

---

## Anti-Patterns to Avoid

### Technical Anti-Patterns

**AVOID:**
- Inline Tailwind classes when helpers exist
- Direct color values when semantic tokens are available
- Raw HTML when ERB helpers provide the same functionality
- Inconsistent dark mode support
- Missing ARIA attributes on interactive elements

### Interface Density Anti-Patterns

**AVOID:**
- Excessive vertical whitespace creating unnecessary scrolling
- Decorative padding that doesn't serve hierarchy or grouping purposes
- Sparse layouts that display minimal information per screen
- Missing help section links at top of pages with FAQ content below
- Unanchored help sections without top-of-page navigation

### Color Usage Anti-Patterns

**AVOID:**
- Using multiple accent colors for visual variety
- Colored backgrounds for decoration rather than semantic purpose
- Colorful borders or gradients without status meaning
- Colored text for emphasis (use weight/size instead)
- "Rainbow" interfaces with too many competing colors
- Relying on color alone to convey information (always pair with icons/text)

### Content Anti-Patterns

**AVOID:**
- Walls of text without visual breaks
- Ambiguous button labels ("Click here", "Submit")
- Missing error messages or unclear validation feedback
- Inconsistent terminology across pages
- Using the word "work" or its variants

**See**: `design-content` skill for terminology and language rules

### Workflow Anti-Patterns

**AVOID:**
- Implementing new UI components not in the design guide without user approval
- Creating custom color styling without user approval
- Failing to implement approved components as reusable helpers
- Missing documentation updates after adding new components or styling
- Inline component code instead of helper abstraction

### Generic AI Aesthetics

**AVOID:**
- Overused font families (Inter, Roboto, Arial as primary fonts)
- Cliched color schemes (purple gradients on white backgrounds)
- Hand-picked blue CTAs (`bg-blue-600`, `btn-info`) instead of the brand token — the brand *is* a blue
  (Signal Blue), so a raw blue reads as an off-key copy of it. Use `bg-primary` / `btn-primary`

---

## Related Skills

For specific design system topics, consult these skills:

- **design-foundations**: Semantic color tokens, typography scale, spacing, dark mode
- **design-components**: Button/card/table/modal helpers and component patterns
- **design-forms**: Form builder, field types, validation patterns
- **design-layouts**: Breakpoints, page patterns, responsive design
- **design-content**: Terminology, ADHD-friendly patterns, accessibility

## Full Documentation

For complete documentation, see:
- [docs/DESIGN-GUIDE.md](../../docs/DESIGN-GUIDE.md) - Comprehensive design system guide
- [docs/UI-COMPONENTS.md](../../docs/UI-COMPONENTS.md) - Complete helper method signatures
- [docs/form_helper.md](../../docs/form_helper.md) - Form builder API reference
