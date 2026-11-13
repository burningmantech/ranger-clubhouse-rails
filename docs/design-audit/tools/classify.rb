# frozen_string_literal: true

# Phase 2: classify every inventory row against docs/design-audit/rules.md.
#
#   ruby docs/design-audit/tools/classify.rb --slices   write data/phase2/<group>.review.tsv
#   ruby docs/design-audit/tools/classify.rb            write data/classified.json (uses data/phase2/*.txt verdicts)
#
# A row gets its verdict from, in order: a reviewer's verdict for that row (data/phase2/*.txt),
# then the DEFAULTS table below. A default of :review means "a reader must open the code"; such
# rows go to the review slices, and any left without a verdict are reported, never guessed.

require "json"
require "set"

ROOT = File.expand_path("../../..", __dir__)
DATA = File.join(ROOT, "docs/design-audit/data")

C = "COMPLIANT"
D = "DIVERGENT"
U = "UNCOVERED"

# Rows that are not a UI pattern in their own right (option builders, stream subscriptions).
SKIP_VARIANTS = /\A(?:options_for_select|options_from_collection_for_select|turbo_stream_from|number-format-call|fields_for|f\.fields_for|f\.hidden_field)\z/

DOCUMENTED_STIMULUS = {
  "modal" => "MODAL-01", "read-more" => "DISC-01", "table-sort" => "TABLE-06", "theme" => "DARK-01",
  "toast" => "TOAST-01", "tabs" => "TABS-01", "review-pane" => "LAYOUT-04", "onboarding" => "TOUR-01",
  "sidebar" => "NAV-02", "form" => "FORM-06", "conditional-show" => "FORM-07", "clipboard" => "TOAST-03",
  "match-stepper" => "NAV-03", "autocomplete" => "AC-01", "input-counter" => "FORM-01", "filter-bar" => "TABLE-04"
}.freeze

# [pattern regex, variant regex, verdict, rule, severity, note]; first match wins.
DEFAULTS = [
  # buttons
  [/buttons/, /\A(?:button_action|button_link|cancel_button|cancel_link|delete_button|submit_button|modal_close_button)\z/, C, "BTN-01", nil, "ButtonHelper method"],
  [/buttons/, /\Aedit_link\z/, C, "BTN-06", nil, "the one edit control"],
  [/buttons/, /\Abutton_row\z/, C, "BTN-07", nil, "button_row container"],
  [/buttons/, /\Af\.submit\z/, C, "BTN-07", nil, "builder submit, as the guide's form examples"],
  [/buttons/, /\Aclipboard_button\z/, C, "TOAST-03", nil, "copy control with its tip"],
  [/buttons/, /\A(?:export_csv_link|dropdown_button|ui_pager_button|match_step_button)\z/, U, nil, nil, "shared button helper the guide does not document"],
  [/buttons/, /./, :review, "BTN-01", nil, nil],
  # links: the guide has no rule for plain links
  [/links/, /\A(?:link_to|link_to_if|link_to_unless|mail_to|<a>|class:link|css:tap-target-link|css:no-decoration|css:link)\z/, U, nil, nil, "plain links: the guide has no link rule (colour, underline, external marker)"],
  [/links/, /\A(?:callsign_link|person_display_link|email_link_or_dash|ext_link|account_link|nav_link_to)\z/, U, nil, nil, "shared link helper the guide does not document"],
  [/links/, /./, :review, nil, nil, nil],
  # forms
  [/forms/, /\A(?:ui_form|form_row)\z/, C, "FORM-01", nil, "AppFormBuilder form"],
  [/forms/, /\Af\.fieldset\z|\Af\.legend\z/, C, "FORM-05", nil, "builder fieldset"],
  [/forms/, /\Af\.rich_text_area\z/, C, "FORM-09", nil, "builder rich text"],
  [/forms/, /\Af\./, C, "FORM-01", nil, "builder field"],
  [/forms/, /\A(?:filter_bar|filter_chips)\z/, C, "TABLE-04", nil, "filter_bar"],
  [/forms/, /\Abulk_select/, U, nil, nil, "bulk selection: named once in the guide, no rule or API"],
  [/forms/, /\A(?:year_selector|year_selector_compact|year_selector_keep_fields|title_year_selector)\z/, :review, "HERO-03", nil, nil],
  [/forms/, /./, :review, "FORM-01", nil, nil],
  # validation
  [/validation/, /\Aform_error_summary\z/, C, "FORM-06", nil, "the builder's error summary"],
  [/validation/, /\Arequired-attribute\z/, C, "FORM-03", nil, "required: on a field"],
  [/validation/, /\Ahtml-constraint-attribute\z/, U, nil, nil, "client-side constraints (min, max, pattern): the guide covers maxlength only"],
  [/validation/, /\Aui_flash_submit_error\z/, U, nil, nil, "shared helper the guide does not document"],
  [/validation/, /./, :review, "FORM-06", nil, nil],
  # modals
  [/modals/, /\Amodal\z/, C, "MODAL-01", nil, "the documented modal builder"],
  [/modals/, /\A(?:modal_dialog|modal_form_footer|modal_close_dialog)\z/, U, nil, nil, "modal helper the guide does not document (it shows only `modal`)"],
  [/modals/, /./, :review, "MODAL-02", nil, nil],
  # tables and lists
  [/tables-lists/, /\Aui_table\z/, C, "TABLE-01", nil, "ui_table"],
  [/tables-lists/, /\Aui_drill_down_row\z/, C, "LAYOUT-03", nil, "records-management row"],
  [/tables-lists/, /\Acss:instruction-list\z/, C, "LIST-01", nil, "instruction list"],
  [/tables-lists/, /\Acss:list-(?:bulleted|numbered)\z/, C, "SPACE-02", nil, "list utility"],
  [/tables-lists/, /\A(?:ui_table_rows|ui_label_value|ui_data_block)\z/, U, nil, nil, "shared helper the guide does not document"],
  [/tables-lists/, /\Acss:(?:callsign-list|roster-|hours-credits|shift-coverage|top-hour-earners)/, U, nil, nil, "page-specific grid component with no guide entry"],
  [/tables-lists/, /\Aclass:list\z/, U, nil, nil, "daisyUI list: not in the guide"],
  [/tables-lists/, /./, :review, "TABLE-01", nil, nil],
  # navigation
  [/navigation/, /\Ahero_panel\.back_to\z/, C, "HERO-04", nil, "back link in the hero"],
  [/navigation/, /\Ahero_panel\.year_selector\z/, C, "HERO-03", nil, "year selector in the hero"],
  [/navigation/, /\Atab_navigation\z/, C, "TABS-01", nil, "tab_navigation"],
  [/navigation/, /\Adropdown_(?:menu|item|divider|item_disabled)\z/, C, "NAV-01", nil, "dropdown helper"],
  [/navigation/, /\A(?:dropdown_scroll_list|partial:common\/dropdown_scroll_list)\z/, C, "NAV-04", nil, "directory quick navigation"],
  [/navigation/, /\Aui_match_stepper\z/, C, "NAV-03", nil, "match stepper"],
  [/navigation/, /\Acss:sidebar-/, C, "NAV-02", nil, "sidebar utility"],
  [/navigation/, /\A(?:ui_pager|ui_pager_meta)\z/, U, nil, nil, "pagination: no guide entry"],
  [/navigation/, /\Acss:(?:mega-menu|navbar)/, U, nil, nil, "navbar and mega menu: no component entry in the guide"],
  [/navigation/, /./, :review, nil, nil, nil],
  # cards
  [/cards/, /\A(?:ui_card|ui_card_image|ui_card_body|ui_card_title|ui_card_section|ui_card_footer|css:card-standard)\z/, C, "CARD-01", nil, "card"],
  [/cards/, /\Aui_accent_card\z/, C, "CARD-02", nil, "accent card"],
  [/cards/, /\Aui_section\z/, C, "CARD-03", nil, "section"],
  [/cards/, /\A(?:ui_stat_box|ui_stat_row)\z/, C, "STAT-01", nil, "stat tiles"],
  [/cards/, /\A(?:ui_accordion|ui_disclosure)\z/, C, "DISC-01", nil, "disclosure helper"],
  [/cards/, /\Acss:review-(?:pane|line)/, C, "LAYOUT-04", nil, "review pane class"],
  [/cards/, /\A(?:ui_stat_link|action_box|ui_icon_item|inline_disclosure|card_disclosure)\z/, U, nil, nil, "shared helper the guide does not document"],
  [/cards/, /./, :review, "CARD-01", nil, nil],
  # toasts and alerts
  [/toasts-alerts/, /\A(?:ui_callout_box|ui_alert_banner)\z/, C, "ALERT-01", nil, "notice helper"],
  [/toasts-alerts/, /\A(?:ui_flash_successful|ui_success_text)\z/, U, nil, nil, "shared helper the guide does not document"],
  [/toasts-alerts/, /./, :review, "TOAST-01", nil, nil],
  # empty and loading
  [/empty-loading/, /\Aui_empty_state\z/, C, "EMPTY-01", nil, "ui_empty_state"],
  [/empty-loading/, /\Avalue_or_dash\z/, C, "EMPTY-02", nil, "prints an em dash for a blank value"],
  [/empty-loading/, /\Anone_stated\z/, D, "EMPTY-02", "low", "the rule: an empty value prints \"—\"; none_stated prints \"None stated\" in muted italics (application_helper.rb:80)"],
  [/empty-loading/, /\A(?:turbo_frame_tag|lazy-turbo-frame-or-image|partial:shared\/frame_spinner|spinner-icon|submit-busy-text|aria-busy|turbo_empty_frame|class:loading|class:skeleton)\z/, U, nil, nil, "loading and busy states: the guide approves the spinner as motion but has no loading-state rule"],
  [/empty-loading/, /./, :review, "EMPTY-01", nil, nil],
  # typography
  [/typography/, /\Ahero_panel\z/, C, "HERO-01", nil, "hero_panel page header"],
  [/typography/, /\Acss:heading-(?:section|title)\z/, C, "TYPE-04", nil, "heading utility"],
  [/typography/, /\A<strong>\z/, C, "COLOR-03", nil, "emphasis by weight"],
  [/typography/, /\A(?:<b>|<em>|<small>)\z/, U, nil, nil, "inline emphasis tags: the guide shows <strong> and says nothing of <b>, <em> or <small>"],
  [/typography/, /\A(?:ui_section_title|ui_subheading)\z/, U, nil, nil, "shared heading helper the guide does not document"],
  [/typography/, /\Adate-format-call\z/, C, "COPY-08", nil, "DateTimeHelper call (strftime in a view is listed separately)"],
  [/typography/, /\Atw-text-size\z/, :text_size, nil, nil, nil],
  [/typography/, /\Atw-font-and-text-style\z/, :font_style, nil, nil, nil],
  [/typography/, /\Acss:lexxy-content\z/, C, "FORM-09", nil, "saved rich text wrapper"],
  [/typography/, /./, :review, "TYPE-04", nil, nil],
  # colour
  [/color/, /\Atw-(?:semantic-token|bridge-token|transparent-or-current)\z/, C, "COLOR-01", nil, "theme token"],
  [/color/, /\Acss:text-(?:stone-(?:muted|subtle|emphasis|icon)|heading|heading-primary)\z/, C, "COLOR-06", nil, "neutral text ladder"],
  [/color/, /\Atw-palette-color\z/, D, "COLOR-01", "medium", "the rule: semantic tokens only; this is a Tailwind palette colour in markup"],
  [/color/, /./, :review, "COLOR-01", nil, nil],
  # spacing
  [/spacing/, /\Atw-spacing-scale\z/, C, "SPACE-01", nil, "Tailwind scale spacing"],
  [/spacing/, /\Atw-radius-shadow\z/, :radius_shadow, nil, nil, nil],
  [/spacing/, /\Acss:(?:flex-center|flex-center-gap-2|inline-flex-center|inline-flex-center-gap-2)\z/, C, "STYLE-04", nil, "documented flex utility"],
  [/spacing/, /\Ainline-style\z/, D, "STYLE-01", "low", "the rule: no inline style= attribute"],
  [/spacing/, /\A<br>\z/, U, nil, nil, "line breaks used for spacing: not addressed"],
  [/spacing/, /\Acss:(?:two-column-lg|stack-to-row-lg|app-edge-pad)\z/, U, nil, nil, "layout utility the guide does not document (it writes the flex classes out)"],
  [/spacing/, /./, :review, "SPACE-01", nil, nil],
  # icons
  [/icons/, /\A(?:fa_icon|icon-option-on-helper)\z/, C, "ICON-01", nil, "fa_icon"],
  [/icons/, /\A(?:image_tag|<img>)\z/, U, nil, nil, "images and photos: no guide entry"],
  [/icons/, /./, :review, "ICON-01", nil, nil],
  # other
  [/other/, /\Aui_badge\z/, C, "BADGE-01", nil, "ui_badge"],
  [/other/, /\A(?:ui_progress_bar|ui_progress_box)\z/, C, "PROG-01", nil, "progress helper"],
  [/other/, /\Acss:(?:messages-|search-hit)/, C, "MSG-01", nil, "documented message styling"],
  [/other/, /\Astimulus:/, :stimulus, nil, nil, nil],
  [/other/, /\A(?:tooltip-or-title-attribute|class:tooltip)\z/, U, nil, nil, "tooltips by title attribute or daisyUI tooltip: the guide covers only help_mode: :tooltip and fa_icon label:"],
  [/other/, /\A(?:yes_no_badge|severity_style)\z/, U, nil, nil, "shared helper the guide does not document"],
  [/other/, /\Acss:/, U, nil, nil, "page-specific component class with no guide entry"],
  [/other/, /\Aclass:(?:avatar|indicator|divider|kbd|join|mask|status|stack|swap|timeline|countdown|chat|carousel|diff|radial-progress)\z/, U, nil, nil, "daisyUI component the guide does not document"],
  [/other/, /./, :review, nil, nil, nil]
].freeze

def default_for(row)
  return [:skip] if row[:variant].match?(SKIP_VARIANTS)
  return [:review, nil, nil, nil] if row[:source] != "census" # everything an agent added needs a reader
  _, _, verdict, rule, severity, note = DEFAULTS.find { |p, v, *| row[:pattern].match?(p) && row[:variant].match?(v) }
  case verdict
  when :text_size
    row[:note].to_s.match?(/\btext-(?:xs|sm)\b/) ? [:review, "TYPE-02", nil, nil] : [C, "TYPE-01", nil, "size on the documented scale"]
  when :font_style
    if row[:note].to_s.match?(/font-mono/) then [:review, "TYPE-06", nil, nil]
    elsif row[:note].to_s.match?(/font-(?:thin|extralight|light|extrabold|black)|text-justify/) then [:review, "TYPE-08", nil, nil]
    else [C, "TYPE-08", nil, "weight or text style on the documented scale"]
    end
  when :radius_shadow
    row[:note].to_s.match?(/shadow(?!-none)/) ? [:review, "SHADOW-01", nil, nil] : [C, "RADIUS-01", nil, "radius on the documented scale"]
  when :stimulus
    name = row[:variant].delete_prefix("stimulus:")
    DOCUMENTED_STIMULUS.key?(name) ? [C, DOCUMENTED_STIMULUS[name], nil, "documented controller"] : [U, nil, nil, "Stimulus behaviour with no guide entry"]
  when nil then [:review, nil, nil, nil]
  else [verdict, rule, severity, note]
  end
end

GROUP_PATHS = {
  "person" => %w[app/views/person/ app/helpers/person/],
  "me" => %w[app/views/me/ app/views/dashboard_tasks/ app/helpers/me/ app/helpers/dashboard_helper.rb],
  "scheduling" => %w[app/views/scheduling/ app/helpers/scheduling/],
  "training" => %w[app/views/training/ app/helpers/training/],
  "mentoring" => %w[app/views/mentoring/ app/helpers/mentoring/ app/helpers/mentor_helper.rb app/helpers/intake_helper.rb],
  "vc" => %w[app/views/vc/ app/helpers/vc/],
  "admin" => %w[app/views/admin/ app/helpers/admin/],
  "timesheets-shiftops" => %w[app/views/timesheets/ app/views/shift_operations/ app/helpers/timesheets/ app/helpers/shift_operations/],
  "teams-people" => %w[app/views/teams_positions/ app/views/people/ app/views/certificates/ app/helpers/teams_positions/ app/helpers/people/ app/helpers/certificates/],
  "ticketing-bmid" => %w[app/views/ticketing/ app/views/bmid/ app/helpers/ticketing/ app/helpers/bmid/ app/helpers/bmid_helper.rb app/helpers/tickets_provisions_helper.rb],
  "communication" => %w[app/views/communication/ app/views/alerts/ app/views/mail/ app/views/bug_reports/ app/views/bookmarks/ app/helpers/communication/ app/helpers/mail_log_helper.rb app/helpers/mailer_helper.rb],
  "hq-assets" => %w[app/views/hq/ app/views/asset_management/ app/views/quartermaster/ app/views/vehicles/ app/views/pogs/ app/helpers/asset_management/ app/helpers/quartermaster/ app/helpers/vehicles/ app/helpers/pogs/ app/helpers/hq_helper.rb],
  "shell-auth-profile" => %w[app/views/layouts/ app/views/application/ app/views/shared/ app/views/sessions/ app/views/register/ app/views/sso/ app/views/pwa/ app/views/test_harness/ app/views/autocomplete/ app/views/profile/ app/views/profile_photos/ app/views/profile_languages/ app/helpers/register_helper.rb public/],
  "common-b" => %w[schedule scheduling shift_manage available_sign_ups timesheet work_history training mentoring qualifications].map { |d| "app/views/common/#{d}/" },
  "common-a" => %w[app/views/common/ app/helpers/messages_helper.rb app/helpers/unified_flagging_helper.rb app/helpers/bulk_upload_helper.rb app/helpers/survey_report_helper.rb],
  "helpers-shared" => %w[app/helpers/ app/javascript/ app/assets/]
}.freeze

def group_of(file)
  GROUP_PATHS.find { |_, prefixes| prefixes.any? { |p| file.start_with?(p) } }&.first || "helpers-shared"
end

inventory = JSON.parse(File.read(File.join(DATA, "inventory.json")), symbolize_names: true)
rows = inventory[:rows].each_with_index.map { |r, i| r.merge(id: format("R%05d", i + 1)) }

mechanical = File.readlines(File.join(DATA, "mechanical.tsv"), chomp: true).drop(1).each_with_index.map do |l, i|
  rule, certainty, file, line, match, source = l.split("\t", -1)
  { id: format("M%04d", i + 1), rule:, certainty:, file:, line: line.to_i, match:, text: source }
end

if ARGV.include?("--slices")
  dir = File.join(DATA, "phase2")
  Dir.mkdir(dir) unless Dir.exist?(dir)
  slices = Hash.new { |h, k| h[k] = [] }
  rows.each do |r|
    verdict, hint, = default_for(r)
    next unless verdict == :review
    slices[group_of(r[:file])] << [r[:id], r[:source] == "census" ? "census" : "agent", r[:file], r[:lines], r[:pattern],
                                   r[:variant], r[:impl], hint.to_s, r[:note].to_s[0, 260]]
  end
  mechanical.each do |m|
    slices[group_of(m[:file])] << [m[:id], "grep:#{m[:certainty]}", m[:file], m[:line], "-", m[:match], "-", m[:rule], m[:text]]
  end
  slices.each do |group, list|
    File.open(File.join(dir, "#{group}.review.tsv"), "w") do |out|
      out.puts %w[id source file lines pattern variant impl rule_hint note].join("\t")
      list.sort_by { |l| [l[2], l[3].to_s.to_i, l[0]] }.each { |l| out.puts l.map { |c| c.to_s.delete("\t") }.join("\t") }
    end
  end
  warn slices.map { |g, l| "#{g}=#{l.size}" }.sort.join("  ")
  exit
end

# ---- final classification ----------------------------------------------------
def fields(line) = line.chomp.split(/\s*\|\|\s*/, -1).map(&:strip)

verdicts = {}
extra = []
sweeps = []
opinions = []
components = []
bad = []
Dir[File.join(DATA, "phase2/*.txt")].sort.each do |path|
  group = File.basename(path, ".txt")
  File.readlines(path, chomp: true).each_with_index do |line, i|
    next if line.strip.empty? || line.start_with?("```")
    f = fields(line)
    case f[0]
    when "V" then verdicts[f[1]] = { classification: f[2], rule: f[3], severity: f[4], line: f[5], note: f[6..].to_a.join(" | "), reviewer: group }
    when "F" then extra << { file: f[1], line: f[2], pattern: f[3], variant: f[4], classification: f[5], rule: f[6], severity: f[7], note: f[8..].to_a.join(" | "), reviewer: group }
    when "S" then sweeps << { group:, rule: f[1], checked: f[2], divergent: f[3], comment: f[4..].to_a.join(" | ") }
    when "Q" then opinions << { group:, text: f[1..].to_a.join(" | ") }
    when "C" then components << { group:, name: f[1], where: f[2], pattern: f[3], classification: f[4], rule: f[5], severity: f[6], note: f[7..].to_a.join(" | ") }
    else bad << "#{group}:#{i + 1}: #{line[0, 90]}"
    end
  end
end

clean = ->(v) { v.to_s.strip.then { |s| s.empty? || s == "-" ? nil : s } }
valid = [C, D, U]
out = []
unreviewed = []
rows.each do |r|
  verdict, rule, severity, note = default_for(r)
  next if verdict == :skip
  finding = r.slice(:id, :file, :pattern, :variant, :impl, :lines, :source).merge(inventory_note: r[:note])
  if (v = verdicts[r[:id]]) && valid.include?(v[:classification])
    finding.merge!(classification: v[:classification], rule_id: clean.call(v[:rule]), severity: clean.call(v[:severity]),
                   line: clean.call(v[:line]) || r[:lines].to_s.split(",").first, note: v[:note], basis: "reviewed (#{v[:reviewer]})")
  elsif verdict == :review
    unreviewed << r[:id]
    finding.merge!(classification: U, rule_id: nil, severity: nil, line: r[:lines].to_s.split(",").first,
                   note: "not classified: no reviewer verdict was returned for this row", basis: "unreviewed")
  else
    finding.merge!(classification: verdict, rule_id: rule, severity:, line: r[:lines].to_s.split(",").first, note:, basis: "default by variant")
  end
  finding[:severity] = nil unless finding[:classification] == D
  finding[:severity] ||= "low" if finding[:classification] == D
  out << finding
end

mechanical.each do |m|
  v = verdicts[m[:id]]
  if v && valid.include?(v[:classification])
    next unless v[:classification] == D # a cleared candidate is not a finding
    out << { id: m[:id], file: m[:file], pattern: clean.call(v[:note][/\Apattern=([\w-]+)/, 1]) || nil, variant: "grep:#{m[:match]}", impl: "grep",
             lines: m[:line].to_s, source: "grep", inventory_note: m[:text], classification: D, rule_id: clean.call(v[:rule]) || m[:rule],
             severity: clean.call(v[:severity]) || "low", line: m[:line].to_s, note: v[:note], basis: "grep, reviewed (#{v[:reviewer]})" }
  elsif m[:certainty] == "definite"
    out << { id: m[:id], file: m[:file], pattern: nil, variant: "grep:#{m[:match]}", impl: "grep", lines: m[:line].to_s, source: "grep",
             inventory_note: m[:text], classification: D, rule_id: m[:rule], severity: "low", line: m[:line].to_s,
             note: "matches the rule's banned form: #{m[:match]}", basis: "grep (definite)" }
  end
end

extra.each_with_index do |e, i|
  next unless valid.include?(e[:classification])
  out << { id: format("F%04d", i + 1), file: e[:file].sub(/:\d.*\z/, ""), pattern: e[:pattern], variant: e[:variant], impl: "review", lines: e[:line].to_s,
           source: e[:reviewer], inventory_note: nil, classification: e[:classification], rule_id: clean.call(e[:rule]),
           severity: e[:classification] == D ? (clean.call(e[:severity]) || "low") : nil, line: e[:line].to_s, note: e[:note], basis: "page sweep (#{e[:reviewer]})" }
end

# ---- lead rulings ------------------------------------------------------------------
# After reading the reviewers' verdicts against the guide's wording, the lead found that some rule
# IDs in rules.md state more than the guide does. Where the guide only shows an example, or does
# not say whether a case is in scope, a "departure" is not a departure from a written rule: it is
# reclassified UNCOVERED with the ambiguity named. Each ruling is applied to every matching finding.
OUTSIDE_SHELL = %r{\Aapp/views/(?:sessions|sso|bookmarks|test_harness)/|\Apublic/|print_sheet|print_sheets|signup_sheet|trainers_report|info_sheet|apparel\.html|roc_photo_board}
LEAD_RULINGS = [
  [->(f) { f[:rule_id] == "BTN-07" },
   "ambiguous BTN-07: the guide shows button_row in its form and records-management examples but never requires it, and its own Quick Actions example (3608-3615) puts buttons in a bare div."],
  [->(f) { f[:rule_id] == "LAYOUT-02" },
   "ambiguous LAYOUT-02: the guide gives two column recipes as examples (3077-3092); it does not say another grid, gap or column method is wrong."],
  [->(f) { f[:rule_id] == "SPACE-01" },
   "ambiguous SPACE-01: the guide lists \"common patterns\" (549-554) rather than required values, and has no general rule on arbitrary values."],
  [->(f) { f[:rule_id] == "FORM-08" },
   "ambiguous FORM-08: the form page structure (2722-2747) is a recommended shape; the guide's own hybrid example wraps ui_form in a ui_section, and a description or back link is optional."],
  [->(f) { f[:rule_id] == "HERO-02" && f[:note].to_s.match?(/has no description|hero has none|has none\b|no description|title and back|without a description|carries a description/i) },
   "ambiguous HERO-02: the guide says what a hero description must be (one sentence), not that every hero needs one."],
  [->(f) { f[:rule_id] == "HERO-04" && f[:note].to_s.match?(/repeat|adds a body|although the hero already|print:hidden|print view|print sheet/i) },
   "ambiguous HERO-04: the guide says where the back link lives; it does not address a second link at the foot of a page, or pages that have no hero (print sheets)."],
  [->(f) { f[:rule_id] == "HERO-01" && f[:file].match?(OUTSIDE_SHELL) },
   "ambiguous HERO-01: \"all pages use hero_panel\" (3027) sits beside \"used across all /me routes\" (1782); the guide does not say whether pages outside the app shell (sign-in, kiosk and wall displays, print sheets, static error pages, fixtures) take a hero."],
  [->(f) { f[:rule_id] == "ALERT-01" && !f[:note].to_s.match?(/hand-made|hand-built|panel|window\.alert|:primary|report-callout|bordered|rounded/i) },
   "ambiguous ALERT-01: the guide documents ui_callout_box as the notice component but does not say a one-line warning inside a card, cell or dialog must be one."]
].freeze
rulings = Hash.new(0)
out.each do |f|
  next unless f[:classification] == D
  LEAD_RULINGS.each_with_index do |(test, text), i|
    next unless test.call(f)
    f.merge!(classification: U, severity: nil, note: "#{text} Found: #{f[:note].to_s.sub(/\Apattern=[\w-]+\s*/, "")}", basis: "lead ruling (reviewer: #{f[:basis]})")
    rulings[i] += 1
    break
  end
end
# The guide itself records the progress badge's palette gradient as tolerated legacy (736-743).
out.each do |f|
  next unless f[:classification] == D && f[:rule_id] == "COLOR-01" && f[:file].end_with?("ui_progress_box_helper.rb")
  f.merge!(classification: C, severity: nil, note: "palette gradient the guide records as documented legacy (736-743): not to be copied", basis: "lead ruling")
end
warn "lead rulings applied: #{rulings.sort.map { |i, n| "#{LEAD_RULINGS[i][1][/[A-Z]+-\d+/]}=#{n}" }.join(" ")}"

File.write(File.join(DATA, "classified.json"), JSON.pretty_generate(
  findings: out, sweeps:, opinions:, components:, unreviewed:, unparsed: bad
))
tally = out.map { |f| f[:classification] }.tally
warn "findings=#{out.size} #{tally} unreviewed=#{unreviewed.size} verdicts=#{verdicts.size} extra=#{extra.size} components=#{components.size} sweeps=#{sweeps.size} bad=#{bad.size}"
bad.first(30).each { |b| warn "  unparsed #{b}" }
