# frozen_string_literal: true

# Grep-level checks for the rules in docs/design-audit/rules.md that a pattern can settle or
# shortlist (read-only on app code).
#
#   ruby docs/design-audit/tools/rule_checks.rb
#
# Writes docs/design-audit/data/mechanical.tsv: rule, certainty, file, line, match
#   definite   the match is a departure from the rule as written
#   candidate  the match needs a reader (the rule has exceptions a regex cannot see)

ROOT = File.expand_path("../../..", __dir__)
OUT = File.join(ROOT, "docs/design-audit/data/mechanical.tsv")

VIEWS = "app/views/**/*.erb"
HELPERS = "app/helpers/**/*.rb"
JS = "app/javascript/controllers/**/*.js"
CSS = "app/assets/stylesheets/{*.css,components/*.css}"
VENDORED = /vanilla-calendar-pro|lexxy-(variables|content|editor)|fontawesome-subset|stylesheets\/driver\.css/

PALETTE = "(?:slate|gray|zinc|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-\\d{2,3}"
COLOR_UTIL = "(?:text|bg|border|ring|fill|stroke|from|to|via|divide|outline|decoration)"

# [rule, certainty, globs, regex, options]
#   only_text: test the line with ERB tags and HTML tags removed (visible copy only)
#   skip:      regex; a matching line is ignored
CHECKS = [
  ["COLOR-01", "definite", [VIEWS, HELPERS, JS], /(?<![\w-])#{COLOR_UTIL}-(?:#{PALETTE}|white|black)(?![\w-])/, {}],
  ["COLOR-08", "definite", [VIEWS, HELPERS, JS], /\bbtn-info\b|\bbg-blue-\d+/, {}],
  ["TYPE-06", "candidate", [VIEWS, HELPERS], /\bfont-mono\b/, {}],
  ["SPACE-02", "definite", [VIEWS, HELPERS, JS], /\blist-(?:disc|decimal|inside)\b/, {}],
  ["STYLE-01", "definite", [VIEWS], /\sstyle=["']/, {}],
  ["STYLE-01", "candidate", [VIEWS, HELPERS], /\bstyle:\s*["']/, { skip: /icon_style|_style:/ }],
  ["STYLE-01", "definite", [VIEWS], /<style[\s>]/, {}],
  ["BP-01", "candidate", [VIEWS, HELPERS, JS], /(?<![\w:-])md:[\w\[-]/, {}],
  ["BP-01", "candidate", [VIEWS, HELPERS, JS], /(?<![\w:-])sm:[\w\[-]/, { skip: /width:\s*["'][^"']*sm:w-/ }],
  ["BP-01", "candidate", [VIEWS, HELPERS, JS], /(?<![\w:-])2xl:[\w\[-]/, {}],
  ["BP-02", "definite", [CSS], /max-width:\s*102[34]px/, {}],
  ["BP-02", "candidate", [CSS], /@media[^{]*\b(?:min|max)-width:\s*\d+px/, {}],
  ["ICON-02", "definite", [VIEWS], /<svg[\s>]/, {}],
  ["ICON-02", "candidate", [VIEWS, HELPERS, CSS], /data:image\/svg/, {}],
  ["ICON-01", "definite", [VIEWS], /<i\s[^>]*class=["'][^"']*\bfa[srb]?\b/, {}],
  ["TOUCH-01", "definite", [VIEWS, HELPERS, JS], /min-h-\[36px\]|\bmin-h-11\b/, {}],
  ["TOUCH-01", "candidate", [VIEWS, HELPERS], /min-height:/, {}],
  ["BTN-01", "candidate", [VIEWS], /<button[\s>]/, {}],
  ["BTN-01", "candidate", [VIEWS, HELPERS], /class[:=]\s*["'][^"']*(?<![\w-])btn(?![\w-])/, { skip: %r{button_helper\.rb} }],
  ["BTN-03", "candidate", [VIEWS, HELPERS], /size:\s*["':]xs\b|\bbtn-xs\b/, {}],
  ["FORM-01", "candidate", [VIEWS, HELPERS], /\b(?:form_with|form_for|form_tag)\b/, { skip: /builder:\s*AppFormBuilder|def |ui_form/ }],
  ["FORM-01", "candidate", [VIEWS], /<form[\s>]/, {}],
  ["FORM-01", "candidate", [VIEWS], /\b(?:text_field_tag|select_tag|check_box_tag|radio_button_tag|number_field_tag|date_field_tag|text_area_tag|file_field_tag|email_field_tag|search_field_tag|password_field_tag)\b/, {}],
  ["TABLE-01", "candidate", [VIEWS], /<table[\s>]/, {}],
  ["TABLE-02", "candidate", [VIEWS, HELPERS], /responsive:\s*false/, {}],
  ["STAT-02", "definite", [VIEWS, HELPERS], /\.hero_stats\b|\.stat_badge\b/, { skip: /ui_hero_panel_helper|me\/dashboard/ }],
  ["TABS-01", "candidate", [VIEWS], /class=["'][^"']*\btabs?\b[^"']*["']|role=["']tab(?:list)?["']/, {}],
  ["MODAL-01", "candidate", [VIEWS], /<dialog[\s>]/, {}],
  ["MODAL-02", "definite", [VIEWS, HELPERS, JS, "app/controllers/**/*.rb"], /Are you sure|Really (?:delete|remove)/i, {}],
  ["MODAL-02", "candidate", [VIEWS, HELPERS, JS], /turbo_confirm:\s*["']|data-turbo-confirm=|window\.confirm\(|(?<![\w.])confirm\(["'`]|\balert\(["'`]/, {}],
  ["MOTION-01", "candidate", [VIEWS, HELPERS], /\banimate-(?!spin\b|pulse\b)[\w-]+|hover:(?:scale|-?translate|shadow)-/, {}],
  ["COLOR-07", "candidate", [VIEWS, HELPERS], /\bbg-linear-|\bbg-gradient-|\bfrom-(?:primary|warning|amber|orange)/, { skip: /progress/ }],
  ["COPY-01", "candidate", [VIEWS], /\b(?:work(?:ing|ed|s)?|jobs?|employees?|staff)\b/i, { only_text: true, skip: /Work History|Staff Credential/ }],
  ["COPY-02", "definite", [VIEWS, HELPERS], /status[\w.()]*\.titleize|\.status\.humanize/, {}],
  ["COPY-04", "candidate", [VIEWS, HELPERS], /(?:button_link|button_action|submit_button|\.submit|back_to|link_to)\s*\(?\s*["'](?:New|Create|Update|Submit|Trash|Destroy)\b[^"']*["']/, {}],
  ["COPY-04", "candidate", [VIEWS, HELPERS], /(?:button_link|button_action|submit_button|\.submit|delete_button|link_to)\s*\(?\s*["']Remove(?! from)\b[^"']*["']/, {}],
  ["COPY-04", "definite", [VIEWS, HELPERS], /(?:back_to|button_link|link_to)\s*\(?\s*["']Back["']/, {}],
  ["COPY-07", "definite", [VIEWS], /[A-Za-z]\.\.\.(?=["'<\s]|$)/, { only_text: true }],
  ["COPY-07", "definite", [VIEWS, HELPERS], /["'][^"'#{}]*[A-Za-z]\.\.\.["']/, { skip: /^\s*#/ }],
  ["COPY-07", "candidate", [VIEWS], /\b(?:signup|signups|checkin|checkout|unsubmit(?:ted)?)\b/i, { only_text: true }],
  ["COPY-08", "definite", [VIEWS], /\bstrftime\b/, {}],
  ["COPY-08", "candidate", [HELPERS], /\bstrftime\b/, { skip: %r{date_time_helper} }],
  ["COPY-08", "candidate", [VIEWS], /\.to_fs\(|\bl\(\s*@?\w+[\w.]*,\s*format:|%-?I:%M|\b(?:am|pm|AM|PM)\b(?=\s*["'<])/, {}],
  ["COPY-09", "definite", [VIEWS, HELPERS], /"%g"|\$(?:<%=\s*|#\{)\s*number_with_(?:delimiter|precision)/, {}],
  ["COPY-09", "candidate", [VIEWS, HELPERS], /number_to_currency/, {}],
  ["COPY-10", "candidate", [VIEWS, HELPERS], /["']\s*(?:Click here|Submit)\s*["']/i, {}]
].freeze

def visible_text(line)
  line.gsub(/<%.*?%>/, " ").gsub(/<[^>]+>/, " ")
end

rows = []
CHECKS.each do |rule, certainty, globs, regex, opts|
  globs.flat_map { |g| Dir.chdir(ROOT) { Dir[g] } }.uniq.sort.each do |rel|
    next if rel.match?(VENDORED)
    comment = false
    File.readlines(File.join(ROOT, rel), chomp: true).each_with_index do |raw, i|
      if rel.end_with?(".erb") && (comment || raw.strip.start_with?("<%#"))
        comment = !raw.include?("%>")
        next
      end
      next if rel.end_with?(".rb") && raw.strip.start_with?("#")
      next if opts[:skip] && (raw.match?(opts[:skip]) || rel.match?(opts[:skip]))
      text = opts[:only_text] ? visible_text(raw) : raw
      next unless (m = text.match(regex))
      rows << [rule, certainty, rel, i + 1, m[0].strip[0, 60], raw.strip[0, 140]]
    end
  end
end

# SPACE-03: a class on a <dt>/<dd> inside <dl class="instruction-list">.
Dir.chdir(ROOT) { Dir[VIEWS] }.sort.each do |rel|
  inside = false
  File.readlines(File.join(ROOT, rel), chomp: true).each_with_index do |raw, i|
    inside = true if raw.include?("instruction-list")
    rows << ["SPACE-03", "definite", rel, i + 1, raw[/<d[td]\s+class=["'][^"']*["']/], raw.strip[0, 140]] if inside && raw.match?(/<d[td]\s+class=/)
    inside = false if raw.include?("</dl>")
  end
end

# HERO-01: an HTML page template with a route and no hero_panel in itself or its partials.
pages = File.join(ROOT, "docs/design-audit/data/pages.tsv")
if File.exist?(pages)
  File.readlines(pages, chomp: true).drop(1).each do |l|
    template, kind, routes, partials, = l.split("\t", -1)
    next unless kind == "html" && !routes.to_s.empty? && !template.start_with?("app/views/layouts")
    files = [template] + partials.to_s.split
    next if files.any? { |f| File.read(File.join(ROOT, f)).match?(/\bhero_panel\b|\bpage_title\b/) }
    rows << ["HERO-01", "candidate", template, 1, "no hero_panel", routes[0, 140]]
  end
end

# TABLE-05: a file with a filter_bar and an export control that is not on the bar's actions: line.
Dir.chdir(ROOT) { Dir[VIEWS] }.sort.each do |rel|
  src = File.read(File.join(ROOT, rel))
  next unless src.include?("filter_bar")
  src.lines.each_with_index do |raw, i|
    next unless raw.match?(/export_csv_link|button_link\s*\(?\s*["'][^"']*Export/)
    next if raw.match?(/actions:/) || src.lines[[i - 3, 0].max, 3].join.match?(/actions:\s*\(?\s*$|actions:\s*safe_join|actions:\s*\[/)
    rows << ["TABLE-05", "candidate", rel, i + 1, "export outside filter_bar actions:", raw.strip[0, 140]]
  end
end

File.open(OUT, "w") do |out|
  out.puts %w[rule certainty file line match source].join("\t")
  rows.uniq.sort_by { |r| [r[0], r[2], r[3]] }.each { |r| out.puts r.map { |c| c.to_s.delete("\t") }.join("\t") }
end
warn rows.group_by { |r| [r[0], r[1]] }.map { |k, v| "#{k.join(":")}=#{v.size}" }.sort.join("  ")
