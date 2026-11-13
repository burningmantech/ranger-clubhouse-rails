# frozen_string_literal: true

# Phase 3: write report.md and findings.json from the classified inventory (read-only on app code).
#
#   ruby docs/design-audit/tools/build_report.rb
#
# Reads  data/classified.json, data/inventory.json, rules.md, data/report/*.md (hand-written sections)
# Writes report.md, findings.json

require "json"
require "set"
require_relative "uncovered_families"

ROOT = File.expand_path("../../..", __dir__)
AUDIT = File.join(ROOT, "docs/design-audit")
DATA = File.join(AUDIT, "data")
PATTERNS = %w[buttons links forms validation modals tables-lists navigation cards toasts-alerts empty-loading
              typography color spacing icons other].freeze
SHORT = { "buttons" => "Btn", "links" => "Link", "forms" => "Form", "validation" => "Valid", "modals" => "Modal",
          "tables-lists" => "Table", "navigation" => "Nav", "cards" => "Card", "toasts-alerts" => "Alert",
          "empty-loading" => "Empty", "typography" => "Type", "color" => "Color", "spacing" => "Space",
          "icons" => "Icon", "other" => "Other" }.freeze
WEIGHT = { "high" => 3, "medium" => 2, "low" => 1 }.freeze
SEV_ORDER = { "high" => 0, "medium" => 1, "low" => 2 }.freeze
D = "DIVERGENT"
U = "UNCOVERED"
C = "COMPLIANT"

classified = JSON.parse(File.read(File.join(DATA, "classified.json")), symbolize_names: true)
inventory = JSON.parse(File.read(File.join(DATA, "inventory.json")), symbolize_names: true)
pages = inventory[:pages].transform_keys(&:to_s)
findings = classified[:findings]
rule_rows = File.readlines(File.join(AUDIT, "rules.md"), chomp: true).grep(/\A\| [A-Z0-9]+-\d+ \|/)
RULE_TEXT = rule_rows.to_h { |l| c = l.split("|").map(&:strip); [c[1], c[5]] }

def md(text) = text.to_s.gsub("|", "\\|").gsub(/\s+/, " ").strip
def short(path) = path.to_s.sub(%r{\Aapp/views/}, "").sub(%r{\Aapp/}, "")

# Shared-layer component verdicts become findings too.
classified[:components].each_with_index do |c, i|
  next unless [C, D, U].include?(c[:classification])
  file, line = c[:where].to_s.split(":", 2)
  findings << { id: format("C%04d", i + 1), file: file.to_s, pattern: PATTERNS.include?(c[:pattern]) ? c[:pattern] : "other",
                variant: "component:#{c[:name]}", impl: "shared-layer", lines: line.to_s, source: c[:group],
                classification: c[:classification], rule_id: (c[:rule].to_s.match?(/\A[A-Z0-9]+-\d+\z/) ? c[:rule] : nil),
                severity: c[:classification] == D ? (WEIGHT.key?(c[:severity]) ? c[:severity] : "low") : nil,
                line: line.to_s[/\d+/], note: c[:note], basis: "component review (#{c[:group]})" }
end

findings.each do |f|
  f[:pattern] = "other" unless PATTERNS.include?(f[:pattern])
  f[:rule_id] = nil unless f[:rule_id].to_s.match?(/\A[A-Z0-9]+-\d+\z/)
  f[:severity] = nil unless f[:classification] == D
  f[:severity] = "low" if f[:classification] == D && !WEIGHT.key?(f[:severity])
end

# The same departure is often recorded twice: once by the census (the tag), once by a reader (the
# one-off it belongs to), sometimes again by a grep or a page sweep. Keep one divergent finding per
# file, rule and spot (lines within three of each other), preferring a reviewed note.
rank = ->(f) { [f[:basis].to_s.start_with?("reviewed") ? 0 : 1, f[:basis].to_s.start_with?("page sweep") ? 0 : 1, -f[:note].to_s.size] }
duplicates = 0
findings.select { |f| f[:classification] == D }.group_by { |f| [f[:file], f[:rule_id]] }.each_value do |list|
  kept = []
  list.sort_by { |f| rank.call(f) }.each do |f|
    line = f[:line].to_s[/\d+/].to_i
    twin = kept.find { |k| (k[:line].to_s[/\d+/].to_i - line).abs <= 3 }
    if twin
      twin[:severity] = f[:severity] if SEV_ORDER.fetch(f[:severity], 3) < SEV_ORDER.fetch(twin[:severity], 3)
      f[:duplicate] = true
      duplicates += 1
    else
      kept << f
    end
  end
end
findings.reject! { |f| f[:duplicate] }

# ---- which pages does a file belong to? --------------------------------------
page_kinds = %w[page fragment print]
audited_pages = pages.select { |_, p| page_kinds.include?(p[:kind].to_s) }
files_of = audited_pages.transform_values { |p| p[:partials].to_a }
pages_of_file = Hash.new { |h, k| h[k] = [] }
files_of.each { |template, partials| ([template] + partials).each { |f| pages_of_file[f] << template } }
# An area helper belongs to the templates of the controller it is named for:
# app/helpers/admin/jobs_helper.rb -> app/views/admin/jobs/*
helper_pages = lambda do |file|
  m = file.match(%r{\Aapp/helpers/(.+)_helper\.rb\z}) or return []
  audited_pages.keys.select { |t| t.start_with?("app/views/#{m[1]}/") }
end
findings.each do |f|
  list = pages_of_file.fetch(f[:file], nil) || helper_pages.call(f[:file])
  f[:pages] = list.uniq.sort
end

by_page = Hash.new { |h, k| h[k] = [] }
findings.each { |f| f[:pages].each { |p| by_page[p] << f } }

score = ->(list) { list.sum { |f| f[:classification] == D ? WEIGHT.fetch(f[:severity], 1) : 0 } }
own = ->(template) { by_page[template].select { |f| f[:file] == template } }

# ---- findings.json -----------------------------------------------------------------
json = findings.map do |f|
  { id: f[:id],
    page: audited_pages.key?(f[:file]) ? f[:file] : (f[:pages].size == 1 ? f[:pages].first : "(shared) #{f[:file]}"),
    pattern: f[:pattern], variant: f[:variant], classification: f[:classification], rule_id: f[:rule_id],
    severity: f[:severity], file: f[:file], line: f[:line].to_s[/\d+/]&.to_i, note: f[:note].to_s,
    used_by_pages: f[:pages].size, basis: f[:basis] }
end
json.sort_by! { |f| [f[:file], f[:line] || 0, f[:pattern], f[:variant].to_s, f[:id]] }
File.open(File.join(AUDIT, "findings.json"), "w") do |out|
  out.puts "["
  out.puts json.map { |f| "  #{JSON.generate(f)}" }.join(",\n")
  out.puts "]"
end

# ---- report ----------------------------------------------------------------------------
tally = findings.map { |f| f[:classification] }.tally
sev = findings.select { |f| f[:classification] == D }.map { |f| f[:severity] }.tally
section = ->(name) { path = File.join(DATA, "report/#{name}.md"); File.exist?(path) ? File.read(path).strip : "_(section not written)_" }
# Several routes render one shared template (me/schedule, person/scheduling and hq/scheduling all
# render common/schedule/index). Templates with the same set of divergent findings are one screen.
screens = audited_pages.keys.select { |t| pages[t][:kind].to_s == "page" }
                       .group_by { |t| by_page[t].select { |f| f[:classification] == D }.map { |f| f[:id] }.sort }
ranked = screens.reject { |ids, _| ids.empty? }.map do |_, members|
  lead = members.max_by { |t| [score.call(own.call(t)), t.include?("/common/") ? 1 : 0] }
  [lead, score.call(by_page[lead]), score.call(own.call(lead)), members - [lead]]
end
ranked = ranked.sort_by { |t, s, o, _| [-s, -o, t] }

File.open(File.join(AUDIT, "report.md"), "w") do |out|
  out.puts "# UI Design Audit", ""
  out.puts section.call("intro"), ""

  out.puts "## Rule IDs", ""
  out.puts "The guide has no rule IDs, so the audit assigned them. `Judged`: **M** a grep settles it, **R** a reader", "must open the code, **V** it needs a rendered page, **P** a process rule code cannot show. The same", "table, with notes on keeping the IDs stable, is in [rules.md](rules.md).", ""
  out.puts "<details><summary>All #{rule_rows.size} rules</summary>", "", "| ID | Priority | Guide lines | Judged | Rule |", "|---|---|---|---|---|"
  rule_rows.each { |l| out.puts l }
  out.puts "", "</details>", ""

  # 1. Summary
  out.puts "## 1. Summary", ""
  kinds = pages.values.map { |p| p[:kind].to_s }.tally
  out.puts "| | |", "|---|---|"
  out.puts "| Templates audited | #{audited_pages.size} (#{kinds["page"]} pages, #{kinds["fragment"]} fragments, #{kinds["print"]} print sheets) |"
  out.puts "| Also inventoried | #{kinds["layout"]} layouts, #{kinds["turbo-stream"]} turbo-stream responses, #{(kinds["other"] || 0) + (kinds["mail"] || 0) + (kinds["fixture"] || 0)} others; #{classified[:components].size} shared helpers, classes, tokens and controllers |"
  out.puts "| Pattern variants classified | #{findings.size} (after merging #{duplicates} duplicate records of the same departure) |"
  out.puts "| COMPLIANT | #{tally[C]} |"
  out.puts "| DIVERGENT | #{tally[D]} (#{sev["high"].to_i} high, #{sev["medium"].to_i} medium, #{sev["low"].to_i} low) |"
  out.puts "| UNCOVERED | #{tally[U]} |"
  clean = audited_pages.keys.count { |t| by_page[t].none? { |f| f[:classification] == D } }
  out.puts "| Templates with no divergent finding | #{clean} of #{audited_pages.size} |"
  out.puts "", section.call("summary"), ""

  out.puts "### The five pages furthest out of sync", ""
  out.puts "Ranked by weighted divergent findings on the page and the partials it renders (high 3, medium 2, low 1).", "\"Own file\" counts only the page's own template, so a page is not ranked high merely for rendering a", "shared partial that has findings.", ""
  out.puts "| # | Page | Route | Score | High | Medium | Low | Own-file score | Main departures |", "|---|---|---|---|---|---|---|---|---|"
  ranked.first(5).each_with_index do |(t, s, o, twins), i|
    list = by_page[t].select { |f| f[:classification] == D }
    counts = list.map { |f| f[:severity] }.tally
    rules = list.map { |f| f[:rule_id] }.compact.tally.sort_by { |_, n| -n }.first(4).map { |r, n| "#{r} ×#{n}" }.join(", ")
    routes = ([t] + twins).flat_map { |m| pages[m][:routes].to_s.split(";") }.map(&:strip).grep(/\AGET /).map { |r| r.sub(/\AGET /, "").sub(/\s*\(via.*?\)/, "") }.uniq.first(4).join(", ")
    out.puts "| #{i + 1} | `#{short(t)}` | #{md(routes)} | #{s} | #{counts["high"].to_i} | #{counts["medium"].to_i} | #{counts["low"].to_i} | #{o} | #{rules} |"
  end
  out.puts "", "The next fifteen:", "", "| # | Page | Score | Own-file score |", "|---|---|---|---|"
  ranked[5, 15].to_a.each_with_index { |(t, s, o, _), i| out.puts "| #{i + 6} | `#{short(t)}` | #{s} | #{o} |" }

  out.puts "", "### Rules departed from most", "", "| Rule | Findings | High | Medium | Low | Templates touched | Rule |", "|---|---|---|---|---|---|---|"
  findings.select { |f| f[:classification] == D }.group_by { |f| f[:rule_id] || "(no rule cited)" }
          .sort_by { |_, l| -l.size }.first(25).each do |rule, list|
    c = list.map { |f| f[:severity] }.tally
    out.puts "| #{rule} | #{list.size} | #{c["high"].to_i} | #{c["medium"].to_i} | #{c["low"].to_i} | #{list.flat_map { |f| f[:pages] }.uniq.size} | #{md(RULE_TEXT[rule].to_s)[0, 150]} |"
  end
  out.puts

  # 2. Matrix
  out.puts "## 2. Page-by-pattern matrix", ""
  out.puts "One row per audited template, one column per pattern. `D`*n*: at least one divergent variant (*n* of them);", "`U`: no divergence, at least one variant no rule covers; `C`: every variant found is covered and compliant;", "`·`: the pattern does not occur. A cell reflects the template and every partial it renders.", ""
  cell = lambda do |list|
    next "·" if list.empty?
    d = list.count { |f| f[:classification] == D }
    next "**D#{d}**" if d.positive?
    list.any? { |f| f[:classification] == U } ? "U" : "C"
  end
  audited_pages.keys.group_by { |t| t.split("/")[2].to_s.sub(/\..*/, "") }.sort_by(&:first).each do |area, list|
    area_score = list.sum { |t| score.call(own.call(t)) }
    out.puts "<details><summary><strong>#{area}</strong> (#{list.size} templates, own-file divergence score #{area_score})</summary>", ""
    out.puts "| Template | #{PATTERNS.map { |p| SHORT[p] }.join(" | ")} |", "|---|#{"---|" * PATTERNS.size}"
    list.sort.each do |t|
      per = by_page[t].group_by { |f| f[:pattern] }
      out.puts "| `#{short(t).sub("#{area}/", "")}` | #{PATTERNS.map { |p| cell.call(per.fetch(p, [])) }.join(" | ")} |"
    end
    out.puts "", "</details>", ""
  end

  # 3. Divergent findings by page
  out.puts "## 3. Divergent findings", ""
  out.puts section.call("divergent-intro"), ""
  line_of = ->(f) { "- **#{f[:severity]}** `#{f[:rule_id] || "-"}` `#{short(f[:file])}:#{f[:line].to_s[/\d+/] || "?"}` #{f[:pattern]}: #{md(f[:note])}" }
  sort = ->(list) { list.sort_by { |f| [SEV_ORDER.fetch(f[:severity], 3), f[:rule_id].to_s, f[:line].to_s.to_i] } }
  divergent = findings.select { |f| f[:classification] == D }
  own_page = divergent.select { |f| audited_pages.key?(f[:file]) }
  shared = divergent - own_page

  out.puts "### 3.1 Pages", ""
  own_page.group_by { |f| f[:file].split("/")[2].to_s.sub(/\..*/, "") }.sort_by(&:first).each do |area, list|
    out.puts "#### #{area} (#{list.size})", ""
    list.group_by { |f| f[:file] }.sort_by { |t, l| [-score.call(l), t] }.each do |template, fl|
      route = pages.dig(template, :routes).to_s.split(";").first
      out.puts "**`#{short(template)}`**#{route.to_s.empty? ? "" : " (#{md(route)})"}", ""
      sort.call(fl).each { |f| out.puts line_of.call(f) }
      out.puts
    end
  end

  out.puts "### 3.2 Shared partials and area helpers", "", "Findings in a file that several pages render. \"Used by\" counts the audited templates that reach it.", ""
  shared.reject { |f| f[:impl] == "shared-layer" }.group_by { |f| f[:file] }.sort_by { |file, l| [-l.first[:pages].size, file] }.each do |file, fl|
    out.puts "**`#{short(file)}`** (used by #{fl.first[:pages].size})", ""
    sort.call(fl).each { |f| out.puts line_of.call(f) }
    out.puts
  end

  out.puts "### 3.3 Shared layer: helpers, stylesheets, controllers", "", "Where the implementation of a shared component differs from what the guide documents for it. One fix", "here changes every page that uses the component.", ""
  shared.select { |f| f[:impl] == "shared-layer" }.group_by { |f| f[:basis] }.sort_by(&:first).each do |basis, fl|
    out.puts "**#{basis.sub("component review ", "").delete("()")}** (#{fl.size})", ""
    sort.call(fl).each { |f| out.puts "- **#{f[:severity]}** `#{f[:rule_id] || "-"}` `#{f[:variant].sub("component:", "")}` (`#{short(f[:file])}:#{f[:line] || "?"}`): #{md(f[:note])}" }
    out.puts
  end

  # 4. Guidelines to write
  out.puts "## 4. Guidelines to write", ""
  out.puts section.call("uncovered-intro"), ""
  uncovered = findings.select { |f| f[:classification] == U }
  fams = Hash.new { |h, k| h[k] = [] }
  uncovered.each { |f| fams[family_of(f)] << f }
  out.puts "| # | Uncovered pattern | Templates | Variants found (files) | Recommended standard |", "|---|---|---|---|---|"
  last = ["Other one-off markup", "Undocumented shared helpers, classes and controllers (shared layer)"]
  ranked_fams = fams.sort_by { |name, l| [last.index(name) || -1, -l.flat_map { |f| f[:pages] }.uniq.size, -l.size] }
  ranked_fams.each_with_index do |(name, list), i|
    variants = list.group_by { |f| variant_label(f) }.sort_by { |_, l| -l.size }.first(8)
                   .map { |v, l| "`#{md(v)}` (#{l.map { |f| f[:file] }.uniq.size})" }.join(", ")
    out.puts "| #{i + 1} | #{name} (#{list.size} uses) | #{list.flat_map { |f| f[:pages] }.uniq.size} | #{variants} | #{md(FAMILY_RECOMMENDATION.fetch(name, "—"))} |"
  end
  out.puts
  ambiguous = uncovered.select { |f| f[:note].to_s.match?(/\Aambiguous\b/i) }
  out.puts "### Rules too vague to judge against", "", "Marked UNCOVERED rather than guessed at. Each needs a sentence added to the guide.", ""
  ambiguous.group_by { |f| f[:note][/[A-Z0-9]+-\d+/] || "(no rule named)" }.sort_by { |_, l| -l.size }.each do |rule, list|
    out.puts "- **#{rule}** (#{list.size} cases, #{list.flat_map { |f| f[:pages] }.uniq.size} templates): #{md(RULE_TEXT[rule].to_s)[0, 120]}"
    notes = list.map { |f| f[:note].sub(/\Aambiguous\s+[A-Z0-9-]+:?\s*/i, "") }
    ruled, plain = notes.partition { |n| n.include?(" Found: ") }
    if ruled.any?
      out.puts "  - What the guide leaves open: #{md(ruled.first.split(" Found: ").first)}"
      ruled.first(3).each { |n| out.puts "  - e.g. #{md(n.split(" Found: ", 2).last)[0, 190]}" }
    end
    plain.tally.sort_by { |_, n| -n }.first(ruled.any? ? 1 : 3).each { |n, c| out.puts "  - #{md(n)[0, 200]}#{c > 1 ? " (×#{c})" : ""}" }
  end
  out.puts

  out.puts "## 5. Rules that could be enforced mechanically", "", section.call("mechanical"), ""
  out.puts "## 6. Not audited, and what code alone could not confirm", "", section.call("not-audited"), ""

  out.puts "### What the page sweeps covered", "", "Each reviewer checked these page-level rules on every template in its area and reported the count.", "", "| Rule | Templates checked | Departures reported |", "|---|---|---|"
  classified[:sweeps].group_by { |s| s[:rule] }.sort_by(&:first).each do |rule, list|
    out.puts "| #{rule} | #{list.sum { |s| s[:checked].to_i }} | #{list.sum { |s| s[:divergent].to_i }} |"
  end
  out.puts

  out.puts "## 7. Observations", "", section.call("observations"), ""
  out.puts "### Reviewers' observations, as recorded", "", "<details><summary>#{classified[:opinions].size} notes from the classification pass</summary>", ""
  classified[:opinions].group_by { |o| o[:group] }.sort_by(&:first).each do |group, list|
    out.puts "**#{group}**", ""
    list.each { |o| out.puts "- #{md(o[:text])}" }
    out.puts
  end
  out.puts "</details>"
end

warn "report: #{findings.size} findings #{tally} severity=#{sev} pages=#{audited_pages.size} unreviewed=#{classified[:unreviewed].size}"
warn "top5: #{ranked.first(8).map { |t, s, o, tw| "#{short(t)}=#{s}/#{o}(+#{tw.size})" }.join("  ")}"
