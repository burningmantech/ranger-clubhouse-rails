# UI Components API Reference

Complete reference for Clubhouse 3 UI component helpers. See also: [Form Helper](form_helper.md), [Design Guide](DESIGN-GUIDE.md)

**Quick Links:**
- [Layout Components](#layout-components)
- [Data Display](#data-display)
- [Forms](#forms)
- [Interactive Components](#interactive-components)
- [Notifications](#notifications)
- [Utilities](#utilities)

---

## Layout Components

### hero_panel

**File:** `app/helpers/ui_components/ui_hero_panel_helper.rb`

```ruby
hero_panel(icon:, id: nil, heading_level: :h2, title: nil, description: nil, back_to: nil, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `icon:` | String | required | FontAwesome icon name |
| `id:` | String | auto-generated | Unique ID for accessibility |
| `heading_level:` | Symbol | `:h2` | Heading level (`:h1` or `:h2`) |
| `title:` | String | `nil` | Plain-text title (block slot for rich titles) |
| `description:` | String | `nil` | Plain-text description — **one sentence** on what the page does |
| `back_to:` | Symbol/Array/String | `nil` | `:dashboard`, `[label, path]`, or an already-rendered link |

Simple pages need no block:

```ruby
hero_panel icon: "ticket", heading_level: :h1, id: "ticket-header",
           title: "Event ticket",
           description: "Claim your ticket to use it this year, or bank it for a future event.",
           back_to: ["Tickets & Provisions", me_tickets_path]
```

**Builder Methods** (for stats, progress, year selector, or rich title/description):

```ruby
hero_panel(icon: "calendar") do |panel|
  panel.title { "Page Title" }
  # description is one sentence -- longer explanations and instructions belong in
  # the main content. See design-rules > Hero Panel Description Rule.
  panel.description { "Description text" }
  panel.back_to { link_to "Back", path }
  panel.year_selector(year: @year, years: years_array)
  # hero_stats requires an approved plan -- default is a ui_stat_box row in the
  # main body. See design-rules > Hero Panel Stats Approval Workflow.
  panel.hero_stats do
    panel.stat_badge("Label", "Value", color: :default)
  end
  panel.progress(completed: 8, total: 10, start_label: "Tasks")
  panel.progress_status { "Custom status content" }
end
```

### ui_section

**File:** `app/helpers/ui_components/ui_section_helper.rb`

```ruby
ui_section(title = nil, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | `nil` | Section title |
| `badge:` | String | `nil` | Badge content, beside the title inside the heading element; `"0"` reads "none" |
| `badge_color:` | Symbol | `:secondary` | Badge color variant |
| `icon:` | String | `nil` | FontAwesome icon name |
| `icon_type:` | Symbol | `:regular` | Icon style |
| `edit_link:` | String | `nil` | Path for edit button |
| `border:` | Boolean | `true` | Include padding |
| `body_class:` | String | `nil` | Additional classes for body |
| `class:` | String | `nil` | Additional classes for container |
| `id:` | String | `nil` | HTML id attribute |

### ui_section_title

**File:** `app/helpers/ui_components/ui_section_helper.rb`

```ruby
ui_section_title(title = nil, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | `nil` | Title text (or use block) |
| `badge:` | String | `nil` | Badge content, beside the title inside the heading element; `"0"` reads "none" |
| `badge_color:` | Symbol | `:secondary` | Badge color variant |
| `class:` | String | `nil` | Additional CSS classes |

### ui_subheading

**File:** `app/helpers/ui_components/ui_section_helper.rb`

```ruby
ui_subheading(title = nil, &block)
```

An `<h3>` one level under a `ui_section_title`: a group of rows, a month of sessions. Takes
the title as a string, or as a block when a badge or a muted span sits beside it. No options.

```erb
<%= ui_subheading "April" %>
<%= ui_subheading do %>
  <%= group_meta[:title] %>
  <%= ui_badge rows.size.to_s, group_meta[:badge_color] %>
<% end %>
```

### ui_card

**File:** `app/helpers/ui_components/ui_card_helper.rb`

```ruby
ui_card(options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `shadow:` | Symbol | `:xs` | Shadow size (`:xs`, `:sm`, `:md`, `:lg`, `:xl`, `:none`) |
| `width:` | Integer | `nil` | Custom width in pixels |
| `height:` | Integer | `nil` | Custom height in pixels |
| `class:` | String | `nil` | Additional CSS classes |

### ui_card_image

**File:** `app/helpers/ui_components/ui_card_helper.rb`

```ruby
ui_card_image(options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image:` | String | `nil` | Path to image |
| `alt:` | String | `""` | Alt text for image |
| `width:` | Integer | `nil` | Custom width in pixels |
| `height:` | Integer | `nil` | Custom height in pixels |
| `class:` | String | `nil` | Additional CSS classes |

### ui_card_body

**File:** `app/helpers/ui_components/ui_card_helper.rb`

```ruby
ui_card_body(options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `class:` | String | `nil` | Additional CSS classes |

### ui_card_title

**File:** `app/helpers/ui_components/ui_card_helper.rb`

```ruby
ui_card_title(title, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | required | Title text |
| `size:` | Symbol | `:lg` | Title size (`:sm`, `:md`, `:lg`, `:xl`) |
| `class:` | String | `nil` | Additional CSS classes |

### ui_card_section

**File:** `app/helpers/ui_components/ui_card_helper.rb`

```ruby
ui_card_section(title, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | required | Section title |
| `class:` | String | `nil` | Additional CSS classes |

### ui_card_footer

**File:** `app/helpers/ui_components/ui_card_helper.rb`

```ruby
ui_card_footer(options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `class:` | String | `nil` | Additional CSS classes |

### ui_accent_card

**File:** `app/helpers/ui_components/ui_accent_card_helper.rb`

```ruby
ui_accent_card(title = nil, variant: :primary, icon: nil, icon_type: :solid, badge: nil,
               heading_level: nil, options: {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | `nil` | Card title |
| `variant:` | Symbol | `:primary` | Color variant (`:success`, `:warning`, `:error`, `:info`, `:primary`, `:secondary`) |
| `icon:` | String | `nil` | FontAwesome icon name |
| `icon_type:` | Symbol | `:solid` | Icon style |
| `badge:` | String | `nil` | Badge HTML content |
| `heading_level:` | Symbol | `nil` | Title as a heading (`:h2`, `:h3` or `:h4`), looking the same; `nil` keeps a div. Anything else raises `ArgumentError` |
| `options:` | Hash | `{}` | HTML options (`:id`, `:class`, `:aria`, `:data`) |

A title that labels the card's content takes `heading_level:` one below the nearest heading above
the card, so a screen reader can move from card to card: `:h3` for a dashboard step under its
group's `<h2>` or a card inside a `ui_section`, `:h2` for a card at page level. A notice, tip or
banner keeps the div.

### page_title

**File:** `app/helpers/page_layout_helper.rb`

```ruby
page_title(title, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | required | Page title text |
| Block | - | `nil` | Optional back link content |

### year_selector

**File:** `app/helpers/page_layout_helper.rb`

```ruby
year_selector(year, options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `year` | Integer | `current_year` | Selected year |
| `years:` | Array | auto-generated | Array of available years |
| `min_year:` | Integer | `1998` | Minimum year |
| `skip_pandemic:` | Boolean | `false` | Skip 2020, 2021 |
| `include_all:` | Boolean | `false` | Add "All" option |

### year_selector_compact

**File:** `app/helpers/page_layout_helper.rb`

```ruby
year_selector_compact(year, options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `year` | Integer | `current_year` | Selected year |
| `years:` | Array | auto-generated | Array of available years |

---

## Data Display

### ui_table

**File:** `app/helpers/table_helper.rb`

```ruby
ui_table(full_width: false, striped: true, responsive: true, caption: nil, **options, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `full_width:` | Boolean | `false` | Table spans full width; otherwise its box fits its content, capped at its parent (wider content scrolls inside it) |
| `striped:` | Boolean | `true` | Alternating row backgrounds |
| `responsive:` | Boolean | `true` | Below `lg`, each row folds into a card of labeled fields; `false` keeps a plain table |
| `caption:` | String | `nil` | Table caption for accessibility |
| `class:` | String | `nil` | Additional CSS classes |

**Builder Methods:**

```ruby
ui_table do |t|
  t.header do
    t.heading "Name"
    t.heading "Hours", right: true
  end
  t.body do
    @items.each do |item|
      t.row do
        t.cell item.name
        t.cell item.hours, right: true
      end
    end
  end
end
```

**Table Builder Methods:**
- `header(&block)` - Table header section
- `heading(value = nil, right: false, center: false, **options, &block)` - Header cell
- `body(&block)` - Table body section
- `row(**options, &block)` - Table row
- `row_header(value = nil, **options, &block)` - Row header cell (th in tbody)
- `cell(value = nil, right: false, center: false, **options, &block)` - Data cell
- `detail_row(id:, colspan: nil, label: nil, **options, &block)` - Expandable detail row

**Pinned header:** in a bounded pane (`container_class: "lg:max-h-[70vh] lg:overflow-y-auto"`), pass `t.header class: TableHelper::PINNED_HEADER_CLASSES` so the column names stay put while the rows scroll. In use on People Search and Salesforce Query.

**Sorting in the browser:** `salesforce_query_heading(t, column, numeric:)` (`app/helpers/admin/salesforce_query_helper.rb`) renders a `th` whose button drives `table_sort_controller.js`; a cell sorts by `data-sort-value` when it has one. Only for rows the server cannot fetch again — see DESIGN-GUIDE > Client-Side Sortable Headings. Extract the heading into the table builder when a second page needs it.

### Expandable detail rows

`detail_row` renders a full-width row that opens beneath its summary row — for
columns whose content is too tall or too wide to sit in the table but which
explain something the summary row already states. It starts closed; pair it with
a `button_action ... controller: "toggle"` control pointing at the same id.

```erb
<%= ui_table striped: false do |t| %>
  <%= t.header do %>
    <%= t.heading "Callsign" %>
    <%= t.heading "Eligible" %>
    <%= t.heading "Why" %>
  <% end %>
  <%= t.body do %>
    <% @rows.each do |row| %>
      <%= t.row do %>
        <%= t.row_header row.callsign %>
        <%= t.cell row.eligible %>
        <%= t.cell do %>
          <%= button_action "Details", :ghost, controller: "toggle",
                            icon: "chevron-down", icon_type: :solid,
                            aria: { controls: dom_id(row), expanded: "false" },
                            data: { toggle_dom_id_value: dom_id(row) } %>
        <% end %>
      <% end %>
      <%= t.detail_row id: dom_id(row), label: row.callsign do %>
        <%# the tall content that used to be a column %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `id:` | String | required | DOM id the toggle control points at |
| `colspan:` | Integer | heading count | Only pass this if the header's `th` count is not the column count |
| `label:` | String | `nil` | Names the row on mobile only. Pass it unless the table is `responsive: false` |

**Two things the helper handles that hand-rolled markup gets wrong:**

- **`colspan` defaults to the table's own heading count**, so adding or removing
  a column cannot leave detail rows under-spanning.
- **The detail cell is excluded from the responsive label scheme.** Mobile
  `data-label`s are matched to headings by cell index, so a cell spanning every
  column would otherwise inherit the *first* heading's label and read
  "Callsign: Teams…" on a phone.

**Pass `striped: false` on any table using detail rows.** `table-row-striped` is
`odd:`/`even:`, which is `:nth-child` — a hidden detail row still counts, so with
two rows per record every summary row lands on the same parity and the stripes
stop telling records apart.

In use on `/vehicles/paperwork` and `/mentoring/convert-prospectives`.

### Responsive ui_table

`ui_table` is responsive by default (since 2026-10-03): it keeps a native
`<table>` on desktop (columns auto-size to their widest content) while each row
becomes a card of labeled fields below the `lg` breakpoint (1024px). Mobile labels are read from `data-label`
attributes the helper auto-derives from the column headings.

The fields inside the card wrap to the width available rather than stacking
unconditionally: one per line on a phone, three or four on a tablet, two lines
instead of eight just under 1024px. A field holding free text outgrows the
others and takes a line of its own. No second breakpoint is involved.

```ruby
ui_table(full_width: true, striped: true, caption: "People") do |t|
  t.header do
    t.heading "Name", width: "200px"
    t.heading "Status"
  end
  t.body do
    @items.each do |item|
      t.row do
        t.row_header item.name
        t.cell item.status
      end
    end
  end
end
```

The responsive layout has no sub-modes — stacking to labeled cards is the only
behavior; `responsive: false` turns it off. Unrecognized keywords (`mode:` and friends) are not options; they land
in `**options` and are emitted as raw attributes on the `<table>` element.

**Responsive Table Builder Methods:**
- `header(&block)` - Table header section
- `heading(value = nil, right: false, center: false, width: nil, **options, &block)` - Header cell
- `body(&block)` - Table body section
- `row(**options, &block)` - Table row
- `row_header(value = nil, **options, &block)` - Row header cell
- `cell(value = nil, right: false, center: false, **options, &block)` - Data cell

### filter_bar

**File:** `app/helpers/ui_components/filter_bar_helper.rb`

**PREFERRED:** Use `filter_bar` whenever a table (or list) page offers user-adjustable filters. It is the standard pattern on filtered index pages (e.g., Action Logs, Slots by Position, Asset Management).

```ruby
filter_bar(chips: [], clear_url: nil, count: nil, id: "filter-bar",
           url: nil, model: nil, scope: nil, open: false,
           toggle_label: "Filters", toggle_icon: "filter", actions: nil, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `chips:` | Array | `[]` | One `{ label:, url: }` hash per active filter; the URL is a plain GET link that drops that one filter |
| `clear_url:` | String | `nil` | Target for "Clear all filters"; rendered only while chips exist |
| `count:` | String | `nil` | Result summary shown at the end of the bar (e.g., `"Showing 9 of 27 slots"`) |
| `id:` | String | `"filter-bar"` | DOM id; panel id is derived as `"#{id}-panel"` |
| `url:` | String | `nil` | When given, the panel opens the standard filter GET form itself — `ui_form(model, url, scope:, method: :get, local: true, no_error_summary: true)` — and the block receives the form builder |
| `model:` | Object | `nil` | Form model passed to `ui_form` (with `url:`) |
| `scope:` | String/Symbol | `nil` | Param scope passed to `ui_form` (with `url:`) |
| `open:` | Boolean | `false` | Start the panel expanded — for a page whose criteria matter before anything has been searched |
| `toggle_label:` | String | `"Filters"` | Text on the disclosure button, before the active-count badge |
| `toggle_icon:` | String | `"filter"` | Icon on the disclosure button — a panel that is a search form rather than a filter can pick an icon that says so (e.g. `"sliders"`) |
| `actions:` | String/Array | `nil` | Markup for the far end of the row, right-aligned — the page's Export CSV `button_link`, or an Array of them. Blank entries render nothing, so a page passes its own visibility rule inline |
| `&block` | Block | required | The filter fields and their Apply submit; without `url:` it provides the whole panel, form included. Raises `ArgumentError` without it |

Renders a slim always-visible row — a "Filters" disclosure button with an
active-count badge, one removable chip per applied filter, a clear-all link,
a result count, and the page's trailing actions — plus a collapsed panel
holding the page's filter form.

```erb
<%= filter_bar id: "action-log-filters",
               chips: action_log_filter_chips(@form),
               clear_url: admin_action_logs_path,
               count: "Showing #{@logs.size} entries",
               url: admin_action_logs_path, model: @form, scope: "filter" do |f| %>
  <%# filter fields + Apply submit (e.g. f.submit "Apply Filters", variant: :secondary) %>
<% end %>
```

**The page's CSV export goes in `actions:`**, not in a `button_row` of its own
above or below the bar. The export is scoped by the filters, so it belongs to
the control that sets them. Use `export_csv_link`, which carries the variant and
icon; the 36px floor comes from `btn-sm` itself (accessibility.css), so no call
site spells it. A page whose export is conditional passes the condition inline;
blank renders no container:

```erb
<%= filter_bar id: "vehicle-registry-filters",
               chips: ..., clear_url: ..., count: ..., url: ...,
               actions: (button_link("Export CSV", :secondary,
                                     vehicles_registry_index_path(@index_params.merge(format: :csv)),
                                     icon: "file-csv", icon_type: :solid) if @result.any?) do |f| %>
  <%# filter fields + Apply submit %>
<% end %>
```

An export whose file is the whole year rather than the filtered view still
rides the bar — one home for the export beats two — and says so in its label
("Export All to CSV"). A second export describing a *different* table on the
page (order lines, size counts) stays beside that table.

Chip-building convention: a small view helper per page (e.g.,
`action_log_filter_chips`) that returns one chip per active filter, each URL
being the current page's params minus that filter. Build the array with the
shared `filter_chips` helper — it handles the label/drop-one-filter loop:

```ruby
def my_filter_chips(year)
  active = params.permit(:status, :kind).to_h.symbolize_keys.compact_blank

  filter_chips(active, { status: "Status", kind: "Kind" }) do |remaining|
    my_index_path(remaining.merge(year:))
  end
end
```

`filter_chips(active, labels, value_label: nil, &url)` maps a `{key => value}`
hash of active filters to the chips array; the block receives the remaining
filters (that entry dropped) plus the dropped key and returns the chip URL.
Pass `value_label:` (a callable of `key, value`) when raw values need
humanizing. `FilterBarHelper::ALL_FILTER_OPTION` (`["All", "all"]`) is the
shared "show everything" select choice; treat `"all"` values as inactive.

Three select-option builders live alongside it, so filtered pages don't
re-implement them:

```ruby
filter_status_options(status_counts, matching: nil)  # [["All","all"], ["Retired (9)","retired"], ...]
filter_signed_up_options                             # [["All","all"], ["Yes","yes"], ["No","no"]]
filter_select_options(labels)                        # [["All","all"], ["Trained","trained"], ...]
```

`filter_select_options` takes the same `{value => label}` hash the page's
chips label those values with, so an option and the chip it sets read alike.

`filter_status_options` takes a `{status => count}` hash and offers only the
statuses the list actually holds, commonest first, ties broken by name. Pass
`matching:` — a second `{status => count}` hash — when the page's other filters
mean a choice would deliver fewer people than the list holds: a select
navigates, so its counts must promise the roster the choice delivers. Ordering
still comes from `status_counts`, so options don't reshuffle as other filters
change, and a status narrowed to no one is still offered, reading `(0)`.

`filter_signed_up_options` renders the tri-state whose values
`SignedUpFilterConcern` accepts; use the two together so the offered set and
the accepted set cannot drift.

### ui_pager

**File:** `app/helpers/ui_components/ui_pager_helper.rb`

```ruby
ui_pager(meta, noun: nil, summary: nil, **options) { |page| url_of_that_page }
```

Where a page of a paged list sits in the whole set ("Page 2 of 7 · 640 messages"),
beside Previous Page and Next Page. A button with no page to go to stays on
screen as a disabled `button_action`, so the pair never moves; the other is a
`button_link`. The block is called only for a page that exists, and returns
that page's URL with the filters carried along.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `meta` | Pagy, Hash | required | The list's Pagy object, offset or countless, or its numbers as `{ page:, total_pages:, total: }`. A hash that also carries `has_previous_page:` / `has_next_page:` has those decide the buttons instead of the page arithmetic, as a Pagy object's own `previous` / `next` do |
| `noun:` | String | `nil` | What the list holds, singular: `"message"` reads "640 messages". Only for a counted list: required unless `summary:` is given, and refused for a countless Pagy |
| `summary:` | String | `nil` | Replaces the whole line, for a page that words it differently: an estimated total, or one never counted (a countless Pagy) |
| `class:` | String | `nil` | Additional CSS classes on the wrapper |

```erb
<%# Built once, shown above the table and again below it. %>
<% pager = ui_pager(@pagy, noun: "request") { |page| admin_request_logs_path(@form.query_params(page:)) } %>

<%# An estimated total: no "of N", and the meta's has_next_page decides Next. %>
<% pager = ui_pager(@meta, summary: action_log_pager_summary(@meta)) { |page| admin_action_logs_path(@form.query_params(page:)) } %>
```

Where a filter or a stale page number can empty the table while the list still
holds rows, render the lower pager outside the empty-state branch so the reader
has a way back. A page whose line reads differently passes `summary:` rather
than getting its own pager helper.

Pagy answers a page past the last with an empty page. A list that shows its
last page instead pages again at `pagy.last`, passing `count: pagy.count` so
it does not count twice (`RequestLog.find_for_query`).

### ui_stat_box

**File:** `app/helpers/ui_components/ui_stat_box_helper.rb`

```ruby
ui_stat_box(value, label, variant: :secondary, icon: nil, icon_type: :solid, size: :md, **options)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `value` | String | required | Metric value to display |
| `label` | String | required | Metric label |
| `variant:` | Symbol | `:secondary` | Color variant (`:success`, `:warning`, `:error`, `:secondary`) |
| `icon:` | String | `nil` | FontAwesome icon name |
| `icon_type:` | Symbol | `:solid` | Icon style |
| `size:` | Symbol | `:md` | Size variant (`:sm`, `:md`, `:lg`) |
| `class:` | String | `nil` | Additional CSS classes |
| `aria:` | Hash | `nil` | ARIA attributes |

### ui_stat_link

**File:** `app/helpers/ui_components/ui_stat_box_helper.rb`

```ruby
ui_stat_link(url, aria_label:, active: false, **options, &block)
```

A `ui_stat_box` that is also a link, for a tile that filters or drills into
what it counts. The block is the box. Never hand-roll the `link_to`: a bare
anchor draws the global link underline through the count and the label, and
turning that off takes the link's focus outline with it, which this replaces
with a focus ring.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `url` | String | required | Where the tile leads |
| `aria_label:` | String | required | The link's name. It replaces the box's text for a screen reader, so it carries the count |
| `active:` | Boolean | `false` | Rings the tile whose filter is showing. That ring has no offset and the focus ring does, so the two read apart |
| `class:` | String | `nil` | Additional CSS classes on the link |

```erb
<%= ui_stat_row do %>
  <%= ui_stat_link swag_distribution_url(category: "shirt"),
                   aria_label: "#{count} shirts — show recipients" do %>
    <%= ui_stat_box count.to_s, "Shirts" %>
  <% end %>
<% end %>
```

### ui_stat_row

**File:** `app/helpers/ui_components/ui_stat_row_helper.rb`

```ruby
ui_stat_row(**options, &block)
```

The container a page's summary metrics sit in. Wraps `ui_stat_box` tiles in a
flex row that tightens one gap step below `lg` so a phone fits more than one
tile per line.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `class:` | String | `nil` | Additional CSS classes |
| `id:` | String | `nil` | Element id, for a turbo-stream target |

```erb
<%= ui_stat_row do %>
  <%= ui_stat_box @people.size.to_s, "People", icon: "users", icon_type: :solid %>
  <%= ui_stat_box @flagged.to_s, "Flagged",
                  variant: @flagged.positive? ? :warning : :secondary,
                  icon: "triangle-exclamation", icon_type: :solid %>
<% end %>
```

Never hand-roll this wrapper. A stat row that needs a grid instead of a wrapping
row is a different pattern and needs approval per `design-rules`.

### ui_badge

**File:** `app/helpers/ui_components/badge_helper.rb`

```ruby
ui_badge(text, variant, options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `text` | String | required | Badge text |
| `variant` | Symbol | required | Color variant (`:primary`, `:secondary`, `:success`, `:warning`, `:error`) |
| `icon:` | String | `nil` | FontAwesome icon name |
| `icon_type:` | Symbol | `:solid` | Icon style |
| `size:` | String | `"xs"` | Text size (`"xs"`, `"sm"`, `"base"`); `"md"` is not a Tailwind text size |
| `class:` | String | `nil` | Additional CSS classes |
| `aria:` | Hash | `nil` | ARIA attributes |

### person_status_badge / person_status_exception_badges

**File:** `app/helpers/person/statuses_helper.rb`

The app-wide vocabulary for rendering a person's status. Never build a per-page status → variant map;
see DESIGN.md's One-Status-Vocabulary Rule for the four standings and their colors.

```ruby
person_status_badge(status, size: "sm")            # always renders; "active" is plain text
person_status_exception_badges(status, size: "base") # [] for "active", else [badge]
person_status_label(person)                        # person_status_badge(person.status)
person_status_standing(status)                     # :norm | :pipeline | :reduced | :context | :anomaly
person_status_norm?(status)
```

Use `person_status_badge` in a table with a dedicated Status column. Use
`person_status_exception_badges` for a roster row (`ui_drill_down_row`'s `badges:`) where status is
incidental and nearly every row reads `active`.

### ui_drill_down_row

**File:** `app/helpers/ui_components/ui_drill_down_row_helper.rb`

One row of an index that drills down into a detail page: a full-width clickable box with a
headline on the left and a chevron on the right. Used by the slots, position credits, swag, and
available sign-ups index pages.

```ruby
ui_drill_down_row(url, title, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `url` | String | required | Destination for the row link |
| `title` | String | required | Headline text (raises `ArgumentError` if blank) |
| `meta:` | String | `nil` | Secondary segment after the title, e.g. `pluralize(count, "slot")` |
| `badges:` | String/Array | `nil` | Rendered `ui_badge` markup; nils are ignored so a conditional badge needs no `if` |
| `blocked:` | Boolean | `false` | Renders a row that cannot be followed — see below |
| `icon:` | String | `"arrow-right"` | FontAwesome icon for the chevron (defaults to `"ban"` when blocked) |
| `class:` | String | `nil` | Additional CSS classes on the link |

Any other options pass through to `link_to`. The block renders a second line below the
headline — a reason the row is unavailable, for example.

The headline reads "Title • meta • badge", each segment optional and separated by bullets.
Pass badges already rendered so each caller keeps its own variant and icon; give them
`size: "base"` so they sit correctly in the `text-lg` headline.

```erb
<%= ui_drill_down_row scheduling_slots_position_path(position.id, year: @year), position.title,
                      meta: pluralize(@slot_counts[position.id], "slot"),
                      badges: (ui_badge("#{inactive} inactive", :warning, size: "base") if inactive.positive?) %>

<%# Blocked row, with the reason underneath %>
<%= ui_drill_down_row path, position.title, meta: pluralize(count, "shift"),
                      blocked: prevent_training_signup?(position.id) do %>
  <div class="text-error">The Online Course must be completed first.</div>
<% end %>
```

**`blocked: true` renders a `<div>`, not a link.** It carries `aria-disabled="true"`, is muted
and shows a not-allowed cursor, drops the hover affordance, and defaults its icon to `"ban"`.
Use the block to say why the row is unavailable — the state alone is not an explanation.

Do not reach for `disabled:` on the link instead: that attribute is inert on an `<a>`, leaving
the row clickable, keyboard-reachable, and visually unchanged. Blocking a row in the UI is an
affordance, not enforcement — the destination action must still refuse on its own.

### ui_progress_bar

**File:** `app/helpers/ui_components/ui_progress_bar_helper.rb`

```ruby
ui_progress_bar(percentage, variant_or_options = {}, options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `percentage` | Integer | required | Progress percentage (0-100) |
| `variant` | Symbol | `:primary` | Color variant (`:primary`, `:secondary`, `:success`, `:error`, `:warning`) |
| `size:` | Symbol | `:md` | Size variant (`:sm`, `:md`, `:lg`, `:xl`) |
| `label:` | String/Boolean | `nil` | Label text or `true` for percentage |
| `projected:` | Integer | `nil` | Percentage for a second, lighter bar behind the main one — where the total lands once something pending counts (sign-ups not yet rangered). Say the projected figure in text beside the bar; the lighter bar is hidden from screen readers |
| `bar_class:` | String | `nil` | Additional classes for bar |
| `aria:` | Hash | `{}` | ARIA attributes |

```erb
<%# Qualifications: time on duty so far, with remaining sign-ups behind it %>
<%= ui_progress_bar item.percentage, projected: item.projected_percentage, aria: { label: "#{name} progress" } %>
```

### credit_timeline_chart

**File:** `app/helpers/scheduling/position_credits_helper.rb`

```ruby
credit_timeline_chart(timeline)   # timeline: a Scheduling::CreditTimeline
```

One of the two approved charts (the other is `hq_forecast_gantt`, below): a
stacked step chart of a position's combined credit rate over time, with its
legend and day axis. `Scheduling::CreditTimeline`
(app/lib) turns the position's `PositionCredit` records into steps between
credit boundaries, ordering series longest-credit-first so a base rate sits at
the bottom and a daily bump rides on top. Plain HTML, no JavaScript: layout is
Tailwind utilities, and the only inline styles are custom properties carrying
the numbers the stylesheet cannot know (`--w` minutes, `--h` and `--y` credits
per hour against `--ymax`), the exception AGENTS.md > CSS Rules allows.

```erb
<%= credit_timeline_chart @timeline %>
```

**Accessibility:** hover readouts are daisyUI tooltips (`data-tip`), text never
wears a series colour, and the page pairs the chart with a Rate Table
`ui_section` listing every step (`credit_segment_makeup` spells a step the same
way in the table, the tooltip and the CSV export), so no value depends on
hovering. Only positive rates are drawn; a zero or negative credit still counts
in a step's total.

**Styling:** `app/assets/stylesheets/components/credit-chart.css` holds the
eight series colours (light and dark steps, validated for colour-vision safety
against the theme's surfaces) and the custom-property geometry; change colours
there and nowhere else. A ninth or later series shares one grey. A third chart
is a new component and needs approval per `design-rules`.

---

### hq_forecast_gantt

**File:** `app/helpers/scheduling/hq_forecast_helper.rb`

```ruby
hq_forecast_gantt(report, day)   # report: an HqForecastReport::Result, day: one of its days
```

A Gantt chart of one day of the HQ Check In/Out Forecast, midnight to
midnight. The top lane holds the check-in/out traffic, one bar per period, as
tall as its share of the day's busiest. A period with an HQ shift scheduled but
no lead, short, or window on duty is striped down its whole column, so a quiet
gap still shows; an hour with no HQ shift at any desk is closed and left plain.
Below it each HQ desk with a shift that day has a lane (a desk with nothing
scheduled gets none, so the pre-event desks appear only on their own days),
with every shift a bar over the hours it runs, labelled signed-up/maximum.
Shifts at one desk that overlap take a lane each. A shift running past
midnight is drawn on both days and squared off where the day cuts it. The
report's days are the calendar dates HQ is open on, and
`HqForecastReport::Result#shifts_on`, `#periods_on` and `#unstaffed_on` pick
what reaches into each; the day badge counts `#unstaffed_on`, so it agrees with
its chart. Plain HTML, no JavaScript. The only inline styles are custom
properties: `--start` and `--span` in minutes from midnight, and `--share` as a
percent of the busiest period.

```erb
<% @days.each do |day| %>
  <%= ui_section day.label, icon: "calendar-day", icon_type: :solid, border: false,
                 badge: hq_forecast_day_badge(@report, day), badge_color: :warning do %>
    <%= hq_forecast_gantt(@report, day) %>
  <% end %>
<% end %>
```

**Accessibility:** every mark says in words what it shows. Traffic bars are
`role="img"` with an `aria-label`. A shift with sign-ups is a link that opens
its sign-up dialog. Its name leads with the count the bar shows ("1/20 signed
up, HQ Window, 06:00 to 18:00"), so speech input can reach it by what is on
screen. Its hit area is the lane's full 40px tall and at least 36px wide: a
shorter bar's link reaches past it on both sides, lifted above its neighbours,
without moving the bar. A shift with no one signed up is `role="img"` and opens
nothing.

daisyUI tooltips repeat the words on hover, and on a shift they also show on
keyboard focus. The mark being read rises over the pinned lane names. A closed
tooltip is `display: none`, so it never stretches the chart or the page, and
every tooltip sits in an `aria-hidden` `.tooltip-content` rather than
`data-tip`, so a screen reader does not read it twice.

The legend keys all four marks, and the striping says what the colour does. A
count that does not fit inside its bar is hidden by a container query rather
than cropped. Below `lg` the chart keeps a 40rem minimum width and scrolls
sideways in its own box, with the lane names pinned and scroll padding that
keeps a focused bar clear of them; the top lane's tooltips open downward there.
In forced colours the marks keep a solid or dashed outline and the focused link
an outline. The chart prints with its colours.

**Styling:** `app/assets/stylesheets/components/hq-forecast.css` holds the two
grid columns, the three-hourly lines, the geometry, the tooltips, the hit areas
and the hatching. The colours are existing tokens: shift bars are
`bg-base-content/80` with `text-base-100`, traffic bars are
`bg-base-content/50`, a shift with no one signed up is `bg-warning` with a
dense hatch, and a gap in the top lane is thin stripes of the warning colour.

## Forms

Complete form documentation: [Form Helper API](form_helper.md)

### ui_form

**File:** `app/helpers/ui_components/ui_form_helper.rb`

```ruby
ui_form(model, url, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | Object | required | ActiveRecord model |
| `url` | String | required | Form submission URL |
| `no_error_summary:` | Boolean | `false` | Skip automatic error summary |
| `layout:` | Symbol | `:vertical` | Default layout (`:vertical`, `:horizontal`, or `:auto`) |

### form_row

**File:** `app/helpers/form_helper.rb`

```ruby
form_row(options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `class:` | String | `nil` | Additional CSS classes |

### form_error_summary

**File:** `app/helpers/form_helper.rb`

```ruby
form_error_summary(model)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | Object | required | ActiveRecord model with errors |

## Autocomplete Field (`autocomplete_field`)

Renders a JSON-powered autocomplete search field with grouped results, filter chips, keyboard navigation, and metadata writeback.

### Form Builder Usage

```ruby
f.autocomplete_field :person_id,
  url: autocomplete_search_path,
  mode: "person_manage",
  label: "Search Person",
  limit: 10,
  meta_mapping: { "id" => "person_id", "status" => "person_status" },
  help_text: "Type to search by callsign or name"
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | String | required | Autocomplete endpoint URL |
| `mode` | String | nil | Search mode identifier |
| `limit` | Integer | 5 | Max results |
| `min_length` | Integer | 2 | Min chars before search |
| `meta_mapping` | Hash | nil | Maps `item.meta` keys to hidden field IDs |
| `submit_on_select` | Boolean | false | Auto-submit form on selection |
| `recents_key` | String | nil | LocalStorage key for recent selections |
| `display_attribute` | Symbol | nil | Model attribute for display value |
| `label` | String | nil | Field label text |
| `help_text` | String | nil | Help text below field |
| `placeholder` | String | "Search…" | Input placeholder |

### Standalone Partial

```erb
<%= render "shared/autocomplete",
  url: autocomplete_search_path,
  mode: "person_manage",
  placeholder: "Search by callsign...",
  hidden_field_name: "person_id" %>
```

See `docs/autocomplete-component.md` for the complete API contract and behavior specification.

## Callsign Chips Field (`callsign_chips_field`)

Several callsigns in one input box, each a removable chip, over `shared/_autocomplete`. Owner-approved
2026-10-18 (messaging rework slice 3, mockup `a-compose`) for the messages compose form's recipients, and
(2026-10-18, by menu) capped at one chip for the HQ window's relay, whose one sender it names.

```erb
<%= f.callsign_chips_field :callsigns, url: suggest_callsigns_messages_path, label: "To", layout: :vertical,
                                       width: "w-full", help_text: "Everyone here sees every reply, in one shared conversation." %>
<%= f.callsign_chips_field :callsigns, url: suggest_callsigns_messages_path, label: "From", max: 1 %>
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | String | required | Suggestions endpoint answering the autocomplete JSON envelope (`Autocomplete::ResponseBuilder`), each item's `value` the callsign |
| `max` | Integer | none | The most chips it holds; a new chip past it replaces the oldest (`data-callsign-chips-max-value`) |
| `placeholder` | String | "Add a callsign…", or "Choose a callsign…" with `max: 1` | The input's placeholder; less its ellipsis, its `aria-label` |
| `label`, `help_text`, `layout`, `width`, `wrapper_class` | | | As every builder field (`build_field`): the label names the input, help and errors describe it |

- The attribute reads an array; each chip sends `<object>[<attribute>][]`. The chips are
  `shared/_callsign_chip` (`name:`, `callsign:`), `inline-flex min-h-9 rounded-full border border-line
  bg-base-200 text-sm`, each with a 36px `btn-ghost btn-square btn-circle` remove button labelled
  "Remove ‹callsign›". Existing tokens only.
- `callsign_chips_controller` makes a chip from a suggestion taken (`autocomplete.change`) or from the text
  typed when Enter finds no suggestion to take, never twice for one callsign (no case), and never sends the
  form on Enter. Removing a chip returns the focus to the input. The server checks every callsign on send.
- The chips sit in `#<field id>_chips`, which a server choice is appended to: the messages page's Find
  Recipient modal (`MessagesConcern#select_callsign`) streams `shared/_callsign_chip` there, or replaces
  the list's one chip (`update`) on the relay, where the controller's cap does not run.
- A suggestion for someone who last signed in over two years ago carries two muted lines saying so
  (`MessagesConcern::AWAY_TOO_LONG`), the warning the relay's old one-person lookup gave.
- `shared/_autocomplete` gained `field_id:` (the text input's id, so the builder's label names it),
  `describedby:`, `wrapper_class:` (its box as a flex item) and `form_field:` (a form field with no hidden
  target: a selection only dispatches `autocomplete.change`) for this.

---

## Interactive Components

### ui_accordion

**File:** `app/helpers/ui_components/ui_accordion_helper.rb`

```ruby
ui_accordion(summary_content, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `summary_content` | String / SafeBuffer | required | Summary label or HTML content |
| `open:` | Boolean | `false` | Render the accordion expanded |
| `unstyled:` | Boolean | `false` | Skip the default compact collapse classes |
| `summary_class:` | String | `nil` | Additional classes for the `<summary>` element |
| `content_class:` | String | `nil` | Additional classes for the content wrapper |
| `summary_html:` | Hash | `{}` | Extra HTML attributes for `<summary>` |
| `content_html:` | Hash | `{}` | Extra HTML attributes for the content wrapper |
| `class:` | String | `nil` | Additional classes for `<details>` |
| `id:` / `data:` / `aria:` | various | `nil` | Standard HTML attributes for `<details>` |

**Usage:**

```erb
<%= ui_accordion("Positions (3 positions)") do %>
  <div class="grid grid-cols-2 gap-1 text-sm text-body">
    ...
  </div>
<% end %>

<%# unstyled: fully custom shells only (e.g. the VC stage cards with their own CSS component) %>
<%= ui_accordion summary, unstyled: true, class: "box vc-stage",
                 summary_class: "vc-stage-summary", content_class: "vc-stage-body" do %>
  ...
<% end %>
```

For a plain disclosure (no collapse styling), use `ui_disclosure` instead.

### ui_disclosure

**File:** `app/helpers/ui_components/ui_disclosure_helper.rb`

```ruby
ui_disclosure(summary_content, options = {}, &block)
```

Native `<details>` / `<summary>` disclosure. Use `ui_accordion` for the DaisyUI collapse-arrow accordion styling;
use `ui_disclosure` for everything else: a bare inline expander (default) or a boxed card with a rotating chevron
(`variant: :card`).

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `summary_content` | String / SafeBuffer | required | Summary label or HTML content |
| `variant:` | Symbol | `:inline` | `:inline` (bare, 36px touch floor built in, keeps the native marker — never add `flex`) or `:card` (boxed, chevron) |
| `subtitle:` | String | `nil` | Card only: secondary line under the title |
| `open:` | Boolean | `false` | Render expanded |
| `summary_class:` | String | `nil` | Additional classes for the `<summary>` element |
| `content_class:` | String | `nil` | Additional classes for the content wrapper |
| `summary_html:` | Hash | `{}` | Extra HTML attributes for `<summary>` |
| `content_html:` | Hash | `{}` | Extra HTML attributes for the content wrapper |
| `class:` | String | `nil` | Additional classes for `<details>` (inline) or the card wrapper (card) |
| `id:` / `data:` / `aria:` | various | `nil` | Standard HTML attributes for `<details>` |

Card titles passed as plain strings render bold; SafeBuffer summaries control their own weight.

The card's wrapper carries `disclosure-card`. It is a hook, not a style: `components/disclosure.css` uses it to
leave a closed card that holds an `instruction-list` off a printed page. A card the reader opened prints open, and a
closed card holding anything else still prints its summary.

A form field inside a closed disclosure is still sent with its form. When a folded field must not be sent (a
choice the reader can no longer see), add `data: { controller: "disclosure-fields", action:
"toggle->disclosure-fields#sync" }`: `disclosure_fields_controller` disables every field inside while the
disclosure is closed, keeping its value. The compose form's Cadre or Delegation select uses it.

**Usage:**

```erb
<%# Inline: small "show more" expanders %>
<%= ui_disclosure "Rejection message", summary_class: "text-sm text-stone-muted" do %>
  <%= simple_format rejection["message"] %>
<% end %>

<%# Card: boxed disclosure with title, optional subtitle, and rotating chevron %>
<%= ui_disclosure "Event categories", variant: :card,
                  subtitle: "Show event filter options",
                  open: @form.event_filters.any? do %>
  ...
<% end %>
```

### ui_data_block

**File:** `app/helpers/ui_components/ui_data_block_helper.rb`

```ruby
ui_data_block(content, max_height: nil)
```

A scrollable, monospaced block for machine output: pretty-printed JSON, a request payload, an exception backtrace.
Used by the admin log pages, each of which had its own copy before.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `content` | String | required | The text to show. Escaped, never interpreted |
| `max_height:` | String | `nil` | A whole max-height class — `max-h-56`, `max-h-80`. Omit it and the block grows to its content |

```ruby
ui_data_block(error_log_pretty_data(row), max_height: "max-h-80")
```

How much of a payload is worth showing before it scrolls is a per-page judgement, which is why the height is the
caller's and not baked in.

### ui_icon_item

**File:** `app/helpers/ui_components/ui_icon_item_helper.rb`

```ruby
ui_icon_item(icon, icon_type = :solid, tone: nil, &block)
```

One line of an icon list: a FontAwesome icon and whatever the block says beside it. A helper rather than a partial
because the content is free-form — these lines hold sentences, `<strong>` runs, links and conditionals, not a label
local. The caller owns the surrounding `<ul>`.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `icon` | String / Symbol | required | FontAwesome icon name |
| `icon_type` | Symbol | `:solid` | `:solid` or `:regular` |
| `tone:` | String | `nil` | A whole icon colour class — `icon-success`, `icon-error`, `text-stone-subtle`. Omit it and the icon takes the surrounding ink |
| `&block` | Block | required | The line's content, wrapped in a `<span>` |

```erb
<ul class="space-y-2">
  <%= ui_icon_item "circle-check", :solid, tone: "icon-success" do %>
    Can be transferred to anyone
  <% end %>
  <%= ui_icon_item "circle-xmark", :solid, tone: "icon-error" do %>
    Cannot be sold
  <% end %>
</ul>
```

Renders `<li class="flex items-start gap-2">` with the icon at `mt-0.5 shrink-0`: `items-start` puts the icon on the
first line of a label that wraps, and the 2px nudge sits it on that line's optical centre.

### modal

**File:** `app/helpers/modal_helper.rb`

```ruby
modal(options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `id:` | String | auto-generated | Modal ID |
| `close_button:` | Boolean | `true` | Include close button |
| `class:` | String | `nil` | Additional CSS classes |

**Builder Methods:**

```ruby
modal(id: "my-modal") do |m|
  m.title "Modal Title"
  m.body { "Content" }
  m.footer do
    button_row do
      button_action "Confirm", :primary, data: { action: "controller#action" }
      modal_close_button "Cancel"
    end
  end
end
```

**Modal Builder Methods:**
- `title(header = nil, options = {}, &block)` - Modal title with close button
- `body(options = {}, &block)` - Modal body content
- `footer(options = {}, &block)` - Modal footer (wrapped in button_row)

### modal_dialog

**File:** `app/helpers/modal_helper.rb`

The scaffold every Turbo form dialog shares: the `turbo_frame_tag "modal"`
wrapper, a modal without the auto-appended close footer (the form supplies its
own), and the title. The block renders the body.

```ruby
modal_dialog(title:, id: nil, frame: "modal", **options, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title:` | String | required | Modal title (any expression) |
| `id:` | String | auto-generated | Modal ID |
| `frame:` | String/false | `"modal"` | Turbo frame to wrap in; pass `false` for partials streamed into an existing frame |
| `**options` | Hash | — | Passed to `modal` (`size:`, `placement:`, ...) |

```erb
<%= modal_dialog id: "assign-dialog", title: "Assign Application" do %>
  <%= form_with url: ..., builder: AppFormBuilder, data: { turbo_frame: "_top" } do |f| %>
    <%= f.select ... %>
    <%= modal_form_footer submit: "Save Assignment" %>
  <% end %>
<% end %>
```

### modal_form_footer

**File:** `app/helpers/modal_helper.rb`

The standard dialog-form footer: a submit plus a Cancel that closes the
dialog. Footers with more than one submit keep an explicit `button_row`.

```ruby
modal_form_footer(form = nil, submit:, close: "Cancel", **submit_options)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `form` | FormBuilder | `nil` | Pass `f` to submit through the builder; omitted, a bare `submit_button` is used |
| `submit:` | String | required | Submit label |
| `close:` | String | `"Cancel"` | Close-button label |
| `**submit_options` | Hash | — | Passed to the submit (`variant:`, ...) |

### confirm_modal

**File:** `app/helpers/modal_helper.rb`

```ruby
confirm_modal(options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title:` | String | `"Confirm"` | Modal title |
| `message:` | String | `"Continue?"` | Confirmation message |
| `confirm_label:` | String | `"Confirm"` | Confirm button label |
| `cancel_label:` | String | `"Cancel"` | Cancel button label |
| `variant:` | Symbol | `:primary` | Confirm button variant; `:error` for a destructive action |
| `method:` | String | `"get"` | HTTP method |

### modal_close_button

**File:** `app/helpers/modal_helper.rb`

```ruby
modal_close_button(label = "Close")
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `label` | String | `"Close"` | Button label |

### button_row

**File:** `app/helpers/button_helper.rb`

```ruby
button_row(options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sticky:` | Boolean | `false` | Stick to bottom on mobile |
| `class:` | String | `nil` | Additional CSS classes |

`button_row` renders nothing when its block comes back blank, so a row whose every
button is conditional disappears instead of leaving an empty flex container. The
surrounding spacing is the caller's (`<div class="my-4">`), not the row's — `.button-row`
sets only `display`, `flex-wrap` and its gaps — so a wrapper that would otherwise be left
holding nothing still needs the same guard.

A `sticky: true` row is fixed to the bottom edge below `lg`, and the helper emits a
`.button-row-spacer` in front of it to hold its place in the flow. The helper counts the
controls it rendered and `components/buttons.css` turns the count into the row's own height,
so a conditional Delete button sizes its own spacer. See DESIGN-GUIDE, "Sticky Save Button
(Mobile)".

On a page with a `filter_bar`, the CSV export does **not** belong in a `button_row` — it
goes in the bar's `actions:`, built with `export_csv_link`.

### export_csv_link

**File:** `app/helpers/button_helper.rb`

```ruby
export_csv_link(url, label = nil, options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `url` | String | required | The CSV endpoint, or a `data:` URI for a client-side download |
| `label` | String | `"Export CSV"` | A whole-report export says so: `"Export All to CSV"` |
| `variant:` | Symbol | `:secondary` | Only where an export is the page's primary action |
| `options` | Hash | `{}` | Passed to `button_link` — `download:`, `data:`, `class:` |

**Every CSV export in the app goes through this helper.** It carries the
`file-csv` icon, the secondary variant, and the 36px touch floor, so no call
site spells them and none can drift. On a page with a `filter_bar`, the result
belongs in the bar's `actions:`.

```erb
<%= export_csv_link(records_path(format: :csv)) %>
<%= export_csv_link(records_path(year: @year, format: :csv), "Export All to CSV") %>
```

### button_link

**File:** `app/helpers/button_helper.rb`

```ruby
button_link(label, variant, url, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `label` | String | required | Button label (or use block) |
| `variant` | Symbol | required | Button variant (`:primary`, `:secondary`, `:tertiary`, `:success`, `:error`, `:warning`, `:dark`, `:ghost`) |
| `url` | String | required | Link URL |
| `icon:` | String | `nil` | FontAwesome icon name |
| `icon_type:` | Symbol | `:regular` | Icon style |
| `size:` | String | `"sm"` | Size (`"xs"`, `"sm"`, `"base"`, `"lg"`, `"xl"`) |
| `disabled:` | Boolean | `false` | Disable button |
| `class:` | String | `nil` | Additional CSS classes |
| `method:` | Symbol | `nil` | HTTP method, submitted by Turbo (`data-turbo-method`) |
| `params:` | Hash | `nil` | Query params added to the URL; with `method:` Turbo submits them as the form fields |

### button_action

**File:** `app/helpers/button_helper.rb`

```ruby
button_action(label, variant, controller: nil, **options)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `label` | String | required | Button label |
| `variant` | Symbol | required | Button variant |
| `controller:` | String | `nil` | Stimulus controller on the button itself. Never one that wraps it: that starts a second copy owning none of the wrapper's targets. Acting on a wrapper takes only `data: { action: … }` |
| `icon:` | String | `nil` | FontAwesome icon name |
| `icon_type:` | Symbol | `:regular` | Icon style |
| `size:` | String | `"sm"` | Button size |
| `disabled:` | Boolean | `false` | Disable button |
| `class:` | String | `nil` | Additional CSS classes |

### submit_button

**File:** `app/helpers/button_helper.rb`

```ruby
submit_button(label = nil, options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `label` | String | `"Submit"` | Button label |
| `variant:` | Symbol | `:primary` | Button variant |
| `disabled:` | Boolean | `false` | Disable button |
| `size:` | String | `"sm"` | Button size |

### cancel_button / cancel_link

**File:** `app/helpers/button_helper.rb`

```ruby
cancel_button(url, label = nil, options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `url` | String | required | Cancel destination URL |
| `label` | String | `"Cancel"` | Button label |
| `size:` | String | `"sm"` | Button size |

### edit_link

**File:** `app/helpers/button_helper.rb`

```ruby
edit_link(url, label = nil, options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `url` | String | required | Edit URL |
| `label` | String | `"Edit"` | Button label (secondary style) |
| `size:` | String | `"sm"` | Button size |
| `icon:` | String | `"pen-to-square"` | Overrides the built-in icon; every edit control carries it by default |

### delete_button

**File:** `app/helpers/button_helper.rb`

```ruby
delete_button(url, label = nil, options = {})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `url` | String | required | Delete URL |
| `label` | String | `"Delete"` | Button label |
| `size:` | String | `"sm"` | Button size |
| `confirm_message:` | String | `nil` | Message for the standard confirm dialog |
| `confirm_modal:` | Hash | `nil` | `confirm_modal` options for a custom dialog |

Either dialog's Confirm button is `:error` (red) unless `confirm_modal:` passes its own `variant:`.

### clipboard_button

**File:** `app/helpers/ui_components/clipboard_helper.rb`

```ruby
clipboard_button(text, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `text` | String | required | What a press copies |
| `label:` | String | `"Copy to clipboard"` | The copy icon's accessible name. Pass one wherever a page shows more than one copy control |
| `use_flex:` | Boolean | `false` | For a block of several lines: the icon sits beside the block, centred on its height |

Renders the block, then a copy icon. The block is what is shown; `text` is what is copied.

```erb
<%= clipboard_button person.email, label: "Copy email address" do %>
  <%= mail_to person.email %>
<% end %>
```

A copy is confirmed by a "Copied" tip on the control, put there by the `copy-to-clipboard` controller
(`app/javascript/controllers/copy_to_clipboard_controller.js`). Behaviour, placement, and styling:
`docs/DESIGN-GUIDE.md` > Copy Confirmation.

A full button that copies takes the same controller and is confirmed the same way. It needs an icon:
the controller animates it.

```erb
<%= button_action "Copy Email List", :secondary, controller: "copy-to-clipboard",
                  icon: "copy", icon_type: :regular,
                  data: { action: "copy-to-clipboard#copy",
                          copy_to_clipboard_content_value: emails.join(", "),
                          copy_to_clipboard_success_class: "btn-copy-success" } %>
```

Covered by `test/system/copy_to_clipboard_test.rb`.

### sidebar_menu

**File:** `app/helpers/sidebar_helper.rb`

```ruby
sidebar_menu(theme = "me", id: "sidebar-drawer", width: "w-65 lg:w-45", &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `theme` | String | `"me"` | Theme (`"me"`, `"admin"`, `"hq"`) |
| `id:` | String | `"sidebar-drawer"` | Drawer ID |
| `width:` | String | `"w-65 lg:w-45"` | Drawer width classes |

### sidebar_section

**File:** `app/helpers/sidebar_helper.rb`

```ruby
sidebar_section(title, theme: "me", &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | required | Section title |
| `theme:` | String | `"me"` | Theme name |

### sidebar_submenu

**File:** `app/helpers/sidebar_helper.rb`

```ruby
sidebar_submenu(title, icon: nil, icon_type: "regular", theme: "me")
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | required | Submenu title |
| `icon:` | String | `nil` | FontAwesome icon name |
| `icon_type:` | String | `"regular"` | Icon style |
| `theme:` | String | `"me"` | Theme name |

### sidebar_item

**File:** `app/helpers/sidebar_helper.rb`

```ruby
sidebar_item(title, url, icon: nil, icon_type: "regular", badge: nil, badge_variant: :error, use_turbo: false, active: nil, active_prefix: false, theme: "me", root: false, **html_options)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | required | Item title |
| `url` | String | required | Link URL |
| `icon:` | String | `nil` | FontAwesome icon name |
| `icon_type:` | String | `"regular"` | Icon style |
| `badge:` | String | `nil` | Badge text/number |
| `badge_variant:` | Symbol | `:error` | Badge color (`:error`, `:success`, `:warning`, `:info`, `:default`) |
| `use_turbo:` | Boolean | `false` | Enable Turbo navigation |
| `active:` | Boolean | auto-detect | Manually set active state |
| `active_prefix:` | Boolean | `false` | Keep the item active for descendant routes with the same path prefix |
| `theme:` | String | `"me"` | Theme name |
| `root:` | Boolean | `false` | Root path for active detection |

### sidebar_submenu_item

**File:** `app/helpers/sidebar_helper.rb`

```ruby
sidebar_submenu_item(title, url, **options)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | String | required | Item title |
| `url` | String | required | Link URL |
| `**options` | Hash | `{}` | Same as `sidebar_item` |

---

## Notifications

### ui_callout_box

**File:** `app/helpers/ui_components/notice_box_helper.rb`

```ruby
ui_callout_box(type, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `type` | Symbol | required | Box type (`:success`, `:info`, `:warning`, `:error`, `:secondary`) |
| `accent:` | Boolean | `false` | Use accent style (left border) |
| `title:` | String | `nil` | Box title |
| `box_header:` | Boolean | `false` | Use as header style |
| `icon:` | String/Boolean | auto | FontAwesome icon name or `false` to hide |
| `icon_type:` | Symbol | `:solid` | Icon style |
| `class:` | String | `nil` | Additional CSS classes |

### ui_alert_banner

**File:** `app/helpers/ui_components/notice_box_helper.rb`

```ruby
ui_alert_banner(label, type, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `label` | String | required | Banner label/title |
| `type` | Symbol | required | Banner type (`:success`, `:info`, `:warning`, `:error`) |
| `class:` | String | `nil` | Additional CSS classes |

### ui_empty_state

**File:** `app/helpers/ui_components/notice_box_helper.rb`

```ruby
ui_empty_state(message = nil, options = {}, &block)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `message` | String | `nil` | Message text (or use block) |
| `icon:` | String | `nil` | FontAwesome icon name |
| `icon_type:` | Symbol | `:regular` | Icon style. Regular draws only the icons in `lib/fontawesome/regular-icons.txt`: pass `:solid` for any other (`fa_icon` raises in development and test) |
| `class:` | String | `nil` | Additional CSS classes |

### ui_toast_render

**File:** `app/helpers/ui_components/toast_helper.rb`

```ruby
ui_toast_render(toast_message, toast_type, for_streaming = false)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `toast_message` | String | required | Toast message text |
| `toast_type` | Symbol | required | Toast type (`:success`, `:info`, `:warning`, `:notice`, `:error`). Error and alert toasts stay until closed; the rest close after six seconds. See `docs/DESIGN-GUIDE.md` > Flash Messages |
| `for_streaming` | Boolean | `false` | Render for Turbo Stream |

### ui_toast_stream

**File:** `app/helpers/ui_components/toast_helper.rb`

```ruby
ui_toast_stream(message, type)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `message` | String | required | Toast message text |
| `type` | Symbol | required | Toast type |

---

## Utilities

### callsign_link

**File:** `app/helpers/link_helper.rb`

```ruby
callsign_link(person, path = nil, **options)
```

Person link showing their callsign, styled with `LinkHelper::TABLE_LINK_CLASSES`
(`link link-primary`, deliberately under the touch floor for dense table rows). Defaults to the person
page; pass a path to point somewhere else. Use the constant directly for
non-callsign table links (`class: LinkHelper::TABLE_LINK_CLASSES`).

```erb
<%= callsign_link row.person %>
<%= callsign_link row.person, person_tickets_provisions_path(row.person) %>
```

### bulk_select

**File:** `app/helpers/ui_components/bulk_select_helper.rb`

Markup kit for the `checkbox-select-all` Stimulus controller.

```erb
<%= bulk_select do %>
  <%= bulk_select_all label: "Select every problem-free item" %>   <%# bar form + live count %>
  <%= bulk_select_all aria_label: "Select all slots" %>            <%# compact heading-cell form %>
  ...
  <%= bulk_select_checkbox "ids[]", row.id, checked: false,
                           id: "row-#{row.id}", aria_label: "Select #{row.name}",
                           skip_select_all: !row.selectable? %>
  <%= bulk_select_count %>  <%# optional extra "N selected" text %>
<% end %>
```

Submit buttons opt in with `data: { checkbox_select_all_target: "submit" }`.

The count renders "0 selected" on the server, so the controller has nothing to
write into its live region on load. A page whose rows start ticked passes how
many to whichever renders the count: `bulk_select_all label: ..., selected: rows.count(&:ready?)`
or `bulk_select_count selected: n`. A count left wrong still corrects itself on
load, but is then announced out of context.

### fa_icon

**File:** `app/helpers/icon_helper.rb`

```ruby
fa_icon(name, style = nil, html_options = {}, text = nil)
```

`style` is positional, and the options come after it: `fa_icon "ban", :solid, end: 2`,
never `fa_icon "ban", end: 2`. Written first, the options land in `style`, the icon gets no
style class, and it draws nothing.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | String/Symbol | required | A Font Awesome Free 7.1 icon name (`_` reads as `-`) |
| `style` | Symbol/String | `"regular"` | Icon style (`"regular"`, `"solid"`, `"brands"`) — Free styles only. `nil` means regular |
| `html_options` | Hash | `{}` | The options below, plus any HTML attribute |
| `text` | String | `nil` | Text to append after icon |

| Option (in `html_options`) | Type | Default | Description |
|-----------|------|---------|-------------|
| `start:` | Integer | `nil` | Start margin spacing, `1` or `2` (`ms-1`, `ms-2`). Never inside a button: the `.btn` gap already spaces it |
| `end:` | Integer | `nil` | End margin spacing, `1` or `2` (`me-1`, `me-2`). Same rule |
| `size:` | String | `nil` | Icon size (`"xs"`, `"sm"`, `"lg"`, `"2x"`, etc.) |
| `fixed:` | Boolean | `false` | Fixed width icon |
| `class:` | String | `nil` | Additional CSS classes |
| `label:` | String | `nil` | What the icon means, for an icon with no words beside it. Sets `title` and appends the label as a screen-reader-only sentence (every icon is `aria-hidden`) |

In development and test, `fa_icon` raises `ArgumentError` for a name that is not an icon in
Font Awesome Free 7.1 (or one the generated subset lacks: rerun `bin/rails fontawesome:subset`),
and for a style other than regular, solid or brands. Production runs no check. For a literal
name no test renders, `test/helpers/icon_helper_test.rb` scans `app/` and `config/` for the
names written as the first argument of `fa_icon` or `ui_icon_item`, as `icon:` and `empty_icon:`
values, as the `name:` of a `{ name:, style: }` map, and as `fa-` classes.

The regular style draws only the icons in `lib/fontawesome/regular-icons.txt`. Font Awesome
Free's regular font has no glyph for any other name, and the browser draws a crossed box in its
place, so pass `:solid` for an icon not on the list. In development and test `fa_icon` raises
`ArgumentError` for a regular icon that is not on it, whether the style is `nil`, `:regular` or
`"regular"`, and the same test file checks each `fa-regular fa-NAME` class written by hand. The
list is generated from the font, never edited: after a Font Awesome upgrade, rerun
`node bin/fontawesome_regular_icons.js`.

### nav_link_to

**File:** `app/helpers/link_helper.rb`

```ruby
nav_link_to(name, path, options = {}, is_root = false)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | String | required | Link text |
| `path` | String | required | Link URL |
| `options` | Hash | `{}` | HTML options |
| `is_root` | Boolean | `false` | Exact match for root path |

### turbo_empty_frame

**File:** `app/helpers/turbo_helper.rb`

```ruby
turbo_empty_frame(target_id)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `target_id` | String | required | Turbo frame ID to empty |

### turbo_response

**File:** `app/helpers/turbo_helper.rb`

```ruby
turbo_response(streams)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `streams` | Array | required | Array of Turbo Stream actions |

### scroll-to-top (Stimulus)

**File:** `app/javascript/controllers/scroll_to_top_controller.js`

```erb
<div data-controller="scroll-to-top" hidden></div>
```

Scrolls the window to the top when the element renders. Required at the top of every results page rendered at 422 from a POST — Turbo keeps the submitting page's scroll position on form-submission renders, landing the reader at the old submit button instead of the summary. Do **not** add it to form re-renders with validation errors; preserved scroll is correct there. Assert it in the controller test with `assert_select "[data-controller=scroll-to-top]"`.

### review-pane (Stimulus)

**File:** `app/javascript/controllers/review_pane_controller.js`

```erb
<div class="flex flex-col lg:flex-row gap-4" data-controller="review-pane">
  <div><%# the list: each line is a.review-line[data-turbo-frame=uf-pane][data-review-pane-target=line][data-review-id] %></div>
  <aside class="review-pane" data-review-pane-target="pane">
    <%= turbo_frame_tag "uf-pane", target: "_top", data: { turbo_action: "advance" } do %>
      <div data-review-id="<%= person.id %>">…</div>
    <% end %>
  </aside>
</div>
```

Selecting a line is not script: each line's link names the pane's frame, which advances the URL to
`?person=`, so the link fetches the pane alone and swaps only it. The list is never re-rendered, so
focus stays on the link the reader activated. The controller keeps the list in step with the pane:
on connect and on `turbo:before-frame-render` it reads what the pane shows (`data-review-id`, on the
pane's content and on each line: a person id on the review pages, a thread id in the mailbox), keeps
it, and moves the lines' `aria-current` to that one; a line rendered later (a streamed or lazily
loaded list) takes the kept id as it connects. It also decides where the pane sits: from `lg` up in
the workspace's second column, below it under the selected line, scrolling that line back into view
when the pane leaves from above it. It moves the pane on `turbo:load`, once Turbo has finished the
visit: moving a `<turbo-frame>` while it loads disconnects it and cancels its request. On connect (a
full load, a redirect back, a Back restore) it scrolls the selected line to the top, because the
layout scrolls an inner element whose position neither a load nor Turbo's snapshot keeps.

`data-review-pane-park-value="false"` is for a workspace whose pane is hidden below `lg` (the
mailbox, `common/messages/_workspace`). The pane then stays put. Its frame is rendered `disabled`
and the controller enables it from `lg` up only -- Turbo hands a link to a frame only while the frame
is enabled -- so below `lg`, and before the controller loads, a line's link is an ordinary page
visit. On connect it only brings an out-of-view line into view (`block: "nearest"`), since a header
sits above that list, or the line as it arrives in a lazily loaded list. When the viewport crosses
`lg` it sets the pane and the `list` target's `hidden lg:block` to what a load of the current
address would render, so a record opened in the frame stays on screen once the viewport narrows.

The pane's CSS is `components/review-pane.css`: from `lg` up the `review-pane` class caps its height
at the viewport less the navbar and its offsets, so a long history scrolls inside the sticky pane;
`.review-line[aria-current=true]` marks the selected line and `.review-line-flagged` tints a raised
Personnel flag's line red unless it is selected. In use on VC › Unified Flagging, In-Person
Training › Unified Flagging, People › Unified Flagging and Mentoring › Post Season Summary,
Potential Alphas and Alpha Status
(`app/views/common/unified_flagging/_review_workspace.html.erb`), and on the three Messages
mailboxes (`app/views/common/messages/_workspace.html.erb`, frame `messages-pane`).

A link inside the pane that loads another record names the pane's frame the way a line does
(`data: { turbo_frame: "messages-pane" }`): the controller then marks that record's line on
`turbo:before-frame-render`, as for a click in the list, and below `lg` the disabled frame makes it a
page visit. The mailbox's Next Unread `button_link` (Person and HQ, `_messages_panel_header`) is one.
A link in the pane that should leave it names `_top` instead: the header sits in a frame of its own
(`messages-panel-header`), which would otherwise capture it. Inside the HQ shell, beside its 191px
summary column, the mailbox's list column is under 20rem from `lg` to about 1210px (245px at 1024,
308px at 1180, measured 2026-10-18), so there the pane drops under the list: `components/hq-window.css`
queries the workspace's own width (`.messages-workspace`, a container under 50rem) and sets the columns
stacked. The pane stays put (park=false) and its frame stays enabled, so a row still loads it. From
about 1230px (20.5rem) the split holds, 348px at 1280 and 412px at 1440.

**Server side** (`UnifiedFlaggingConcern`): `review_selection(summaries)` sets `@selected` and
`@history` from `?person=`, among the rows shown; `review_pane_request?` is true for a
`Turbo-Frame: uf-pane` request, which `render_review_pane(**extras)` answers with `_review_pane`
alone. A page with its own `#index` calls both before building its list.

**Partials** (`app/views/common/unified_flagging/`, strict locals): `_review_workspace` is a layout
(`pane:`; the block is the list's sections); `_review_list` (`rows:`, `year:`, `selected_id:`,
`extra:` — a partial path for a page's own word on each line); `_list_row` (`summary:`, `year:`,
`selected_id:`, `extra:`); `_review_pane` (`summary:`, `history:`, `year:`, `extra_chips:`,
`extra_meta:` — partial paths for a page's own chips and line, which Post Season keeps in
`Mentoring::PostSeasonSummaryHelper::PANE_EXTRAS`); `_name_line` (`person:`, `chips:`);
`_signal_line` (`summary:`, `lead:`); `_note_buttons` (`person:`, `year:`); `_history` (`person:`,
`history:`, `year:`, `note_buttons:`); `_group_tiles` (`counts:`, `active:`, `year:` — the stat
tiles, one per group of `UnifiedFlaggingConcern#unified_flagging_group_meta`, which a page
overrides to word its groups). The pattern and its rules: `design-layouts` › Pattern 7.

### thread-live (Stimulus)

**File:** `app/javascript/controllers/thread_live_controller.js`

```erb
<%= tag.div id: "messages-thread", role: "log", aria: { label: "Conversation", live: "polite" },
            data: { controller: "thread-live", thread_live_url_value: mark_read_message_path(message) } do %>
```

The open thread on Me › Messages (ruling D6 of the messaging rework). A reply lands in
`#messages-thread` live, appended by a turbo-stream broadcast (`PersonMessage#announce_to_recipient`,
`turbo_stream_from message_owner, message` in `_messages_panel`); when a card the server marked
`data-unread` -- someone else's, not yet read by the owner -- is added while
`document.visibilityState` is `visible`, the controller posts the URL (`MessagesConcern#mark_read`,
idempotent) as a turbo-stream request, and the answer updates the navbar envelope, the Unread tab's
count, the thread's row and the cards. A card added in a hidden tab stays New. It watches with a
MutationObserver, not Stimulus targets, because target callbacks also fire for the cards already on
the page when it connects. Only /me renders it: Person and HQ never mark a thread read by looking.

---

### scroll-to-element (Stimulus)

**File:** `app/javascript/controllers/scroll_to_element_controller.js`

```erb
<div data-controller="scroll-to-element" data-scroll-to-element-id-value="group-7" hidden></div>
```

Brings one element into view when the page renders, named by its id. Use it to put the reader back
beside the record they just changed after an edit redirects them to a list or a parent page.

**A `#fragment` cannot do this job after a form submission.** Turbo takes the page to visit from the
response's URL, and a URL's fragment is not part of it, so `redirect_to path(anchor: "group-7")` from a
POST, PATCH, or DELETE is silently dropped and the reader lands at the top. (Fragments still work for
ordinary link visits.) Carry the id as a query parameter instead, and render this marker for it:

```ruby
# Controller: only a record actually on the page, so a stale link scrolls to
# nothing -- and to_s first, or `?group[]=1` arrives as an Array and raises.
@focus_group_id = @groups.map(&:id).find { |id| id == params[:group].to_s.to_i }
```

It respects `prefers-reduced-motion`. In use on Survey Management
(`app/views/communication/surveys/show.html.erb`).

**Measuring it:** `window.scrollY` stays `0` in this application — `body` is `h-screen` and the scroller
is an inner `div.drawer-content`. Read `document.querySelector(".drawer-content").scrollTop` instead.

---

## Color Variants

Most components accept a `variant:` parameter with these values:

| Variant | Color | Use Case |
|---------|-------|----------|
| `:primary` | Signal Blue (brand) | Primary actions, info |
| `:secondary` | Neutral gray | Secondary actions, default state |
| `:success` | Green | Completed, approved, positive |
| `:warning` | Amber/yellow | Pending, caution, attention needed |
| `:error` | Red | Error, destructive, urgent |
| `:info` | Blue | Information (limited use) |
| `:tertiary` | Transparent | Alias of `:ghost` (legacy) |
| `:dark` | `btn-neutral` | Dark-chrome contexts only |
| `:ghost` | Transparent | Minimal buttons |

## Button Sizes

| Size | Text Size | Use Case |
|------|-----------|----------|
| `"xs"` | `text-xs` | Icon-only, compact sidebars (avoid for user-facing text) |
| `"sm"` | `text-sm` | Default, most buttons |
| `"base"` | `text-base` | Larger emphasis |
| `"lg"` | `text-lg` | Hero CTAs |
| `"xl"` | `text-xl` | Extra large prominence |
