---
name: design-components
description: UI component helpers for buttons, cards, tables, modals, badges, and navigation in Clubhouse 3. Use when building views with UI components or needing helper method signatures.
---




# Design Components

## Buttons

**Helper**: `ButtonHelper` (`app/helpers/button_helper.rb`)

**CRITICAL:** Always use `ButtonHelper` methods for buttons. Never write raw button HTML.

### Button Methods

```erb
<%# Link styled as button %>
<%= button_link "Label", :variant, url, options %>

<%# CSV export -- carries the icon, variant and 36px floor. Never hand-roll one. %>
<%= export_csv_link records_path(format: :csv) %>
<%= export_csv_link records_path(year: @year, format: :csv), "Export All to CSV" %>

<%# Common shortcuts %>
<%= submit_button "Save" %>
<%= cancel_button url %>    <%# or cancel_link (alias) %>
<%= edit_link url %>        <%# the one edit control: secondary + pen-to-square %>
<%= delete_button url %>    <%# confirms first: "Delete <thing>?" in the red dialog; confirm: false to skip %>

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

**Where buttons sit.** Every page or form action sits in a `button_row`, a lone button included,
and a form's submit and its cancel (`f.submit` + `cancel_link`) share one. Four places take no
row: the record actions on one table row, list line or record card (a `flex gap-2` group); a
button inside a callout; a button in a section's or card's title row; and a toolbar line where
buttons share the row with a pager, a count or a field.

**`delete_button` confirms by default**: the red dialog asks "Delete <thing>?" and says whether it
can be undone. Pass `confirm: false` only where a confirmation is already given another way.

### Button Variants

| Variant | Usage |
|---------|-------|
| `:primary` | Primary actions |
| `:secondary` | Secondary actions |
| `:success` | Positive actions |
| `:error` | Destructive actions |
| `:warning` | Warning actions |
| `:ghost` | Minimal buttons |
| `:tertiary` | Alias of `:ghost` (legacy) |
| `:dark` | `btn-neutral` — dark-chrome contexts only |

The main action of a form, dialog or section is `:primary`, a positive one included; `:success` is
for a positive action that is not the main one. Apply Filters is `:secondary` when the page has a
primary action of its own, and the default primary otherwise. A two-button view toggle shows the
current view as `:primary`. `class:` on a button carries width and margin only: never `bg-*`,
`ring-*`, `btn-link`, padding or a text size (a text-like link is `link_to`, a bigger button `size:`).

### Button Sizes

**Default size is `sm`**. Avoid `xs` except for icon-only buttons in dense tables.

| Size | Usage |
|------|-------|
| `xs` | Icon-only action buttons (rare) |
| `sm` | Default button size |
| `base` | Medium buttons |
| `lg` | Large buttons |
| `xl` | Extra large buttons |

```erb
<%= button_link "Standard", :primary, url %>
<%= button_link "Large", :primary, url, size: "lg" %>
<%= button_link "Edit", :primary, url, icon: "pen", icon_type: :solid %>
```

### Full-Width Action Buttons

**PREFERRED:** `full_width: true` for a page's main action buttons — a bar on a phone and a tablet,
an ordinary button from `lg` up. Never spell `w-full sm:w-auto` by hand: `sm:` is reserved for
field widths (`design-forms`), and every other responsive width in the app turns at `lg`.

```erb
<%= button_link "Sign Up for This Shift", :primary, url, full_width: true %>
<%= submit_button "Start Shift", size: "lg", full_width: true %>
```

`button_classes` takes the same option, for the rare element styled as a button without being one
(a `<summary>` that replaces one). Do not add `justify-center` alongside it — `.btn` already
centres its content.

### Button Helper Selection Rules

| Need | Use | Not |
|------|-----|-----|
| Button-styled link to a URL | `button_link` | `link_to` with button classes |
| Stimulus action or form submit | `button_action` | `button_to` or raw `<button>` |
| Inline text link within content | `link_to` | `button_link` |

**PREFERRED:** `button_link` over `link_to` whenever the link should look like a button.

**PREFERRED:** `button_action` over `button_to` or raw `<button>` for Stimulus-triggered actions.

**CRITICAL:** Ask permission before using a raw `<button>` element. The helpers handle variants, sizes, icons, dark mode, and accessibility automatically. The ruled exceptions are helpers' own raw buttons: the client-side sort heading, `clipboard_button`'s copy icon, and `dropdown_button`, the menu row that acts on the page.

Plain `link_to` is only appropriate for inline text links within paragraphs or content (e.g., "See the <%= link_to "FAQ", "#faq" %> for details.").

---

## Cards

**Helper**: `UiCardHelper` (`app/helpers/ui_components/ui_card_helper.rb`)

```erb
<%= ui_card do %>
  <%= ui_card_title "Card Title", size: :lg %>
  <%= ui_card_body do %>
    Card content goes here.
  <% end %>
  <%= ui_card_footer do %>
    <%= button_link "Action", :primary, url %>
  <% end %>
<% end %>
```

**Options:**
- `shadow:` - Shadow size (`:xs`, `:sm`, `:md`, `:lg`, `:xl`, `:none`); default `:xs` (`card-standard` itself has none)

---

## Accent Cards

**Helper**: `UiAccentCardHelper` (`app/helpers/ui_components/ui_accent_card_helper.rb`)

Accent cards feature a prominent left border for visual hierarchy.

```erb
<%= ui_accent_card "Task Title", variant: :success do %>
  Task content here.
<% end %>

<%= ui_accent_card "Complete Training", 
    variant: :warning, 
    icon: "graduation-cap", 
    icon_type: :solid do %>
  Training details and requirements.
<% end %>

<%# HTML attributes go inside options: -- :id, :class, :aria, :data %>
<%= ui_accent_card "Shift Signup", variant: :info,
    options: { id: "shift-123", class: "mb-4" } do %>
  Shift details.
<% end %>

<%= ui_accent_card step.title, variant: :warning, heading_level: :h3 do %>
  Step details.
<% end %>
```

**PREFERRED — a title that labels the card's content is a heading.** Pass `heading_level:` one
below the nearest heading above the card: `:h3` for a dashboard step under its group's `<h2>` or a
card inside a `ui_section`, `:h2` for a card at page level. It looks the same as the default div,
and a screen reader can then move from card to card. A notice, tip or banner keeps the div. Only
`:h2`, `:h3` and `:h4` are accepted; anything else raises `ArgumentError`.

**Variants:**
- `:success` - Green border (completed, earned)
- `:warning` - Amber border (action needed, pending)
- `:error` - Red border (urgent, blocked)
- `:info` - Info-blue border (optional steps, notes, explanations, help)
- `:primary` - Brand border in Signal Blue (the next step, a call to action) -- what the helper uses when `variant:` is omitted
- `:secondary` - Neutral border (no status to signal)

**CRITICAL — a bare `id:` raises `ArgumentError`.** `ui_section` takes `id:` directly; the accent
card takes every HTML attribute inside `options:`. Turning a `ui_section` into an accent card means
moving its `id:` there, or the page 500s.

---

## Stat Boxes

**Helper**: `UiStatBoxHelper` (`app/helpers/ui_components/ui_stat_box_helper.rb`)

Display metrics with icon, value, and label.

```erb
<%= ui_stat_box "95%", "Complete", variant: :success %>

<%= ui_stat_box "12.5", "Credits Earned", 
    variant: :success, 
    icon: "circle-check", 
    icon_type: :solid %>

<%# Summary row -- always ui_stat_row, never a hand-rolled div or grid %>
<%= ui_stat_row do %>
  <%= ui_stat_box credit_format(@earned), "Earned",
      variant: :success, icon: "circle-check", icon_type: :solid %>
  <%= ui_stat_box hour_format(@scheduled), "Scheduled",
      variant: :secondary, icon: "clock", icon_type: :solid %>
<% end %>
```

**Sizes:** `:sm`, `:md` (default), `:lg`

A tile's value is a short figure or word (a count, an amount, a status), and its `class:` sets
width or margin only. It takes a status variant only when its value is a status, and falls back to
`:secondary` when that count is zero.

### Stat Row

**Helper**: `UiStatRowHelper` (`app/helpers/ui_components/ui_stat_row_helper.rb`)

`ui_stat_row` is the only container for a page's summary tiles: a wrapping flex row that
tightens its gap below `lg`. Never hand-roll the wrapper; a grid of stat boxes is a
different pattern and needs approval per `design-rules`. Full API: `docs/UI-COMPONENTS.md`.

### Stat Link

**Helper**: `ui_stat_link` (`app/helpers/ui_components/ui_stat_box_helper.rb`)

A tile that filters or drills into what it counts is a `ui_stat_link` wrapping the box,
never a hand-rolled `link_to`. A bare anchor draws the global link underline through the
count and the label; the helper turns it off and gives the tile a focus ring in place of
the outline that goes with it.

```erb
<%= ui_stat_row do %>
  <%= ui_stat_link records_path(status: "flagged"), active: @status == "flagged",
                   aria_label: "#{@flagged} flagged — show them" do %>
    <%= ui_stat_box @flagged.to_s, "Flagged", variant: :warning %>
  <% end %>
<% end %>
```

`aria_label:` replaces the box's text for a screen reader, so it carries the count.
`active:` rings the tile whose filter is showing. Full API: `docs/UI-COMPONENTS.md`.

---

## Tables

**Helper**: `TableHelper` (`app/helpers/table_helper.rb`)

### Standard Table

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

Every data table is `ui_table`. `class:` on the table, `t.heading`, `t.row_header` and `t.cell`
carries layout only: margin, width caps, `whitespace-nowrap`, a column-group divider in
`border-line`, a total's weight, or a hook into the table's own component CSS. A two-row grouped
header may be built inside `ui_table` from `TableHelper`'s constants. Not data tables: a print
sheet's blank fill-in grid, a list of record cards, a roster grid of names.

### Striped Table (ADHD-Friendly)

```erb
<%= ui_table full_width: true, striped: true do |t| %>
  <%# ... table content %>
<% end %>
```

### Responsive Table

`ui_table` is responsive by default: a native `<table>` on
desktop (columns auto-size to their widest content) while each row becomes a
card of labeled fields below the `lg` breakpoint (1024px). Mobile labels come
from `data-label` attributes the helper auto-derives from the column headings.

Inside the card the fields wrap to the width available: one per line on a phone,
three or four on a tablet, two lines instead of eight just under 1024px. No
second breakpoint does this — `flex-wrap` decides per field whether another one
fits, and a field holding free text takes a full line rather than being capped.

```erb
<%= ui_table full_width: true, striped: true do |t| %>
  <%= t.header do %>
    <%= t.heading "Name" %>
    <%= t.heading "Email" %>
  <% end %>
  <%= t.body do %>
    <% @users.each do |user| %>
      <%= t.row do %>
        <%= t.row_header user.name %>
        <%= t.cell user.email %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
```

The fold has no sub-modes — labeled fields are the only behavior.
Unrecognized keywords (`mode:` and friends) are not options; they land in
`**options` and are emitted as raw attributes on the `<table>`.

### When to Pass `responsive: false`

Responsive is the default, admin reports included. The wider the table, the more
it needs it: a plain table hides its overflow behind a container scrollbar, and
on a phone that scrollbar is an overlay — invisible until something moves, so
the columns past the fold read as columns that do not exist. An eight-column log
at 390px hid five of them with nothing on screen to say so.

**Keep the default** for more columns than fit at 390px (in practice five or
more), for any user-facing route, `/me` or otherwise, and for reports and logs an
admin might open away from a desk.

**Pass `responsive: false` when:**
- The grid itself is the point and sideways scrolling is the intended reading —
  a year-by-year matrix with a frozen first column, or a ledger sorted from its
  headings. Comment the call site, as `timesheets/top_hour_earners` and
  `bmid/manage/_table` do
- It is a print sheet: the fold is a width query, and a printed page is
  narrower than `lg`, so a responsive table prints as cards
- It is short, roughly four columns or fewer, and already reads as a table on a
  phone. Plain is allowed there, not required

A fit-width table (`full_width: false`, the default) is no reason to opt out.
Its box is sized to its content but capped at its parent (`max-w-full`), so a
value wider than a phone — an address, an id list, a nowrap cell — scrolls inside
the box like any plain table's overflow.

### Filtering Tables

**Helper**: `FilterBarHelper` (`app/helpers/ui_components/filter_bar_helper.rb`)

**PREFERRED:** When a table page offers user-adjustable filters, use `filter_bar` above the table — never ad-hoc filter forms, accordions, or chip rows. In use on Action Logs, Slots by Position, and Asset Management.

An ERB comment cannot sit inside an open ERB expression, so the arguments are
annotated with plain Ruby `#` comments:

```erb
<%= filter_bar id: "my-filters",
               chips: my_filter_chips(@form),   # [{ label:, url: }] -- url drops that one filter
               clear_url: index_path,           # "Clear all"; shown only while chips exist
               count: "Showing 9 of 27",        # optional result summary
               actions: export_csv_link(index_path(format: :csv)),  # right-aligned
               url: index_path do |f| %>
  <%# required block: the filter fields + an Apply submit (f is the form builder) %>
<% end %>
```

Renders a slim row (Filters disclosure button + active-count badge, removable chips, clear-all, count, trailing actions) over a collapsed panel holding the form. Write a per-page `*_filter_chips` view helper returning one chip per active filter. Full API: `docs/UI-COMPONENTS.md`.

**CRITICAL — the CSV export goes in `actions:`.** On a page with a filter bar, the export button rides the bar rather than a `button_row` of its own: the file is scoped by the filters, so it belongs to the control that sets them. Prefer `export_csv_link`; the 36px floor comes from `btn-sm` itself, so no call site spells it. Pass any visibility rule inline — a blank action renders nothing:

```erb
actions: (button_link("Export CSV", :secondary, index_path(@index_params.merge(format: :csv)),
                      icon: "file-csv", icon_type: :solid) if @rows.any?)
```

A second export describing a different table on the page (size counts, order lines) stays beside that table. With no filter bar the export sits in the page's `button_row` above the table.

---

## Sections

**Helper**: `UiSectionHelper` (`app/helpers/ui_components/ui_section_helper.rb`)

Card-like containers for grouping related content.

```erb
<%= ui_section "Section Title" do %>
  Section content.
<% end %>

<%= ui_section "Profile", icon: "user", icon_type: :solid do %>
  Profile content.
<% end %>

<%# Without border padding (for tables) %>
<%= ui_section "Table Section", border: false do %>
  <%= ui_table do |t| %>
    <%# Table content %>
  <% end %>
<% end %>

<%# With custom ID for anchor links %>
<%= ui_section "FAQ", id: "faq-section" do %>
  Content.
<% end %>
```

**Options:**
- `icon:` - FontAwesome icon name
- `icon_type:` - Icon style (`:solid`, `:regular`)
- `border:` - `false` drops only the extra `pb-1`; the body keeps its `px-4 pb-2`
- `id:` - Custom ID for the section

A section normally has a title; an untitled one may box a page's whole body or a form. Icons are
optional, but sibling sections on one page either all carry one or none do.

---

## Hero Panels

**Helper**: `UiHeroPanelHelper` (`app/helpers/ui_components/ui_hero_panel_helper.rb`)

Standardized page header of every page inside the app shell (`design-layouts` > Pages Outside the App Shell for the rest).

```erb
<%= hero_panel icon: "calendar", heading_level: :h1, id: "unique-id" do |panel| %>
  <% panel.title do %>
    Page Title
  <% end %>
  
  <%# One sentence -- see the description note below the options. %>
  <% panel.description do %>
    Brief description of the page's purpose.
  <% end %>
  
  <% panel.back_to do %>
    <%= back_to "Previous Page", previous_path %>
  <% end %>
  
  <% panel.year_selector year: @year, years: current_user.years_combined %>
  
  <%# hero_stats needs an approved plan -- see the note below the options. %>
  <% panel.hero_stats do %>
    <%= panel.stat_badge "Label", "Value", color: :default %>
    <%= panel.stat_badge "Urgent", "5", color: :warning %>
  <% end %>
  
  <% panel.progress completed: 8, total: 10, start_label: "Tasks", end_label: "80%" %>
<% end %>
```

**Options:**
- `icon:` (required) - FontAwesome icon name
- `heading_level:` - `:h1` or `:h2` (default: `:h2`)
- `id:` - Unique ID for accessibility

**CRITICAL — hero stats need an approved plan**: `hero_stats` / `stat_badge` compete
with the page title, and on mobile they stack beneath it and push the content down. Do
not use them unless the user approved a plan that puts stats in the hero. Default to a
`ui_stat_row` in the main body, above the content it summarizes:

```erb
<%= ui_stat_row do %>
  <%= ui_stat_box @report.trainee_count.to_s, "Trainees", variant: :warning %>
  <%= ui_stat_box @report.enrollment_count.to_s, "Sign-ups" %>
<% end %>
```

See `design-rules` > Hero Panel Stats Approval Workflow.

**CRITICAL — description is one sentence**: `panel.description` states what the page
does, in a single sentence, in the panel's own style (no classes, no status colour). Every hero
has one except a new or edit form page, whose title already says what it does. The title may
carry a status or a badge beside the words. Longer explanations, caveats, and step-by-step
instructions go in the main content: usually the collapsed card below; a full page of
instructions on a page the reader operates takes a `ui_section` at the foot, linked from
the top per `design-layouts` > Help Section & FAQ Pattern. See `design-rules` > Hero
Panel Description Rule.

The usual home for a rule, legend or how-to that would have been the hero's second
sentence is one collapsed card under the stat row — `ui_disclosure … variant: :card,
class: "my-4"` holding an `instruction-list`, labelled "About This Report" on a report or a
log, or "How This Page Works" on a page the reader operates (the page's controls decide which
— `design-rules`). The card variant is required: boxed,
with a chevron, it reads as a control for the whole page; the inline summary is a line of
text. On a report or a log the same card holds every other explanation the page has —
legends and notes about one section included — in place of a visible list, info callout or
paragraph; warnings, privacy notices and notices about one state of the data stay visible.
Reference:
`app/views/asset_management/asset_history/index.html.erb`, and
`app/views/ticketing/access_documents/index.html.erb` for a legend with samples; the full
pattern and its placement rules are in `design-rules` > Where a Rule or a How-To Goes. The
one-sentence rule is guarded by `test/views/hero_description_test.rb`.

---

## Badges

**Helper**: `BadgeHelper` (`app/helpers/ui_components/badge_helper.rb`)

```erb
<%= ui_badge "New", :primary %>
<%= ui_badge "Approved", :success %>
<%= ui_badge "Pending", :warning %>
<%= ui_badge "Rejected", :error %>

<%# With icons %>
<%= ui_badge "Completed", :success, icon: "circle-check", icon_type: :solid %>

<%# Size options: "xs" (default), "sm", "base" -- "md" is not a Tailwind text size %>
<%= ui_badge "Larger", :primary, size: "sm" %>
<%= ui_badge "In a text-lg headline", :warning, size: "base" %>
```

`class:` carries layout only (`shrink-0`, margin), never opacity or colour. Every state of a badge
set is a badge: a helper that returns `ui_badge` for some states does not return plain text for
another.

---

## Progress Bars

**Helper**: `UiProgressBarHelper` (`app/helpers/ui_components/ui_progress_bar_helper.rb`)

```erb
<%= ui_progress_bar 75 %>
<%= ui_progress_bar 50, :success %>
<%= ui_progress_bar 60, :warning, label: "Loading…" %>
<%= ui_progress_bar 80, label: true %>  <%# Show percentage %>
<%= ui_progress_bar 90, size: :lg %>
<%= ui_progress_bar 65, bar_class: "progress-projected" %>  <%# striped: an estimate, not yet earned %>
```

---

## Modals

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

The title is `modal-title-text` (`text-xl font-semibold`). Two dialogs open themselves instead of
through the `modal` controller: the on-demand `dialog_controller.js` (search, the mega menu) and the
HQ wizard (`hq_wizard_controller.js`). A new dialog uses `ModalHelper`.

**PREFERRED for Turbo form dialogs:** `modal_dialog` folds the
`turbo_frame_tag "modal"` wrapper, the chrome (`close_button: false`), and the
title into one call; `modal_form_footer` is the standard submit + Cancel row
inside the form (multi-submit footers keep an explicit `button_row`).

```erb
<%= modal_dialog id: "assign-dialog", title: "Assign Application" do %>  <%# frame: false when streamed into an existing "modal" frame %>
  <%= form_with url: ..., builder: AppFormBuilder, data: { turbo_frame: "_top" } do |f| %>
    <%= f.select ... %>
    <%= modal_form_footer f, submit: "Save Assignment" %>  <%# omit f to use a bare submit_button; close: relabels Cancel %>
  <% end %>
<% end %>
```

---

## Tabs

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

Tabs show panes of one page in place. A switch that loads another view of the page (a log's Search
and Live modes, the mega menu's panels) is a group of buttons, not tabs, with the current one told
to a screen reader (`aria-current`, or an sr-only "(current view)").

---

## Notifications

**Helper**: `UiComponents::NoticeBoxHelper` (`app/helpers/ui_components/notice_box_helper.rb`)

### Callout Boxes

```erb
<%= ui_callout_box :success do %>
  Your changes have been saved.
<% end %>

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

**Tints** (`components/boxes.css`): success and error `bg-*/5` on `border-*/20`; info `bg-info/10`
on `border-info/30`; warning `bg-warning/10` on a full `border-warning`, with amber ink on everything
inside but buttons and badges; secondary `bg-base-300/90`.

**When a notice is a callout.** A notice in the page body is a `ui_callout_box` or a
`ui_alert_banner`. Inside a card, a dashboard step, a table cell, a label/value row or a dialog
body, a one-line status message may instead be status-coloured text that starts with its status
icon (`fa_icon … class: "icon-error"`), at `text-base` and in sentence case: never capitals, never
without the icon. A callout holds a notice, never a control alone; its `class:` is margin and width.

### Alert Banners

```erb
<%= ui_alert_banner "Important Notice", :warning do %>
  Banner content with prominent styling.
<% end %>
```

---

## Empty States

```erb
<%= ui_empty_state "No items found." %>

<%= ui_empty_state "No messages yet.", icon: "envelope", icon_type: :regular %>

<%= ui_empty_state do %>
  No upcoming shifts found. <%= link_to "Browse available shifts", available_shifts_path %>.
<% end %>
```

**When a collection needs one.** A list, table or section that the reader came for, and a search's
results, show `ui_empty_state` when empty: never a header-only table or an empty box. A collection
may render nothing when it cannot be empty where it is drawn (its caller or controller guards it,
or the only link to it needs rows; say so in a comment), when it is a fixed catalogue, or when it is
supplementary (an optional bucket, a group or a dashboard step shown only with items) and the page
gives its count elsewhere. A shared partial may leave the empty state to its caller.

---

## Sidebar

**Helper**: `SidebarHelper` (`app/helpers/sidebar_helper.rb`)

```erb
<%# Every layout: a menu definition from app/lib/menus.rb (docs/MENUS.md) %>
<% sidebar_menu :me do %>
  <%= sidebar_render_menu(Menus::ME, @menu_context) %>
<% end %>
```

`sidebar_render_menu` builds the `sidebar_section`, `sidebar_submenu` and `sidebar_item` calls; no view
makes them directly.

**Theme Variants:** `"me"`, `"admin"`, `"hq"` (anything else falls back to `"me"`)

---

## Match Stepper

**Helper**: `UiComponents::UiMatchStepperHelper` (`app/helpers/ui_components/ui_match_stepper_helper.rb`)

"Match 2 of 3" with Previous and Next, joined: walking a search's matches one record at a time,
round past either end. Markup alone; the named Stimulus controller answers `#previous`/`#next` and
rewrites its `count` target. Pin it on its own row over what it steps through, not in a header
that scrolls away. In use on the mailbox's pane (`common/messages/_messages_panel`,
`search_matches_controller`). Rules: `docs/DESIGN-GUIDE.md` › Match Stepper.

```erb
<%= ui_match_stepper "search-matches", label: "Matches in this conversation", current: 1, total: 3 %>
```

---

## Navigation Dropdowns

**Helper**: `NavigationHelper` (`app/helpers/navigation_helper.rb`)

```erb
<%# A native <details> dropdown. The label is the trigger button (variant: a
    ButtonHelper variant, default :secondary); class: takes DaisyUI placement
    modifiers; summary_class: / menu_class: size the trigger and the list;
    menu_label: names the list when the label is a greeting ("Hello Firecracker"). %>
<%= dropdown_menu "Menu", class: "dropdown-end", menu_class: "w-64" do %>
  <%= dropdown_item "Profile", profile_path %>
  <%= dropdown_item "Settings", settings_path %>
  <%= dropdown_divider %>
  <%= dropdown_item "Logout", logout_path, data: { turbo_method: :delete } %>
<% end %>

<%= dropdown_item_disabled "Coming Soon" %>

<%# A row that acts on the page instead of going somewhere %>
<%= dropdown_button "Label", data: { action: "controller#method" } %>
```

An open dropdown closes on Escape, on a click outside it, and when an item is chosen.

---

## Icons

**Helper**: `IconHelper` (`app/helpers/icon_helper.rb`)

**CRITICAL:** Use only FontAwesome Free v7.1 icons via the `fa_icon` helper.

**CRITICAL — the regular style draws only the icons in `lib/fontawesome/regular-icons.txt`.**
Regular is `fa_icon`'s default, and the default `icon_type:` of `ui_empty_state`, `ui_section`,
`f.fieldset`, the button helpers and the sidebar helpers. Font Awesome Free's regular font has no
glyph for any other name, so the browser draws a crossed box in its place. Pass `:solid` for any
icon not on the list; `fa_icon` raises in development and test when one is asked for in regular.
The list is generated from the font (`node bin/fontawesome_regular_icons.js`), never edited by hand.

**AVOID:**
- FontAwesome Pro icons
- Custom SVG icons
- Inline SVG markup in views

### Basic Usage

```erb
<%= fa_icon "user" %>
<%= fa_icon "user", :solid %>
<%= fa_icon "star", :solid, size: "lg" %>
<%= fa_icon "arrow-right", :solid, start: 2 %>  <%# margin-start %>
<%= fa_icon "check", :solid, class: "icon-success" %>
<%= fa_icon "ban", :solid, class: "icon-warning", label: "Not marked as being on site" %>
```

**`label:` for an icon that speaks for itself.** Every icon is `aria-hidden`, so a mark with
no words beside it — a ban icon in a table row — needs its meaning said some other way.
`label:` sets the `title` (a tooltip for a pointer) and appends the label as an `sr-only`
sentence. It is required on every such icon, wherever its explanation lives (the page's card, a
visible legend, or nowhere): an `sr-only` name alone leaves a sighted reader with the icon only.
Never hand-write the `title:` + `<span class="sr-only">` pair; leave `label:` off an icon that
only decorates the words next to it.

**Glyphs in text are punctuation, not icons.** "·" and "—" as separators, "→" for "then" or
between a value's before and after, and "×" naming a close control in a sentence stay typed. A
glyph that stands in for a word on its own (✓ or ✗ as a status, ★ as a rating) is an icon:
`fa_icon`.

**Never pass `start:`/`end:` to an icon inside a button.** `.btn` is a flex row with
`gap: .375rem`, so the space is already there and a margin doubles it. The same goes for a
`<span>`, `<kbd>` or badge inside a button — write no margin and let the gap do it. Outside a
button (a `<dt>`, a `<strong>`, a table cell) `start:`/`end:` is the right tool.

### Common Icons by Category

Most of these have no regular glyph and draw only with `:solid`. Check
`lib/fontawesome/regular-icons.txt` before leaving one in the regular style.

**Navigation:** `home`, `arrow-left`, `arrow-right`, `chevron-down`, `bars`, `times`

**Actions:** `pen`, `trash`, `plus`, `minus`, `check`, `download`, `upload`

**Status:** `circle-check` (success), `circle-exclamation` (warning), `triangle-exclamation` (danger), `circle-info` (info)

**Objects:** `user`, `users`, `calendar`, `clock`, `envelope`, `file`, `folder`

---

## Lists

A bulleted or numbered list in content is a plain `<ul>`/`<ol>` with one class for the marker
and its indent, nothing else for spacing on the inline-start side:

```erb
<ul class="list-bulleted space-y-1">
  <li>One shift per day.</li>
</ul>
```

`list-bulleted` and `list-numbered` carry the one list indent (`design-foundations` > Spacing).
Never `list-disc` or `list-decimal` on their own, `ms-5`, `pl-4` or `list-inside`. A list of rows
(messages, conversations) is not a marker list and takes no indent; a Q&A list is
`instruction-list` (`design-content` > Q&A Style Content Pattern). Lines that each start with a
typed marker (`—`, `•`, `*`) are a list: write the `<ul>`, not the marker.

---

## Related Skills

- **design-rules**: Critical rules and approval workflows
- **design-foundations**: Colors, typography, spacing used in components
- **design-forms**: Form-specific components and patterns
- **design-layouts**: Page layouts using these components
- **design-content**: Accessibility and language for components

## Full Documentation

For complete documentation, see:
- [docs/DESIGN-GUIDE.md](../../docs/DESIGN-GUIDE.md) - Component Library section
- [docs/UI-COMPONENTS.md](../../docs/UI-COMPONENTS.md) - Complete helper API reference
