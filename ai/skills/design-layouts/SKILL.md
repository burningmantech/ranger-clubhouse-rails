---
name: design-layouts
description: Page layout patterns and responsive breakpoints for Clubhouse 3. Use when creating new pages, implementing /me route layouts, or working with responsive designs.
---




# Design Layouts

## Responsive Breakpoints

**PREFERRED:** Write for **mobile and desktop**, and let `lg:` carry the difference. That is the
shape of almost every page here, and a layout needing a third tier usually needs a simpler layout.

### Breakpoint Policy

| Breakpoint | Size | Usage | Priority |
|------------|------|-------|----------|
| (none) | < 1024px | Mobile/default styles | **PREFERRED** - always start here |
| `lg:` | ≥ 1024px | Desktop styles | **PREFERRED** - the structural fold |
| `xl:` | ≥ 1280px | Large desktop | Optional refinements only |
| `sm:` | 640px | Field widths via `AppFormBuilder` `width:` (`w-full sm:w-48`) | **AVOID** elsewhere - one sanctioned use |
| `md:` | 768px | The phone/not-phone floor | **AVOID** - two sanctioned uses only |

Write the fold as `(width < theme(--breakpoint-lg))`, never `max-width: 1024px` — both bounds are
inclusive, so a `max-width` fold matches at exactly 1024px at the same moment `lg:` does.

### Between the two, let the content decide

A tablet is a real admin device here — an 820pt screen fits two or three things per line — but the
width where that becomes true depends on the content, not the device. Reach for a wrapping flex row
or a `min-width` floor on the items before reaching for a breakpoint. This is how the responsive
table fold packs fields into columns on a tablet and one per line on a phone without naming either.

`md:` is **not** a general-purpose breakpoint. It marks one fact — below 768px controls cannot sit
side by side — and has exactly two sanctioned uses, both in `components/buttons.css`: `.button-row`
stacking, and `.button-row-spacer`, the sticky row's spacer, whose height `ButtonHelper#button_row`
derives from the controls it rendered. Never use `md:` for layout tiers, grid columns, or
show/hide.

`sm:` has one sanctioned use of its own: the `width:` option on form fields (`w-full sm:w-48`),
full width on a phone and the measured width from 640px up. Nothing else uses it.

The HQ window additionally scales itself above 1800px for shared-screen reading; that lives in
`components/hq-window.css` and needs no work from callers. See DESIGN-GUIDE.md → Responsive
Breakpoints.

### Examples

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
```

### Progressive Grid Columns

```erb
<%# Two tiers: mobile and desktop %>
<div class="grid grid-cols-2 lg:grid-cols-4 gap-4">...</div>

<%# Three tiers: mobile, desktop, large desktop %>
<div class="grid grid-cols-2 lg:grid-cols-4 xl:grid-cols-6 gap-4">...</div>
```

---

## Page Layouts

Patterns 1–5 are the baseline every user-facing page under `/me` follows. Pattern 6 is the
admin records shape and applies to management sections outside `/me`; Pattern 7 is the
review shape for reading many records one at a time.

### Layout Pattern Selection

**PREFERRED:** Use this decision tree to select the correct layout pattern:

| If the page... | Use Pattern | Key Components |
|----------------|-------------|----------------|
| Shows overview with stats/progress | **Dashboard** | hero_panel + stats + progress + quick actions + sections |
| Lists multiple items to browse | **Directory/List** | hero_panel + optional scroll nav + item sections |
| Shows detail for a single item | **Detail** | hero_panel + back_to + info sections |
| Collects user input | **Form** | hero_panel + back_to + ui_form + sticky buttons |
| Manages many records in a few categories | **Records Management** | category index of `ui_drill_down_row` → per-category `filter_bar` + `ui_table` |
| Reads many records one at a time | **Review Pane** | sections of one-line links → the selected record's history in a sticky pane, its own Turbo frame |
| Doesn't fit above patterns | **Special** | hero_panel + tabs or custom layout |

---

## Pattern 1: Dashboard (Overview + Stats)

**When to use:** Main landing pages, schedule views, dashboards with metrics.

```erb
<%= hero_panel icon: "icon", heading_level: :h1 do |panel| %>
  <% panel.title do %>Page Title<% end %>
  <% panel.description do %>One sentence on what the page does<% end %>
  <% panel.year_selector year: @year, years: years %> <%# Optional %>
  <% panel.progress completed: x, total: y %>
<% end %>

<%# Longer explanations and instructions live in the BODY, not the hero
    (design-rules > Hero Panel Description Rule). %>

<%# Summary numbers live in the BODY, not the hero -- hero_stats needs an
    approved plan (design-rules > Hero Panel Stats). %>
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

---

## Pattern 2: Directory/List

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

---

## Pattern 3: Detail

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

---

## Pattern 4: Form (New/Edit)

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

---

## Pattern 5: Special

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

---

## Pattern 6: Records Management (Drill-Down)

**When to use:** an admin section managing many records of one kind that fall into a
small, stable set of categories — assets by type, slots by position, sign-ups by
position. Two levels; do not put both on one page.

**Do not use** when there is no natural category, when a category holds only a handful
of records, or when the reader's real question spans categories ("who still has gear
checked out?"). Those are flat reports — use a single filtered `ui_table` page instead.

### Level 1 — category index

No filter bar, no table. Just the categories and how big each one is.

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

### Level 2 — category page

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

### Rules

- **The category is the page, never a filter.** It gets no select on level 2 and no
  removable chip — a chip that drops it has nowhere to land. Build every chip URL
  against the category page so removing one keeps both the year and the category.
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

### Traps

- A nullable category column makes level 1 crash: `ui_drill_down_row` raises on a blank
  title, and `[nil].any?` is `false`, so the bucket silently vanishes. Give blank its own
  label and URL sentinel, and guard the list with `present?`.
- A finder that skips blank filter values returns **every** category when handed a blank
  one. Narrow the blank bucket explicitly.
- Adding the level-2 action to the controller does not gate it. Add it to the
  `authorize_ability ... only:` list in the same edit.

**Existing pages:** Asset Inventory (`asset-management/records`), Slots
(`scheduling/slots`), Available Sign-Ups, Position Credits, Swag

> Every one of these carries its level-2 totals in a body `ui_stat_row`, as shown
> above. Nothing in the app puts drill-down totals in the hero any more — see
> `design-rules` > Hero Panel Stats.

---

## Pattern 7: Review Pane (List + History)

**When to use:** a reviewer reads many records one at a time and acts on each — a
coordinator reading intake histories and filing notes, a mentor reviewing a season's
class. One line per record on the left; the selected record's whole history on the
right, so the list never moves while the pane is read. Approved 2026-10-14 for the three
Unified Flagging pages.

**Do not use** when each record has only a line's worth of detail (that is a `ui_table`
or a card list), or when the reader acts on records in bulk (a `bulk_select` table).

### Shape

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

### Rules

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

### Traps

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

- The controller matches a line to the pane by `data-review-id` on both. A workspace whose pane
  is hidden below `lg` (the mailbox: list page, then thread page) runs it with
  `data-review-pane-park-value="false"` and renders its frame `disabled`: the controller enables
  the frame from `lg` up only, so below `lg`, and before the controller loads, a line's link is an
  ordinary page visit. (Do not render a parking workspace's frame disabled: nothing enables it.)

**Existing pages:** VC › Unified Flagging, In-Person Training › Unified Flagging (read-only),
People › Unified Flagging (read-only; anyone the teams wrote about in a year, any status),
Mentoring › Post Season Summary, Potential Alphas and Alpha Status (read-only) —
`app/views/common/unified_flagging/_review_workspace.html.erb` and its siblings; the controller
and the partial locals are in `docs/UI-COMPONENTS.md` › review-pane. The three Messages mailboxes
(`app/views/common/messages/_workspace.html.erb`, approved 2026-10-18 as design A "Mail Desk" of
the messaging rework) apply the same shape to mail, with stacked message cards in the pane, replies
appended live (`thread-live` on /me marks one read where it lands) and, on Person and HQ, a Next
Unread button in the pane header that loads the person's next unread thread into the pane. Inside
the HQ shell the list column is under 20rem from `lg` to about 1210px beside the summary column
(308px at the window tablet's landscape 1180, measured 2026-10-18), and there the pane drops under
the list (`components/hq-window.css`, a container query on `.messages-workspace`); from about 1230px
the split holds.

---

## Common Layout Elements

### Page Headers

All pages use the `hero_panel` component for consistent page headers:

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

### Back Navigation

Back links are integrated into hero panels:

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

### Quick Actions

```erb
<div class="mb-4">
  <%= button_link "Primary", :primary, path, icon: "icon" %>
  <%= button_link "Secondary", :secondary, path %>
</div>
```

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

<%# Two-column with ui_section: the flex wrapper does the work %>
<div class="flex flex-col lg:flex-row gap-4">
  <%= ui_section "Left" do %>...<% end %>
  <%= ui_section "Right" do %>...<% end %>
</div>
```

### ADHD-Friendly Q&A Display

```erb
<dl class="instruction-list">
  <dt>Question?</dt>
  <dd>Clear, concise answer.</dd>
</dl>
```

### Collapsible Content

Use `data-controller="read-more"` for expandable sections.

### Status Indicators

Always combine borders, backgrounds, badges, AND icons. **CRITICAL:** Never rely on color alone.

---

## Interface Density & Scannability

**CRITICAL**: Interfaces must be as compact as possible while maintaining readability and pleasant aesthetics.

### Key Principles

- **Minimize vertical scrolling**: Consolidate information using appropriate spacing
- **Optimize information density**: Present more information per screen without sacrificing readability
- **Maintain readability**: Compactness must never compromise text legibility or touch target sizes (36px minimum)
- **Strategic whitespace**: Use whitespace purposefully for grouping and hierarchy, not decoration

### Help Section & FAQ Pattern

**CRITICAL**: When pages include help sections, FAQs, or explanatory content positioned further down the page, they must be clearly announced and linked at the top.

This is the shape for a full page of instructions on a page the reader operates. A report or a log has no foot-of-page help section: its explanations go in the one collapsed card under the stat row (`design-rules` > Where a Rule or a How-To Goes).

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
- Use consistent anchor IDs (`#faq-section`, `#help-section`, `#instructions`)

---

## Empty States

Always use the helper — never a hand-rolled dashed box:

```erb
<%= ui_empty_state "No items found." %>
<%= ui_empty_state "No messages yet.", icon: "envelope", icon_type: :regular %>
```

`envelope` draws in the regular style, the helper's default, but most icons do not: regular draws
only the icons in `lib/fontawesome/regular-icons.txt`. Pass `icon_type: :solid` for any other;
`fa_icon` raises in development and test when you don't.

---

## Turbo Integration Patterns

### Turbo Frame Loading Placeholders

When using lazy-loaded Turbo Frames, provide a loading placeholder with proper accessibility:

```erb
<turbo-frame id="content-frame"
             src="<%= content_path %>"
             loading="lazy"
             class="space-y-4">
  <div class="flex-center gap-2 p-8" role="status">
    <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
    <span class="sr-only">Loading…</span>
  </div>
</turbo-frame>
```

**CRITICAL:** Loading spinners must:
- Use `border-primary` (semantic token) — never `border-blue-600`
- Include `role="status"` on the container
- Include `sr-only` text for screen readers

### Permanent Elements

Use `data-turbo-permanent` for elements that must survive Turbo morphing/navigation:

```erb
<div id="sidebar-state" data-turbo-permanent>
  <%# Content preserved across navigations %>
</div>
```

**Requirements:**
- Element **must** have a stable, unique `id` attribute
- The same `id` must exist in both old and new pages
- Use sparingly — only for state that would be jarring to reset (e.g., expanded menus, scroll position)

### Turbo Stream Targets

For toast notifications and flash messages delivered via Turbo Streams, use the existing toast system. See Notifications in `design-components` for callout boxes and alert banners.

### Results Pages Rendered at 422

House pattern for POST results a GET cannot re-derive (export ledgers, maintenance run results): render the results view directly from the POST with `status: :unprocessable_entity` — Turbo silently drops a 200 form response.

Turbo keeps the submitting page's scroll position on form-submission renders (it morphs them into the page, keeping its scroller, `.drawer-content`), so the reader lands wherever the submit button was instead of at the summary. Start every 422 results view with the scroll-to-top marker, which scrolls that scroller to its top:

```erb
<div data-controller="scroll-to-top" hidden></div>
```

And assert it in the controller test:

```ruby
assert_select "[data-controller=scroll-to-top]"
```

**Use it on:** results/ledger pages rendered at 422 after a successful POST (BMID/TRS exports, ticketing and VC maintenance ledgers).

**Never use it on:** form re-renders with validation errors — preserved scroll is correct there; the reader needs to stay next to the fields they're fixing.

### Returning the Reader to One Record

**A redirect's `#fragment` does nothing after a form submission.** Turbo takes the page to visit from
the response's URL, and a URL's fragment is not part of it, so `redirect_to path(anchor: "group-7")`
from a POST, PATCH, or DELETE leaves the reader at the top of the page. Fragments still work for
ordinary link visits, which is why the mistake survives review.

**Use it on:** an edit or a reorder that redirects back to the list or parent page the reader came
from. Carry the record's id as a query parameter and render the `scroll-to-element` marker — see
`scroll-to-element` in `docs/UI-COMPONENTS.md` for the controller and view snippets, and for why
`window.scrollY` is the wrong thing to measure it with.

Pages written before this was understood still redirect with `anchor:` (announcements, slots, team
records, BMID titles and others); they land at the top of the page rather than beside the record.

In use on `app/views/communication/surveys/show.html.erb`.

---

## Related Skills

- **design-rules**: Critical rules and approval workflows
- **design-foundations**: Colors, typography, spacing
- **design-components**: Hero panels, sections, buttons
- **design-forms**: Form page layouts and patterns
- **design-content**: ADHD-friendly content patterns

## Full Documentation

For complete documentation, see [docs/DESIGN-GUIDE.md](../../docs/DESIGN-GUIDE.md) - Layout Patterns and Page Layouts sections.
