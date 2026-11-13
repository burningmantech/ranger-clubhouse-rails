# frozen_string_literal: true

# Merges the mechanical census with the subagent inventories (read-only on app code).
#
#   ruby docs/design-audit/tools/build_inventory.rb
#
# Reads  docs/design-audit/data/{census.tsv,pages.tsv,inventory/*.txt}
# Writes docs/design-audit/data/inventory.json   every (file, pattern, variant) row, plus pages
#        docs/design-audit/inventory.md          overview, variant catalogue, components, not audited
#        docs/design-audit/inventory/<area>.md   per-page detail

require "json"
require "set"

ROOT = File.expand_path("../../..", __dir__)
AUDIT = File.join(ROOT, "docs/design-audit")
DATA = File.join(AUDIT, "data")
PATTERNS = %w[buttons links forms validation modals tables-lists navigation cards toasts-alerts empty-loading
              typography color spacing icons other].freeze
# Census rows that are leads for a human reader, not patterns in their own right.
CENSUS_SKIP = ["conditional-branch(candidate)"].freeze

def fields(line) = line.chomp.split(/\s*\|\|\s*/, -1).map(&:strip)

def norm_file(path)
  path.to_s.sub(%r{\A\./}, "").sub(/:\d[\d,\s-]*\z/, "")
end

rows = [] # {file, pattern, variant, impl, lines, note, source}
File.readlines(File.join(DATA, "census.tsv"), chomp: true).drop(1).each do |l|
  file, pattern, variant, impl, count, lines, detail = l.split("\t", -1)
  next if CENSUS_SKIP.include?(variant)
  rows << { file:, pattern:, variant:, impl:, count: count.to_i, lines:, note: detail.to_s, source: "census" }
end

pages = {} # template => {routes, kind, layout, audited, purpose, partials, group}
File.readlines(File.join(DATA, "pages.tsv"), chomp: true).drop(1).each do |l|
  template, kind, routes, partials, unresolved = l.split("\t", -1)
  pages[template] = { routes:, kind: kind == "html" ? "page" : kind, layout: "-", audited: "census-only",
                      purpose: "", partials: partials.to_s.split, unresolved: unresolved.to_s.split, group: nil }
end

components = []
tokens = []
variants = []
observations = []
drops = []
edges = Hash.new { |h, k| h[k] = Set.new }
bad = []

Dir[File.join(DATA, "inventory/*.txt")].sort.each do |path|
  group = File.basename(path, ".txt")
  File.readlines(path, chomp: true).each_with_index do |line, i|
    next if line.strip.empty? || line.start_with?("```")
    f = fields(line)
    case f[0]
    when "PAGE"
      template = norm_file(f[1])
      page = (pages[template] ||= { routes: "", kind: "other", partials: [], unresolved: [] })
      page[:routes] = f[2] if page[:routes].to_s.empty? || f[2].to_s.size > page[:routes].size
      page.merge!(kind: f[3] || page[:kind], layout: f[4] || "-", audited: f[5] || "yes",
                  purpose: f[6..].to_a.join(" | "), group:)
    when "ADD"
      pattern = PATTERNS.include?(f[2]) ? f[2] : "other"
      rows << { file: norm_file(f[1]), pattern:, variant: f[3].to_s, impl: f[4].to_s,
                count: f[5].to_s.split(",").size, lines: f[5].to_s.delete(" "), note: f[6..].to_a.join(" | "),
                source: group }
    when "DROP" then drops << { file: norm_file(f[1]), pattern: f[2], variant: f[3], reason: f[4..].to_a.join(" | "), source: group }
    when "EDGE" then edges[norm_file(f[1])] << f[2].to_s
    when "COMPONENT", "TOKEN", "BASE"
      (f[0] == "COMPONENT" ? components : tokens) << { kind: f[0], group:, fields: f[1..] }
    when "VARIANTS" then variants << { group:, pattern: f[1], text: f[2..].to_a.join(" | ") }
    when "OBS" then observations << { group:, text: f[1..].to_a.join(" | ") }
    else bad << "#{group}:#{i + 1}: #{line[0, 80]}"
    end
  end
end

# Apply DROPs to census rows.
dropped = 0
drops.each do |d|
  before = rows.size
  rows.reject! { |r| r[:source] == "census" && r[:file] == d[:file] && r[:variant] == d[:variant] }
  dropped += before - rows.size
end

# EDGE rows that name a real partial extend the page closure.
partial_of = lambda do |name|
  n = name[/[\w\/.-]+/].to_s
  next n if n.start_with?("app/views/") && File.exist?(File.join(ROOT, n))
  dir, base = File.split(n)
  cand = File.join("app/views", dir, "_#{base}.html.erb")
  File.exist?(File.join(ROOT, cand)) ? cand : nil
end
extra = Hash.new { |h, k| h[k] = Set.new }
edges.each { |from, names| names.each { |n| (p = partial_of.call(n)) && extra[from] << p } }
static = {} # file => partials rendered statically, from pages.tsv closure of pages only; rebuild per file below
pages.each_value do |page|
  queue = page[:partials].dup
  seen = page[:partials].to_set
  until queue.empty?
    extra[queue.shift].each { |p| queue << p if seen.add?(p) }
  end
  page[:partials] = seen.to_a.sort
end
pages.each { |template, page| extra[template].each { |p| page[:partials] |= [p] } }

# A wrapper page whose body lives in a shared template was marked partial/no by its own agent
# because that template belonged to another group. Every file under app/views was read by some
# group, so such a page is audited once its shared files resolve.
SHARED_ELSEWHERE = /common\/|other agent|another agent|another group|not inventoried|not inspected|not opened|outside (?:this|my) scope|wrapper|delegat/i
pages.each_value do |page|
  next unless %w[partial no].include?(page[:audited].to_s)
  next unless page[:purpose].to_s.match?(SHARED_ELSEWHERE) && page[:partials].any?
  page[:audited_by_own_group] = page[:audited]
  page[:audited] = "yes"
  page[:purpose] = "#{page[:purpose]} [shared files audited by their own group]"
end

by_file = rows.group_by { |r| r[:file] }
area_of = ->(template) { template.start_with?("app/views/") ? template.split("/")[2].sub(/\..*\z/, "") : template.split("/").first }

File.write(File.join(DATA, "inventory.json"), JSON.pretty_generate(
  generated_from: "census.tsv + inventory/*.txt", rows:, pages:, drops:, variants:, observations:
))

# ---- per-area page files ----------------------------------------------------
Dir.mkdir(File.join(AUDIT, "inventory")) unless Dir.exist?(File.join(AUDIT, "inventory"))
def md(text) = text.to_s.gsub("|", "\\|").gsub(/\s+/, " ").strip

pages.group_by { |t, _| area_of.call(t) }.sort_by(&:first).each do |area, list|
  File.open(File.join(AUDIT, "inventory/#{area}.md"), "w") do |out|
    out.puts "# Inventory: `app/views/#{area}`", ""
    out.puts "#{list.size} templates. Generated by `tools/build_inventory.rb`; do not edit by hand.", ""
    list.sort_by(&:first).each do |template, page|
      out.puts "## `#{template.sub("app/views/", "")}`", ""
      out.puts "- Route: #{page[:routes].to_s.empty? ? "none found" : md(page[:routes])}"
      out.puts "- Kind: #{page[:kind]}; layout: #{md(page[:layout])}; audited: #{page[:audited]}"
      out.puts "- #{md(page[:purpose])}" unless page[:purpose].to_s.empty?
      out.puts "- Partials reached: #{page[:partials].map { |p| "`#{p.sub("app/views/", "")}`" }.join(", ")}" if page[:partials].any?
      out.puts "- Renders not resolved statically: #{page[:unresolved].join(", ")}" if page[:unresolved].to_a.any?
      out.puts "", "| Pattern | Variant | Impl | Where | Detail |", "|---|---|---|---|---|"
      files = [template] + page[:partials]
      PATTERNS.each do |pattern|
        files.flat_map { |f| by_file.fetch(f, []).select { |r| r[:pattern] == pattern } }
             .sort_by { |r| [r[:variant], r[:file]] }.each do |r|
          where = "#{r[:file].sub("app/views/", "")}:#{r[:lines]}"
          out.puts "| #{pattern} | `#{md(r[:variant])}` | #{md(r[:impl])} | #{md(where)} | #{md(r[:note])[0, 220]} |"
        end
      end
      out.puts
    end
  end
end

# ---- variant catalogue --------------------------------------------------------
page_files = pages.transform_values { |p| p[:partials] }
pages_using = Hash.new { |h, k| h[k] = Set.new }
pages.each do |template, page|
  next unless %w[page print fragment].include?(page[:kind].to_s) || page[:kind].to_s.empty?
  ([template] + page[:partials]).each do |f|
    by_file.fetch(f, []).each { |r| pages_using[[r[:pattern], r[:variant]]] << template }
  end
end

File.open(File.join(AUDIT, "inventory.md"), "w") do |out|
  out.puts File.read(File.join(DATA, "inventory-intro.md")), ""
  out.puts "## Per-area page inventories", ""
  out.puts "One file per `app/views` area; each lists every template with its route, layout, the partials it", "reaches, and every pattern variant found in those files with `file:line`.", ""
  out.puts "| Area | Templates | Pages | Fragments | Other | Inventory rows | File |", "|---|---|---|---|---|---|---|"
  pages.group_by { |t, _| area_of.call(t) }.sort_by(&:first).each do |area, list|
    kinds = list.map { |_, p| p[:kind].to_s }.tally
    n = list.sum { |t, p| ([t] + p[:partials]).sum { |f| by_file.fetch(f, []).size } }
    other = list.size - kinds.fetch("page", 0) - kinds.fetch("fragment", 0)
    out.puts "| #{area} | #{list.size} | #{kinds.fetch("page", 0)} | #{kinds.fetch("fragment", 0)} | #{other} | #{n} | [inventory/#{area}.md](inventory/#{area}.md) |"
  end
  out.puts
  out.puts "## Pattern variant catalogue", ""
  out.puts "Every implementation variant found, per pattern. `Files` counts files containing it, `Pages` counts", "page templates that reach it directly or through a statically rendered partial.", ""
  PATTERNS.each do |pattern|
    list = rows.select { |r| r[:pattern] == pattern }.group_by { |r| r[:variant] }
    out.puts "### #{pattern} (#{list.size} variants)", "", "| Variant | Impl | Files | Uses | Pages | Examples |", "|---|---|---|---|---|---|"
    list.sort_by { |v, rs| [-pages_using[[pattern, v]].size, -rs.size, v] }.each do |variant, rs|
      impls = rs.map { |r| r[:impl] }.tally.sort_by { |_, n| -n }.map(&:first).first(2).join(", ")
      examples = rs.first(3).map { |r| "`#{r[:file].sub("app/", "")}:#{r[:lines].split(",").first}`" }.join(" ")
      out.puts "| `#{md(variant)}` | #{md(impls)} | #{rs.map { |r| r[:file] }.uniq.size} | #{rs.sum { |r| r[:count] }} | #{pages_using[[pattern, variant]].size} | #{examples} |"
    end
    out.puts
  end

  out.puts "## Same pattern, more than one implementation (reported by the inventory agents)", ""
  variants.sort_by { |v| [PATTERNS.index(v[:pattern]) || 99, v[:group]] }.each do |v|
    out.puts "- **#{v[:pattern]}** (#{v[:group]}): #{v[:text]}"
  end

  out.puts "", "## Shared component implementations", ""
  components.group_by { |c| c[:group] }.each do |group, list|
    out.puts "### #{group} (#{list.size})", ""
    list.each do |c|
      name, pattern, where, *rest = c[:fields]
      out.puts "- **`#{name}`** (#{pattern}, `#{where}`)"
      rest.each { |r| out.puts "  - #{r}" unless r.to_s.empty? }
    end
    out.puts
  end

  out.puts "## Design tokens and base rules (stylesheet layer)", ""
  tokens.each { |t| out.puts "- #{t[:kind]} `#{t[:fields][0]}` (`#{t[:fields][1]}`): #{t[:fields][2..].to_a.reject(&:empty?).join(" | ")}" }

  out.puts "", "## Observations recorded by the inventory agents", ""
  observations.group_by { |o| o[:group] }.each do |group, list|
    out.puts "### #{group}", ""
    list.each { |o| out.puts "- #{o[:text]}" }
    out.puts
  end

  out.puts "## Census rows dropped as false positives", ""
  drops.each { |d| out.puts "- `#{d[:file]}` #{d[:pattern]} `#{d[:variant]}`: #{d[:reason]} (#{d[:source]})" }

  out.puts "", "## Not fully audited", ""
  pages.select { |_, p| !%w[yes census-only].include?(p[:audited].to_s) }.sort_by(&:first).each do |t, p|
    out.puts "- `#{t}` (#{p[:audited]}): #{p[:purpose]}"
  end
  missing = pages.select { |_, p| p[:audited] == "census-only" }.keys
  out.puts "", "Templates with no agent PAGE row (census data only): #{missing.size}"
  missing.sort.each { |t| out.puts "- `#{t}`" }
end

kinds = pages.values.map { |p| p[:kind] }.tally
warn "rows=#{rows.size} (dropped #{dropped}) pages=#{pages.size} #{kinds} components=#{components.size} tokens=#{tokens.size} variants=#{variants.size} obs=#{observations.size} bad=#{bad.size}"
bad.first(40).each { |b| warn "  unparsed #{b}" }
