# frozen_string_literal: true

# Mechanical UI pattern census for the design audit (read-only).
#
#   ruby docs/design-audit/tools/pattern_census.rb
#
# Reads app/views (and app/helpers with --helpers) and writes, under docs/design-audit/data/:
#   census.tsv  file, pattern, variant, impl, count, lines, detail
#   pages.tsv   page template, routes, partials reached through static render calls
#
# It only reports what a regex can see. Class strings built at runtime, partials
# rendered from helpers, and anything a helper emits are invisible to it.

require "set"

ROOT = File.expand_path("../../..", __dir__)
OUT = File.join(ROOT, "docs/design-audit/data")
CSS_DIR = File.join(ROOT, "app/assets/stylesheets")

# --- helper calls: name => [pattern, impl] -----------------------------------
SHARED = "shared-helper"
RAILS = "rails-helper"
HELPERS = {
  "buttons" => {
    SHARED => %w[button_action button_link cancel_button edit_link export_csv_link delete_button submit_button
                 button_row cancel_link clipboard_button dropdown_button modal_close_button ui_pager_button match_step_button],
    RAILS => %w[button_to button_tag submit_tag]
  },
  "links" => {
    SHARED => %w[ext_link account_link nav_link_to callsign_link email_link_or_dash person_display_link],
    RAILS => %w[link_to link_to_if link_to_unless mail_to]
  },
  "forms" => {
    SHARED => %w[ui_form form_row filter_bar filter_chips bulk_select bulk_select_all bulk_select_count
                 bulk_select_checkbox year_selector year_selector_compact year_selector_keep_fields title_year_selector],
    RAILS => %w[form_with form_for form_tag fields_for text_field_tag select_tag check_box_tag radio_button_tag
                number_field_tag date_field_tag text_area_tag file_field_tag label_tag search_field_tag
                email_field_tag password_field_tag telephone_field_tag options_for_select
                options_from_collection_for_select]
  },
  "validation" => {
    SHARED => %w[form_error_summary ui_flash_submit_error]
  },
  "modals" => {
    SHARED => %w[modal modal_dialog modal_form_footer modal_close_dialog confirm_modal confirm_modal_dialog]
  },
  "tables-lists" => {
    SHARED => %w[ui_table ui_table_rows ui_label_value ui_data_block ui_drill_down_row]
  },
  "navigation" => {
    SHARED => %w[dropdown_scroll_list tab_navigation dropdown_menu dropdown_item dropdown_divider dropdown_item_disabled ui_pager
                 ui_pager_meta ui_match_stepper]
  },
  "cards" => {
    SHARED => %w[ui_card ui_card_image ui_card_body ui_card_title ui_card_section ui_card_footer ui_accent_card
                 ui_section action_box ui_stat_box ui_stat_row ui_stat_link ui_icon_item ui_accordion ui_disclosure
                 inline_disclosure card_disclosure]
  },
  "toasts-alerts" => {
    SHARED => %w[ui_callout_box ui_alert_banner ui_toast_render ui_toast_stream ui_flash_successful ui_success_text]
  },
  "empty-loading" => {
    SHARED => %w[ui_empty_state turbo_empty_frame value_or_dash none_stated],
    RAILS => %w[turbo_frame_tag turbo_stream_from]
  },
  "typography" => {
    SHARED => %w[hero_panel ui_section_title ui_subheading page_title]
  },
  "icons" => {
    SHARED => %w[fa_icon],
    RAILS => %w[image_tag inline_svg_tag]
  },
  "other" => {
    SHARED => %w[yes_no_badge ui_badge ui_progress_bar ui_progress_box severity_style]
  }
}.freeze

HELPER_INDEX = HELPERS.flat_map { |pattern, by_impl|
  by_impl.flat_map { |impl, names| names.map { |n| [n, [pattern, impl]] } }
}.to_h.freeze
HELPER_RE = /(?<![\w.:@"'\/-])(#{HELPER_INDEX.keys.sort_by { |k| -k.size }.join("|")})(?=[\s(]|$)/

BUILDER_FIELDS = %w[text_field email_field password_field number_field telephone_field phone_field url_field
                    date_field datetime_field time_field text_area rich_text_area select collection_select
                    check_box radio_button collection_radio_buttons collection_check_boxes file_field
                    search_field autocomplete_field callsign_chips_field fieldset legend submit label
                    fields_for button hidden_field].freeze
BUILDER_RE = /\b(?:f|ff|form|fields|builder|[a-z]+_f|[a-z]+_form|[a-z]+_fields)\.(#{BUILDER_FIELDS.join("|")})\b/

# --- raw HTML tags: tag => [pattern, variant] -------------------------------
RAW_TAGS = {
  "button" => "buttons", "a" => "links", "form" => "forms", "input" => "forms", "select" => "forms",
  "textarea" => "forms", "label" => "forms", "fieldset" => "forms", "dialog" => "modals",
  "table" => "tables-lists", "ul" => "tables-lists", "ol" => "tables-lists", "dl" => "tables-lists",
  "nav" => "navigation", "details" => "cards", "svg" => "icons", "img" => "icons", "i" => "icons",
  "h1" => "typography", "h2" => "typography", "h3" => "typography", "h4" => "typography",
  "h5" => "typography", "h6" => "typography", "small" => "typography", "strong" => "typography",
  "b" => "typography", "em" => "typography", "hr" => "spacing", "br" => "spacing",
  "canvas" => "other", "iframe" => "other", "video" => "other", "progress" => "other"
}.freeze
RAW_TAG_RE = /<(#{RAW_TAGS.keys.sort_by { |k| -k.size }.join("|")})(?=[\s>\/])/

# --- other line-level markers: [regex, pattern, variant, impl] --------------
MARKERS = [
  [/content_tag[\s(]+:?["']?(\w+)|\btag\.(\w+)/, nil, nil, "rails-helper"], # resolved per tag below
  [/\.errors\b|errors\.(any\?|full_messages|each|\[)/, "validation", "model-errors-inline", "one-off"],
  [/render\s+(?:partial:\s*)?["']common\/error_summary["']/, "validation", "partial:common/error_summary", "shared-partial"],
  [/aria-invalid|aria:\s*\{[^}]*invalid/, "validation", "aria-invalid", "attribute"],
  [/\brequired(?::\s*true|=|\b(?=[\s>]))/, "validation", "required-attribute", "attribute"],
  [/\b(?:pattern|minlength|maxlength|min|max)[:=]\s*["'\d]/, "validation", "html-constraint-attribute", "attribute"],
  [/render\s+(?:partial:\s*)?["']common\/dropdown_scroll_list["']/, "navigation", "partial:common/dropdown_scroll_list", "shared-partial"],
  [/turbo[_-]confirm/, "modals", "turbo-confirm", "attribute"],
  [/(?<!turbo_)(?<!turbo-)\bconfirm\(/, "modals", "js-confirm", "one-off"],
  [/\.back_to\b|\bback_to:/, "navigation", "hero_panel.back_to", SHARED],
  [/\.year_selector\b/, "navigation", "hero_panel.year_selector", SHARED],
  [/\bflash(?:\.now)?\[|\bflash\.(?:each|notice|alert)|\bnotice\b(?=\s*%>)|\balert\b(?=\s*%>)/, "toasts-alerts", "flash-read-in-view", "one-off"],
  [/render\s+(?:partial:\s*)?["']common\/toast["']/, "toasts-alerts", "partial:common/toast", "shared-partial"],
  [/render\s+(?:partial:\s*)?["']shared\/frame_spinner["']/, "empty-loading", "partial:shared/frame_spinner", "shared-partial"],
  [/fa-spinner|fa-circle-notch|["' ]spinner\b/, "empty-loading", "spinner-icon", "one-off"],
  [/loading:\s*["':]?lazy|loading=["']lazy/, "empty-loading", "lazy-turbo-frame-or-image", "attribute"],
  [/disable_with|turbo_submits_with|turbo-submits-with/, "empty-loading", "submit-busy-text", "attribute"],
  [/aria-busy|aria:\s*\{[^}]*busy/, "empty-loading", "aria-busy", "attribute"],
  [/\.(?:empty|none|blank)\?|\.any\?|\.present\?\s*%>|<%\s*else\s*%>/, "empty-loading", "conditional-branch(candidate)", "candidate"],
  [/\bicon:\s*["':]/, "icons", "icon-option-on-helper", SHARED],
  [/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}\u{2705}\u{274C}]/, "icons", "emoji-or-symbol-character", "hard-coded"],
  [/&(?:nbsp|rarr|larr|times|check|bull|middot|raquo|laquo);|[→←×•·»«✓✗]/, "icons", "html-entity-or-glyph", "hard-coded"],
  [/#[0-9a-fA-F]{3,8}\b(?![^<]*%>)|rgba?\(|hsla?\(|oklch\(/, "color", "literal-color-value", "hard-coded"],
  [/data-tip|tooltip|\btitle=["']/, "other", "tooltip-or-title-attribute", "attribute"],
  [/datetime_format|short_datetime_format|full_datetime_format|mdy_format|ymd_format|month_day_format|wday_month_day_format|strftime|to_fs|l\(/, "typography", "date-format-call", "detail"],
  [/number_to_currency|number_with_delimiter|number_with_precision|pluralize/, "typography", "number-format-call", "detail"]
].freeze

CONTENT_TAG_PATTERN = RAW_TAGS.merge("div" => nil, "span" => nil, "p" => nil, "li" => nil, "td" => nil,
                                     "th" => nil, "tr" => nil, "section" => nil).freeze

# --- class tokens -----------------------------------------------------------
DAISY = {
  "buttons" => %w[btn],
  "forms" => %w[input select textarea checkbox radio toggle file-input range label fieldset floating-label
                validator rating join filter],
  "modals" => %w[modal],
  "tables-lists" => %w[table list],
  "navigation" => %w[tabs tab menu dropdown navbar drawer breadcrumbs steps step dock],
  "links" => %w[link],
  "cards" => %w[card collapse hero stat stats accordion],
  "toasts-alerts" => %w[alert toast],
  "empty-loading" => %w[loading skeleton],
  "other" => %w[badge progress radial-progress avatar tooltip indicator divider kbd mask status swap timeline
                countdown stack chat carousel diff]
}.freeze
DAISY_INDEX = DAISY.flat_map { |pattern, bases| bases.map { |b| [b, pattern] } }.to_h.freeze

CSS_FILE_PATTERN = {
  "buttons" => %w[buttons], "forms" => %w[forms autocomplete camera], "modals" => %w[modals],
  "tables-lists" => %w[tables lists label-value callsign-list roster-matrix hours-credits shift-coverage
                       top-hour-earners],
  "navigation" => %w[navbar sidebar mega-menu tabs dropdowns bookmark],
  "cards" => %w[cards boxes disclosure hero-panel review-pane],
  "toasts-alerts" => %w[toasts], "empty-loading" => %w[empty-state],
  "typography" => %w[headings], "color" => %w[text-colors],
  "spacing" => %w[flex-patterns layout-patterns safe-area], "icons" => %w[icons]
}.flat_map { |pattern, files| files.map { |f| [f, pattern] } }.to_h.freeze

NOT_CLASSES = %w[css js erb html rb com md dark hidden fixed flex group show active the same w-full text-center
                 text-end text-right fa fa-chevron-down animate-pulse application].to_set.freeze

def custom_classes
  index = {}
  utilities = {}
  files = Dir[File.join(CSS_DIR, "components/*.css")] +
          %w[utilities base accessibility login].map { |f| File.join(CSS_DIR, "#{f}.css") } +
          [File.join(ROOT, "app/assets/tailwind/application.css")]
  files.each do |path|
    base = File.basename(path, ".css")
    pattern = CSS_FILE_PATTERN.fetch(base, "other")
    src = File.read(path)
    # An @utility is the app's own class even when it shares a daisyUI prefix (card-standard,
    # list-numbered); a bare selector with a daisyUI prefix (.btn-error) is an override of daisyUI.
    src.scan(/@utility\s+([\w-]+)/).flatten.each { |name| utilities[name] ||= [pattern, base] }
    src.scan(/(?<![\w-])\.([a-zA-Z][\w-]*)/).flatten.uniq.each do |name|
      next if NOT_CLASSES.include?(name) || DAISY_INDEX.key?(name) || DAISY_INDEX.key?(name[/\A[a-z]+(?:-input)?/])
      index[name] ||= [pattern, base]
    end
  end
  index.merge(utilities).merge(
    "instruction-list" => %w[tables-lists accessibility], "lexxy-content" => %w[typography lexxy],
    "me-muted" => %w[color hero-panel], "tap-target-link" => %w[links accessibility],
    "no-decoration" => %w[links base]
  )
end
CUSTOM = custom_classes.freeze

SEMANTIC = %w[primary primary-content secondary secondary-content accent accent-content neutral neutral-content
              base-100 base-200 base-300 base-content info info-content success success-content warning
              warning-content error error-content].freeze
BRIDGE = %w[body body-subtle chrome default default-soft default-strong heading hero-tile hero-tile-content line
            sidebar-active sidebar-content sidebar-divider sidebar-link sidebar-link-hq sidebar-title-hq
            signature-edge].freeze
PALETTE = %w[slate gray zinc stone red orange amber yellow lime green emerald teal cyan sky blue indigo violet
             purple fuchsia pink rose].freeze
COLOR_PREFIX = "(?:text|bg|border(?:-[trblxyse])?|ring(?:-offset)?|fill|stroke|from|to|via|divide|outline|decoration|accent|caret|shadow|placeholder)"
SEMANTIC_RE = /\A#{COLOR_PREFIX}-(#{(SEMANTIC + BRIDGE).sort_by { |s| -s.size }.join("|")})(?:\/\d+)?\z/
PALETTE_RE = /\A#{COLOR_PREFIX}-(?:(?:#{PALETTE.join("|")})-\d{2,3}|white|black)(?:\/\d+)?\z/
TRANSPARENT_RE = /\A#{COLOR_PREFIX}-(?:transparent|current|inherit)\z/
TEXT_SIZE_RE = /\Atext-(?:xs|sm|base|lg|xl|[2-9]xl)\z/
FONT_RE = /\A(?:font-(?:thin|extralight|light|normal|medium|semibold|bold|extrabold|black|mono|sans|serif)|leading-[\w.]+|tracking-\w+|uppercase|lowercase|capitalize|italic|not-italic|underline|line-through|no-underline|truncate|line-clamp-\d+|whitespace-[\w-]+|break-\w+|tabular-nums|text-(?:left|center|right|start|end|wrap|nowrap|balance|pretty))\z/
SPACING_RE = /\A-?(?:p[xytrblse]?|m[xytrblse]?|gap(?:-[xy])?|space-[xy])-(?:\d+(?:\.\d+)?|px|auto)\z/
SIZING_RE = /\A(?:w|h|min-w|max-w|min-h|max-h|size|basis)-(?:\d+(?:\.\d+)?|px|full|screen|auto|fit|min|max|\d+\/\d+|[a-z0-9]+)\z/
RADIUS_SHADOW_RE = /\A(?:rounded(?:-[a-z]+)?(?:-(?:none|sm|md|lg|xl|2xl|3xl|full|box|field|selector))?|shadow(?:-(?:xs|sm|md|lg|xl|2xl|none|inner))?)\z/
ARBITRARY_RE = /\[[^\]]+\]/
FA_RE = /\Afa-[\w-]+\z|\Afa[srbl]?\z/

CLASS_CONTEXT_RE = /(?:\bclass(?:es|_names)?|\b\w+_class(?:es)?|\btoken_list)\s*(?:[:=]|=>)?\s*[(\[]?\s*(["'])(.*?)\1/

Record = Struct.new(:lines, :details)

def add(store, file, pattern, variant, impl, line, detail = nil)
  rec = (store[[file, pattern, variant, impl]] ||= Record.new([], Set.new))
  rec.lines << line unless rec.lines.last == line
  rec.details << detail if detail
end

def classify_token(raw)
  token = raw.sub(/\A(?:[\w-]+(?:\[[^\]]*\])?:)+/, "").sub(/\A!/, "").sub(/!\z/, "")
  return if token.empty? || token.include?("<%") || token.include?('#{')

  if token.match?(ARBITRARY_RE)
    kind = token.match?(/\A(?:text|bg|border|ring|fill|stroke)-\[(?:#|rgb|hsl|oklch|var\(--color|color:)/) ? "color" : "spacing"
    return [kind, "tw-arbitrary-value", "hard-coded", raw]
  end
  return ["color", "tw-palette-color", "hard-coded", raw] if token.match?(PALETTE_RE)
  if (m = token.match(SEMANTIC_RE))
    family = BRIDGE.include?(m[1]) ? "tw-bridge-token" : "tw-semantic-token"
    return ["color", family, "token", raw]
  end
  return ["color", "tw-transparent-or-current", "token", raw] if token.match?(TRANSPARENT_RE)
  return ["typography", "tw-text-size", "utility", raw] if token.match?(TEXT_SIZE_RE)
  return ["typography", "tw-font-and-text-style", "utility", raw] if token.match?(FONT_RE)
  return ["spacing", "tw-spacing-scale", "utility", raw] if token.match?(SPACING_RE)
  return ["spacing", "tw-radius-shadow", "utility", raw] if token.match?(RADIUS_SHADOW_RE)
  return ["icons", "fa-class-literal", "one-off", raw] if token.match?(FA_RE)
  if CUSTOM.key?(token)
    pattern, css = CUSTOM[token]
    return [pattern, "css:#{token}", "custom-css(#{css}.css)", nil]
  end
  base = token[/\A(file-input|floating-label|radial-progress|[a-z]+)/, 1]
  # Tailwind utilities that share a daisyUI component prefix.
  return if token.match?(/\A(?:select-(?:none|text|all|auto)|table-(?:auto|fixed|cell|row|caption|column)|list-(?:disc|decimal|none|inside|outside|item)|filter-none|mask-(?:\w+-)?(?:from|to|via)-.*|stack-to-row-lg)\z/)
  if DAISY_INDEX.key?(base) && (token == base || token.start_with?("#{base}-"))
    return [DAISY_INDEX[base], "class:#{base}", "daisyui-class", raw]
  end
  nil
end

OPTION_RE = /\b(variant|size|color|style|type|layout|tone|kind|theme|severity|placement|method|class|icon|align|compact|striped|responsive|title_tag|level|padding|width):\s*(:\w+|"[^"]*"|'[^']*'|true|false|\d+)/

# A helper call often wraps across lines; read up to the closing %> for its options.
def call_options(all, i)
  stmt = all[i, 15].take_while.with_index { |l, k| k.zero? || !all[i + k - 1].include?("%>") }.join(" ")
  stmt = stmt[0, stmt.index("%>") || stmt.size]
  stmt.scan(OPTION_RE).map { |k, v| "#{k}=#{v.delete(%q("'))}" }
end

def scan_file(store, rel, renders)
  all = File.readlines(File.join(ROOT, rel), chomp: true)
  in_comment = false
  all.each_with_index do |text, i|
    line = i + 1
    # ERB comments, including ones that run over several lines, are not UI.
    if in_comment || text.strip.start_with?("<%#")
      in_comment = !text.include?("%>")
      next
    end
    next if rel.end_with?(".rb") && text.strip.start_with?("#")

    text.scan(HELPER_RE) do |(name)|
      pattern, impl = HELPER_INDEX[name]
      add(store, rel, pattern, name, impl, line)
      call_options(all, i).each { |opt| add(store, rel, pattern, name, impl, line, opt) } if impl == SHARED
    end
    # Area helpers that wrap a shared component: <%= photo_status_badge ... %>
    text.scan(/<%=\s*([a-z_]+_(badge|link|button))\b/) do |name, kind|
      next if HELPER_INDEX.key?(name)
      pattern = { "badge" => "other", "link" => "links", "button" => "buttons" }.fetch(kind)
      add(store, rel, pattern, "area-#{kind}-helper", "area-helper", line, name)
    end
    text.scan(BUILDER_RE) do |(name)|
      pattern = name == "submit" || name == "button" ? "buttons" : "forms"
      add(store, rel, pattern, "f.#{name}", "form-builder", line)
    end
    text.scan(RAW_TAG_RE) do |(tag)|
      next if tag == "i" && !text.match?(/<i\s[^>]*class=/)
      add(store, rel, RAW_TAGS[tag], "<#{tag}>", "raw-html", line)
    end
    MARKERS.each do |re, pattern, variant, impl|
      next unless (m = text.match(re))
      if pattern.nil?
        tag = m[1] || m[2]
        next unless (p = CONTENT_TAG_PATTERN[tag])
        add(store, rel, p, "content_tag/tag.#{tag}", impl, line)
      else
        add(store, rel, pattern, variant, impl, line)
      end
    end
    text.scan(/\bstyle\s*(?:=|:)\s*(["'])(.*?)\1/) do |(_, css)|
      pattern = css.match?(/color|background|border-color|fill/) ? "color" : "spacing"
      add(store, rel, pattern, "inline-style", "inline-style", line, css[0, 80])
    end
    text.scan(/data-controller=["']([^"']+)["']|controller:\s*["']([^"']+)["']/) do |a, b|
      (a || b).split.each { |c| add(store, rel, "other", "stimulus:#{c}", "stimulus-controller", line) }
    end
    text.scan(CLASS_CONTEXT_RE) do |(_, classes)|
      classes.gsub(/<%.*?%>/, " ").split.each do |tok|
        pattern, variant, impl, detail = classify_token(tok)
        add(store, rel, pattern, variant, impl, line, detail) if pattern
      end
    end
    text.scan(/render\s*\(?\s*(partial:\s*|layout:\s*|template:\s*)?["']([\w\/.-]+)["']/) do |kind, name|
      renders << (kind.to_s.start_with?("template") ? "template:#{name}" : name)
    end
  end
end

def partial_path(name, from)
  if name.start_with?("template:")
    return %w[html.erb turbo_stream.erb].map { |ext| File.join("app/views", "#{name.delete_prefix("template:")}.#{ext}") }
                                        .find { |rel| File.exist?(File.join(ROOT, rel)) }
  end
  dir, base = File.split(name)
  dir = File.dirname(from).sub(%r{\Aapp/views/?}, "") if dir == "."
  %w[html.erb turbo_stream.erb].each do |ext|
    rel = File.join("app/views", dir, "_#{base.sub(/\.html\z/, "")}.#{ext}")
    return rel if File.exist?(File.join(ROOT, rel))
  end
  nil
end

def routes_by_action
  path = File.join(OUT, "routes.txt")
  return {} unless File.exist?(path)
  File.readlines(path).each_with_object(Hash.new { |h, k| h[k] = [] }) do |l, acc|
    next unless (m = l.match(/(GET|POST|PATCH|PUT|DELETE)\s+(\/\S*)\s+([\w\/]+#\w+)/))
    acc[m[3]] << "#{m[1]} #{m[2].sub("(.:format)", "")}"
  end
end

def run
  roots = ["app/views"]
  roots << "app/helpers" if ARGV.include?("--helpers")
  files = roots.flat_map { |r| Dir.chdir(ROOT) { Dir["#{r}/**/*.{erb,rb}"] } }.sort
  store = {}
  renders = {}
  files.each do |rel|
    renders[rel] = []
    scan_file(store, rel, renders[rel])
  end

  File.open(File.join(OUT, "census.tsv"), "w") do |out|
    out.puts %w[file pattern variant impl count lines detail].join("\t")
    store.sort_by { |(file, pattern, variant, _), _| [file, pattern, variant] }.each do |(file, pattern, variant, impl), rec|
      lines = rec.lines.first(15).join(",") + (rec.lines.size > 15 ? ",…" : "")
      detail = rec.details.to_a.sort.first(25).join(" ")
      out.puts [file, pattern, variant, impl, rec.lines.size, lines, detail].join("\t")
    end
  end

  routes = routes_by_action
  File.open(File.join(OUT, "pages.tsv"), "w") do |out|
    out.puts %w[template kind routes partials unresolved_renders].join("\t")
    files.grep(%r{\Aapp/views/}).reject { |f| File.basename(f).start_with?("_") }.each do |page|
      seen = Set.new
      unresolved = Set.new
      queue = [page]
      until queue.empty?
        cur = queue.shift
        renders.fetch(cur, []).each do |name|
          target = partial_path(name, cur)
          if target.nil?
            unresolved << name
          elsif seen.add?(target)
            queue << target
          end
        end
      end
      action = page.sub(%r{\Aapp/views/}, "").sub(/\.(html|turbo_stream|json)\.erb\z/, "").sub(%r{/([^/]+)\z}, '#\1')
      kind = page.start_with?("app/views/layouts/") ? "layout" : page[/\.(\w+)\.erb\z/, 1] || "other"
      out.puts [page, kind, routes.fetch(action, []).join("; "), seen.to_a.sort.join(" "), unresolved.to_a.sort.join(" ")].join("\t")
    end
  end
  warn "#{files.size} files, #{store.size} census rows"
end

run
