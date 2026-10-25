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

**CRITICAL:** Ask permission before using a raw `<button>` element. The helpers handle variants, sizes, icons, dark mode, and accessibility automatically.

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
- `shadow:` - Shadow size (`:xs`, `:sm`, `:md`, `:lg`, `:xl`, `:none`)

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

A second export describing a different table on the page (size counts, order lines) stays beside that table.

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
- `border:` - Set to `false` to remove padding
- `id:` - Custom ID for the section

---

## Hero Panels

**Helper**: `UiHeroPanelHelper` (`app/helpers/ui_components/ui_hero_panel_helper.rb`)

Standardized page header component used across all /me routes.

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
does, in a single sentence. Longer explanations, caveats, and step-by-step
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

---

## Progress Bars

**Helper**: `UiProgressBarHelper` (`app/helpers/ui_components/ui_progress_bar_helper.rb`)

```erb
<%= ui_progress_bar 75 %>
<%= ui_progress_bar 50, :success %>
<%= ui_progress_bar 60, :warning, label: "Loading…" %>
<%= ui_progress_bar 80, label: true %>  <%# Show percentage %>
<%= ui_progress_bar 90, size: :lg %>
<%= ui_progress_bar 40, projected: 65 %>  <%# lighter bar behind: the total once pending sign-ups count %>
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

---

## Sidebar

**Helper**: `SidebarHelper` (`app/helpers/sidebar_helper.rb`)

```erb
<%= sidebar_menu "me" do %>
  <%= sidebar_section "Navigation", theme: "me" do %>
    <%= sidebar_item "Dashboard", me_root_path, icon: "home", theme: "me", root: true %>
    <%= sidebar_item "Schedule", me_schedule_path, icon: "calendar", theme: "me" %>
  <% end %>
  
  <%= sidebar_submenu "Settings", icon: "gear", icon_type: :solid, theme: "me" %>
<% end %>
```

**Theme Variants:** `"me"`, `"admin"`, `"hq"` (anything else falls back to `"me"`)

**Badge Variants:** `:error`, `:success`, `:warning`, `:info`

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
```

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
sentence. Never hand-write the `title:` + `<span class="sr-only">` pair; leave `label:` off
an icon that only decorates the words next to it.

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
