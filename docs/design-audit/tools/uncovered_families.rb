# frozen_string_literal: true

# Groups UNCOVERED findings into the patterns a guideline would have to address, and holds the
# audit's recommendation for each. Used by build_report.rb.

# [family name, pattern regex, variant regex]; first match wins. Checked against "pattern / variant".
FAMILIES = [
  ["Undocumented shared helpers, classes and controllers (shared layer)", /./, /\Acomponent:/],
  ["Plain links and link helpers", /links/, /./],
  ["Plain links and link helpers", /./, /\Acss:link\z|tap-target-link/],
  ["Stimulus behaviours with no guide entry", /./, /scroll-to-top|hidden-behaviour|\Adata-controller:/],
  ["CSV export control (`export_csv_link`)", /buttons/, /export_csv_link/],
  ["Dialog shell and footer (`modal_dialog`, `modal_form_footer`)", /modals/, /modal_dialog|modal_form_footer|modal_close_dialog|custom-dialog|dialog/],
  ["Loading and busy states", /empty-loading/, /turbo_frame_tag|lazy|spinner|busy|loading|skeleton|turbo_empty_frame/],
  ["Collection with no empty branch", /empty-loading/, /not-handled/],
  ["Worded or styled placeholder for an empty value", /empty-loading|typography|tables-lists/, /placeholder|empty-value|none_stated|plain-text-empty|table-row-empty|dash/],
  ["Label and value display", /tables-lists|typography|cards/, /ui_label_value|ui_data_block|definition-grid|\A<dl>\z|stacked-cell|label-value|key-value/],
  ["Pagination (`ui_pager`)", /navigation/, /pager/],
  ["Bulk selection (`bulk_select`)", /forms|tables-lists|other/, /bulk_select|bulk-select|row-selector/],
  ["Inline emphasis tags (`<b>`, `<em>`, `<i>`, `<small>`)", /typography|icons/, /\A<(?:b|em|i|small|strong)>\z/],
  ["Separator and arrow glyphs in text", /icons/, /glyph|entity|emoji|arrow|separator|symbol/],
  ["Client-side field constraints (`min`, `max`, `pattern`)", /validation/, /html-constraint/],
  ["Form errors reported outside the builder", /validation/, /./],
  ["Stimulus behaviours with no guide entry", /other/, /\Astimulus:/],
  ["Print sheets", /./, /\Acss:(?:alpha-|sheet-|report-|acceptance-|signup-)|print/],
  ["Login and public pages", /./, /\Acss:login-|login|public-page|static-error/],
  ["Navbar and mega menu", /navigation|other/, /mega|navbar|\A<nav>\z|top-menu|public-menu/],
  ["Count lines, meta lines and hand-made sub-headings", /typography/, /heading|count|summary|meta|intro|subline|ui_subheading|ui_section_title|label|caption|fragment|note|paragraph|\A<h\d>\z/],
  ["Layout utilities and wrappers (`two-column-lg`, `stack-to-row-lg`, width caps)", /spacing/, /two-column|stack-to-row|wrapper|grid-layout|page-width|app-edge|layout|column/],
  ["Line breaks used for spacing", /spacing/, /\A<br>\z|\A<hr>\z/],
  ["Arbitrary Tailwind values", /spacing|color/, /arbitrary/],
  ["Tooltips", /./, /tooltip|title-attribute/],
  ["Photos, avatars and images", /./, /image_tag|\A<img>\z|avatar|photo|camera|crop/],
  ["Inline notices that are not callouts", /toasts-alerts/, /./],
  ["Area badge maps and yes/no badges", /other|color/, /badge|severity_style|status-by-color|status/],
  ["Stat links, action boxes and icon items", /cards/, /ui_stat_link|action_box|ui_icon_item/],
  ["Hand-built list rows and non-bulleted lists", /tables-lists/, /list|\A<ul>\z|\A<ol>\z|row/],
  ["Page-specific grids, boards and charts", /./, /\Acss:(?:roster-|hours-|hq-|ct-|vc-|shift-coverage|top-hour|stat-meter|progress|callsign-list)|chart|gantt|board|matrix|canvas|grid-table/],
  ["Shared helper called with its own classes", /./, /helper-class-override/],
  ["Embedded frames and media", /other/, /iframe|video|canvas|embed/],
  ["Other one-off markup", /./, /./]
].freeze

# A finding whose note starts "ambiguous <RULE>" belongs to the question that rule leaves open.
AMBIGUOUS_FAMILY = {
  "BTN-07" => "Where buttons sit (`button_row` or a bare wrapper)",
  "HERO-01" => "Page header outside the app shell (sign-in, kiosk, print, error pages)",
  "HERO-02" => "Hero with no description",
  "HERO-04" => "Back link repeated at the foot of a page, or on a page with no hero",
  "FORM-08" => "Form page shape",
  "LAYOUT-02" => "Column and grid recipes",
  "SPACE-01" => "Spacing values outside the guide's common patterns",
  "EMPTY-01" => "Collection with no empty branch",
  "EMPTY-02" => "Worded or styled placeholder for an empty value",
  "ALERT-01" => "Inline notices that are not callouts",
  "ICON-01" => "Separator and arrow glyphs in text"
}.freeze

FAMILY_RECOMMENDATION = {
  "Where buttons sit (`button_row` or a bare wrapper)" =>
    "Decide it and say it: every group of page actions and every form's submit sits in `button_row` (it handles stacking below `md` and the sticky spacer); one button inside a callout, a table cell or a section's title row is exempt. Then fix the guide's own Quick Actions example, which uses a bare div.",
  "Page header outside the app shell (sign-in, kiosk, print, error pages)" =>
    "Write the exemption: sign-in and SSO pages use `sessions/_heading`; kiosk, wall-display and print layouts carry their own masthead; static error pages are exempt. Everything inside the app shell takes `hero_panel`.",
  "Hero with no description" =>
    "Say whether a description is required. If it is, 13 heroes (mostly new and edit forms under /person) need a sentence; if not, say a form page may omit it.",
  "Back link repeated at the foot of a page, or on a page with no hero" =>
    "Allow or forbid a second \"Back to X\" at the foot of a long page; give print sheets one shared `print:hidden` navigation partial (three sheets copy it inline).",
  "Form page shape" =>
    "Mark the form page structure PREFERRED and name what is fixed (hero with back link, `ui_form`, button row last) and what is free (sections inside or around the form, a stat row above an edit form).",
  "Column and grid recipes" =>
    "Say whether `gap-4` is the grid gap or an example, and whether CSS columns and an `xl:` fold are allowed for card grids.",
  "Spacing values outside the guide's common patterns" =>
    "Turn \"common patterns\" into rules or label them examples: card padding (`p-3` is in use beside `p-4`), the gap between sections, and the button-row gap (the row itself uses viewport units).",
  "Plain links and link helpers" =>
    "Write a Links section. Standard: a bare `<a>`/`link_to` (already primary and underlined on hover from base.css) for prose links; `person_display_link`/`callsign_link` for people; `ext_link` for anything leaving the app; `email_link_or_dash` for addresses; `tap-target-link` when a link stands alone. Say when a link is a `button_link` instead.",
  "CSV export control (`export_csv_link`)" =>
    "Document `export_csv_link` as the export control. TABLE-05 and the pattern 6 examples show `button_link \"Export CSV\", :secondary, ..., icon: \"file-csv\"`; 84 files use the helper. Make the helper the standard and fix the label there.",
  "Dialog shell and footer (`modal_dialog`, `modal_form_footer`)" =>
    "Make `modal_dialog` + `modal_form_footer` the documented standard for form dialogs (47 and 32 files against 28 for the `modal` builder the guide shows); keep `modal` for non-form dialogs. Name the default size: the guide's comment says `:md`, the code defaults to `:lg`.",
  "Loading and busy states" =>
    "Write a Loading States section. Standard: `shared/_frame_spinner` inside a lazy `turbo_frame_tag`; `turbo_submits_with` text on a submit that takes time; `aria-busy` on the region. Retire the inline copy, the `border-[3px]` spinner and the plain \"Loading…\" paragraphs.",
  "Collection with no empty branch" =>
    "Add one sentence to EMPTY-01: every list, table or section that can be empty renders `ui_empty_state` (or says why it cannot be empty). Today the rule covers how an empty state looks, not whether one is required.",
  "Worded or styled placeholder for an empty value" =>
    "Extend EMPTY-02: `value_or_dash` is the helper for a blank value; say whether a worded placeholder (\"Never\", \"None stated\", \"not yet\") is allowed and, if so, that it is `none_stated`-style muted text rather than ad-hoc italics.",
  "Label and value display" =>
    "Document `ui_label_value` as the standard for a record's label/value block (30 uses), with its size default stated; fold the raw `<dl>` grids, flex rows and header-less `ui_table`s into it.",
  "Pagination (`ui_pager`)" =>
    "Document `ui_pager`: where it sits (above and below the list, or below only), the count line beside it, and its relation to `filter_bar count:`.",
  "Bulk selection (`bulk_select`)" =>
    "Document `bulk_select` (select-all, row checkbox, count) as the standard for acting on several rows; the guide names it once (line 3519) without an API or placement rule.",
  "Inline emphasis tags (`<b>`, `<em>`, `<i>`, `<small>`)" =>
    "One line under COLOR-03: emphasis is `<strong>`; `<b>`, `<i>` and `<small>` are not used; `<em>` only for a title or term. 75 files use `<b>` for the same job as `<strong>`.",
  "Separator and arrow glyphs in text" =>
    "Say which glyphs are text and which are icons: \"·\" and \"—\" as separators are punctuation; a \"→\" or \"✓\" carrying meaning is an icon and goes through `fa_icon`.",
  "Client-side field constraints (`min`, `max`, `pattern`)" =>
    "Add to Form Patterns: when to set `min`/`max`/`pattern`, and that every constraint needs a matching server validation and message (COPY-06). The guide covers `maxlength` only.",
  "Form errors reported outside the builder" =>
    "Add to FORM-06: a form without a model (bulk tools, searches) reports a refusal in an error `ui_callout_box` above the form, not in a flash alone and not in red text.",
  "Stimulus behaviours with no guide entry" =>
    "Add a short Behaviours table (controller, what it does, where allowed) for the controllers pages attach directly; the guide lists four of roughly sixty. Start with `toggle`, `unsaved-changes`, `scroll-to-top`, `local-time`, `position-picker`.",
  "Print sheets" =>
    "Write a Print Sheets section: the shared skeleton (masthead, running head, doc label, legend), the `print` layout, hex literals allowed for paper, raw `<table>` allowed, and one shared stylesheet instead of five families that repeat it.",
  "Login and public pages" =>
    "Document the login page's component set (panel, input, submit) or state that `login.css` is exempt from the component rules; five of its classes are unused.",
  "Navbar and mega menu" =>
    "Add Navbar and Mega Menu entries beside Sidebar: the 36px floor (the mega menu's item links are `min-h-8`), the search field, and which buttons are ghost.",
  "Count lines, meta lines and hand-made sub-headings" =>
    "Document `ui_subheading` and `ui_section_title`, and give the count line one form (`text-lg` per LAYOUT-03 on level 1; `filter_bar count:` elsewhere). Muted meta lines take `text-stone-muted`.",
  "Layout utilities and wrappers (`two-column-lg`, `stack-to-row-lg`, width caps)" =>
    "Either document `two-column-lg` and `stack-to-row-lg` in Custom Utility Classes or replace them with the `flex flex-col lg:flex-row gap-4` the guide writes out; name the allowed page width caps (`lg:w-3/4`, `max-w-3xl`).",
  "Line breaks used for spacing" =>
    "One line under Spacing: no `<br>` for vertical space; use a block element with a scale margin. `<br>` stays for an address or a line of verse.",
  "Arbitrary Tailwind values" =>
    "The guide bans three specific arbitrary values (TOUCH-01) and uses several itself. State the general rule AGENTS.md already has: no arbitrary value without a written reason; a computed number goes through a CSS custom property.",
  "Tooltips" =>
    "Write a Tooltips entry: `fa_icon ... label:` for an icon's meaning, `help_mode: :tooltip` for a field (after fixing its `aria-describedby`), and no bare `title=` for information a touch user needs.",
  "Photos, avatars and images" =>
    "Document the avatar and photo treatments (sizes from `PersonPhoto` constants, the placeholder, `rounded-full`), and move the computed width/height from inline `style` to a custom property.",
  "Inline notices that are not callouts" =>
    "Settle ALERT-01's scope: a one-line notice inside a card or dashboard step is either a compact `ui_callout_box` or `text-error` with an icon. About 15 dashboard steps use bold red paragraphs.",
  "Area badge maps and yes/no badges" =>
    "Document `yes_no_badge` and require a status-to-variant map to live in one place per status family; two helpers colour the same verdict differently.",
  "Stat links, action boxes and icon items" =>
    "Document `ui_stat_link` (a stat tile that filters), `action_box` and `ui_icon_item`, or fold them into `ui_stat_box` and `ui_section`.",
  "Hand-built list rows and non-bulleted lists" =>
    "Document the plain list row (a link or record per line with a divider) as a component, or name `ui_drill_down_row` as its standard outside records-management pages.",
  "Page-specific grids, boards and charts" =>
    "List the approved one-page components (roster grid, hours and credits grid, HQ forecast Gantt, credit chart, photo board, VC stage cards) with their owner pages, as the guide does for the review pane, so PROC-01 has a record.",
  "Shared helper called with its own classes" =>
    "Say, per helper, what `class:` may carry (layout and width only) and what it may not (colour, type size, radius).",
  "Embedded frames and media" =>
    "No rule needed unless more appear; note the allowed uses (document preview, camera capture).",
  "Undocumented shared helpers, classes and controllers (shared layer)" =>
    "Add the missing entries to the Component Library, or mark each helper internal. The per-item list is in findings.json (`variant` starting `component:`).",
  "Other one-off markup" => "Review case by case; most are single uses."
}.freeze

def family_of(finding)
  if (rule = finding[:note].to_s[/\Aambiguous\s+([A-Z0-9]+-\d+)/i, 1]) && AMBIGUOUS_FAMILY.key?(rule)
    return AMBIGUOUS_FAMILY[rule]
  end
  key_pattern = finding[:pattern].to_s
  variant = finding[:variant].to_s
  name, = FAMILIES.find { |_, p, v| key_pattern.match?(p) && variant.match?(v) }
  name || "Other one-off markup"
end

def variant_label(finding)
  finding[:variant].to_s.sub(/\Aoneoff:/, "").sub(/\Acomponent:/, "").sub(/\Agrep:/, "")
end
