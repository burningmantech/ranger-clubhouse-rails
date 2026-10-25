#!/usr/bin/env ruby
# frozen_string_literal: true

# css_census.rb — a deterministic inventory of CSS class usage in Rails view code.
#
# No gems, no Rails boot required. Run from the Rails root:
#
#   ruby bin/css_census.rb                    # human-readable report
#   ruby bin/css_census.rb --format json      # machine-readable, for a follow-up pass
#   ruby bin/css_census.rb --min 3 --top 25   # only clusters seen 3+ times
#
# It exists so that the audit stage is measured rather than guessed: an LLM skimming
# views will miss duplicates, but this will not.

require "json"
require "optparse"
require "set"
require_relative "../lib/css_matchers"

OPTS = {
  roots: %w[app/views app/components app/helpers app/presenters app/decorators app/javascript],
  exts: %w[.erb .rb .haml .slim .html .js],
  min: 2,        # minimum occurrences for a cluster to be reported
  min_tokens: 2, # ignore trivial one-class attributes
  top: 40,
  jaccard: 0.7,
  format: "text"
}.freeze

opts = OPTS.dup
OptionParser.new do |o|
  o.banner = "Usage: ruby bin/css_census.rb [options]"
  o.on("--roots a,b,c", Array, "Directories to scan (default: #{OPTS[:roots].join(",")})") { |v| opts[:roots] = v }
  o.on("--min N", Integer, "Min occurrences for a duplicate cluster (default #{OPTS[:min]})") { |v| opts[:min] = v }
  o.on("--min-tokens N", Integer, "Min classes in an attribute (default #{OPTS[:min_tokens]})") { |v| opts[:min_tokens] = v }
  o.on("--top N", Integer, "Rows per section (default #{OPTS[:top]})") { |v| opts[:top] = v }
  o.on("--jaccard F", Float, "Near-duplicate similarity threshold (default #{OPTS[:jaccard]})") { |v| opts[:jaccard] = v }
  o.on("--format FMT", %w[text json], "text or json (default text)") { |v| opts[:format] = v }
end.parse!

# ---------------------------------------------------------------- extraction --

CLASS_ATTR   = /\bclass\s*=\s*(["'])(.*?)\1/m           # class="..." in markup
CLASS_KWARG  = /\bclass:\s*(["'])(.*?)\1/m              # class: "..." in Ruby / tag helpers
# style = "regular" in Ruby is an assignment; an HTML attribute has no spaces.
STYLE_ATTR   = /\bstyle=(["'])(.*?)\1/m
DYNAMIC      = /<%|#\{|\{\{/                            # ERB / interpolation / mustache

# Interpolation that builds a class *name* — invisible to Tailwind's scanner, so
# the class silently never makes it into the compiled stylesheet.
#
# Two families, and both fail the same way. The first is Tailwind's own utility
# prefixes. The second is component prefixes that take a variant suffix —
# daisyUI's, plus the ones this app defines itself — where `badge-<%= variant %>`
# is the obvious thing to reach for and is just as dead as `bg-<%= colour %>`.
UNSCANNABLE = /\b(?:bg|text|border|ring|from|via|to|fill|stroke|shadow|w|h|min-w|max-w|min-h|max-h|
                 p|px|py|pt|pb|pl|pr|m|mx|my|mt|mb|ml|mr|gap|grid-cols|col-span|basis|order|z|
                 rounded|opacity|duration|delay|translate-x|translate-y|scale|
                 btn|badge|alert|card|input|select|textarea|checkbox|toggle|range|file-input|
                 tab|tabs|menu|navbar|drawer|dropdown|modal|join|stat|steps|breadcrumbs|tooltip|
                 avatar|loading|skeleton|divider|collapse|chat|timeline|progress|radial-progress|
                 mask|indicator|swap|carousel|hero|footer|
                 box|icon|toast)-(?:<%|\#\{)/x

# What counts as a palette colour, an arbitrary value or an !important lives in
# lib/css_matchers.rb, so it can be tested. Each of those rules has been wrong
# once, in ways no one noticed until a unit removed colours the census had been
# calling clean.

files = opts[:roots].flat_map do |root|
  next [] unless Dir.exist?(root)

  Dir.glob(File.join(root, "**", "*")).select do |p|
    File.file?(p) && opts[:exts].any? { |e| p.end_with?(e) }
  end
end.sort

def line_of(source, offset)
  source[0, offset].count("\n") + 1
end

static  = []   # {tokens:, key:, file:, line:, raw:}
dynamic = []   # {raw:, file:, line:, unscannable:}
styles  = []   # {raw:, file:, line:}

files.each do |path|
  src = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)

  record = lambda do |raw, offset|
    rec = { raw: raw.strip, file: path, line: line_of(src, offset) }

    if raw.match?(DYNAMIC)
      dynamic << rec.merge(unscannable: raw.match?(UNSCANNABLE))
    else
      tokens = raw.split(/\s+/).reject(&:empty?).uniq
      next if tokens.empty?

      static << rec.merge(tokens: tokens, key: tokens.sort.join(" "))
    end
  end

  # Where a class list has already been found, so the bare-string pass below
  # does not count `class: "a b"` a second time.
  claimed = []

  [CLASS_ATTR, CLASS_KWARG].each do |re|
    src.to_enum(:scan, re).each do
      m = Regexp.last_match
      claimed << (m.begin(2)...m.end(2))
      record.call(m[2].to_s, m.begin(0))
    end
  end

  # Ruby and JS hold class lists in constants, helper arguments and Stimulus
  # values, none of which look like `class=` or `class:`. Code files only: in a
  # template a bare string is far more likely to be a label than a class list,
  # and the two patterns above already cover the template cases.
  if path.end_with?(".rb", ".js")
    src.to_enum(:scan, CssMatchers::CODE_STRING).each do
      m = Regexp.last_match
      next if claimed.any? { |span| span.cover?(m.begin(2)) }
      next unless CssMatchers.classy?(m[2])

      record.call(m[2].to_s, m.begin(0))
    end
  end

  src.to_enum(:scan, STYLE_ATTR).each do
    m = Regexp.last_match
    styles << { raw: m[2].to_s.strip, file: path, line: line_of(src, m.begin(0)) }
  end
end

# Tailwind reads app/javascript too, and a class name glued to a template
# placeholder there is the same bug in a third spelling. Read whatever --roots
# says: the lint's roots are views and helpers, and this one rule has to reach
# JS without moving the numbers the ratchet recorded for those two.
Dir.glob("app/javascript/**/*.{js,ts}").reject { |path| path.include?("/vendor/") }.sort.each do |path|
  File.foreach(path).with_index(1) do |line, number|
    next unless CssMatchers.glued_js_class?(line)

    dynamic << { raw: line.strip, file: path, line: number, unscannable: true }
  end
end

# ------------------------------------------------------------------ analysis --

clusters = static.group_by { |e| e[:key] }.map do |key, entries|
  tokens = key.split(" ")
  {
    key: key,
    tokens: tokens,
    count: entries.size,
    size: tokens.size,
    # How many class tokens vanish from the codebase if this cluster is extracted once.
    weight: (entries.size - 1) * tokens.size,
    sites: entries.map { |e| "#{e[:file]}:#{e[:line]}" }.uniq
  }
end

duplicates = clusters
  .select { |c| c[:count] >= opts[:min] && c[:size] >= opts[:min_tokens] }
  .sort_by { |c| [-c[:weight], -c[:count]] }

# Near-duplicates: distinct class strings that are *almost* the same. These are the
# expensive ones — they read as intentional variation but are usually drift.
candidates = clusters.select { |c| c[:size] >= 3 }.sort_by { |c| -c[:count] }.first(400)
seen = Set.new
families = []
candidates.each_with_index do |a, i|
  next if seen.include?(a[:key])

  group = [a]
  ta = a[:tokens].to_set
  candidates[(i + 1)..].to_a.each do |b|
    next if seen.include?(b[:key])

    tb = b[:tokens].to_set
    sim = (ta & tb).size.to_f / (ta | tb).size
    group << b if sim >= opts[:jaccard] && sim < 1.0
  end
  next if group.size < 2

  group.each { |g| seen << g[:key] }
  shared = group.map { |g| g[:tokens].to_set }.reduce(:&)
  families << {
    variants: group.size,
    occurrences: group.sum { |g| g[:count] },
    shared: shared.to_a.sort,
    differing: group.map { |g| { classes: (g[:tokens].to_set - shared).to_a.sort, count: g[:count], at: g[:sites].first } }
  }
end
families.sort_by! { |f| [-f[:occurrences], -f[:variants]] }

token_freq = Hash.new(0)
static.each { |e| e[:tokens].each { |t| token_freq[t] += 1 } }

def offenders(static, &predicate)
  hits = Hash.new { |h, k| h[k] = { count: 0, sites: [] } }
  static.each do |e|
    e[:tokens].select(&predicate).each do |t|
      hits[t][:count] += 1
      hits[t][:sites] << "#{e[:file]}:#{e[:line]}" if hits[t][:sites].size < 5
    end
  end
  hits.sort_by { |_, v| -v[:count] }
end

palette   = offenders(static) { |t| t.match?(CssMatchers::PALETTE) }
bare_bw   = offenders(static) { |t| t.match?(CssMatchers::BARE_BW) }
arbitrary = offenders(static) { |t| CssMatchers.arbitrary?(t) }
bangs     = offenders(static) { |t| CssMatchers.important?(t) }

# Hand-rolled daisyUI components: clusters that reimplement something daisyUI ships.
SHAPES = {
  "btn" => {
    # must look clickable, not just boxy
    required: [[/\Arounded/], [/\Ahover:(bg|text|border)-/, /\Atransition/, /\Acursor-pointer\z/, /\Afocus:/],
               [/\Apx-/], [/\Ainline-flex\z/, /\Aflex\z/, /\Ainline-block\z/, /\Ablock\z/]],
    signals: [/\Ainline-flex\z/, /\Aitems-center\z/, /\Ajustify-center\z/, /\Arounded/, /\Apx-/, /\Apy-/,
              /\Afont-(medium|semibold|bold)\z/, /\Atransition/, /\Ahover:bg-/, /\Acursor-pointer\z/,
              /\Afocus:ring/, /\Adisabled:/],
    threshold: 6,
    hint: "btn + btn-primary / btn-sm / btn-outline / btn-ghost"
  },
  "card" => {
    required: [[/\Arounded/], [/\Ashadow/, /\Aborder\z/], [/\Abg-/], [/\Ap-\d/, /\Apx-\d/, /\Ap-\d\z/]],
    signals: [/\Arounded-(lg|xl|2xl|3xl|box)\z/, /\Aborder\z/, /\Aborder-/, /\Ashadow/, /\Abg-/, /\Ap-\d/,
              /\Aoverflow-hidden\z/, /\Adivide-y\z/],
    threshold: 5,
    hint: "card + card-body / card-title / card-border"
  },
  "badge" => {
    required: [[/\Arounded-full\z/], [/\Atext-xs\z/, /\Atext-\[?1[01]px/], [/\Apx-/]],
    signals: [/\Arounded-full\z/, /\Atext-xs\z/, /\Apx-[12](\.5)?\z/, /\Apy-(0\.5|1)\z/, /\Afont-(medium|semibold)\z/,
              /\Ainline-flex\z/, /\Auppercase\z/, /\Atracking-/],
    threshold: 4,
    hint: "badge + badge-sm / badge-outline / badge-success"
  },
  "input" => {
    required: [[/\Aborder\z/, /\Aborder-/], [/\Afocus:(ring|border|outline)/], [/\Arounded/]],
    signals: [/\Aw-full\z/, /\Aborder\z/, /\Arounded/, /\Apx-[23]\z/, /\Apy-[12](\.5)?\z/,
              /\Afocus:(ring|border|outline)/, /\Ashadow-sm\z/, /\Aplaceholder/, /\Adisabled:/],
    threshold: 5,
    hint: "input + input-bordered (or select / textarea / fieldset + label)"
  },
  "alert" => {
    required: [[/\Abg-(red|green|yellow|blue|amber|emerald|rose)-\d/],
               [/\Atext-(red|green|yellow|blue|amber|emerald|rose)-\d/, /\Aborder-(red|green|yellow|blue|amber|emerald|rose)-\d/],
               [/\Ap-\d/, /\Apx-\d/]],
    signals: [/\Arounded/, /\Ap-[34]\z/, /\Aflex\z/, /\Aitems-(start|center)\z/, /\Agap-/,
              /\Abg-(red|green|yellow|blue|amber|emerald|rose)-\d/,
              /\Atext-(red|green|yellow|blue|amber|emerald|rose)-\d/,
              /\Aborder-(red|green|yellow|blue|amber|emerald|rose)-\d/],
    threshold: 5,
    hint: "alert + alert-info / alert-success / alert-warning / alert-error"
  }
}.freeze

handrolled = []
clusters.each do |c|
  next if c[:size] < 4

  best = nil
  SHAPES.each do |name, spec|
    next if c[:tokens].include?(name) # already using the daisyUI component
    next if c[:tokens].any? { |t| t.start_with?("#{name}-") }
    # every required group must have at least one matching token
    next unless spec[:required].all? { |group| group.any? { |re| c[:tokens].any? { |t| t.match?(re) } } }

    matched = spec[:signals].count { |re| c[:tokens].any? { |t| t.match?(re) } }
    next if matched < spec[:threshold]

    best = { name: name, spec: spec, score: matched } if best.nil? || matched > best[:score]
  end
  next unless best

  handrolled << c.merge(looks_like: best[:name], hint: best[:spec][:hint], confidence: best[:score])
end
handrolled.sort_by! { |c| [-c[:count], -c[:confidence]] }

longest = clusters.sort_by { |c| -c[:size] }.first(opts[:top])

summary = {
  files_scanned: files.size,
  class_attributes: static.size + dynamic.size,
  static_attributes: static.size,
  distinct_class_strings: clusters.size,
  duplicate_clusters: duplicates.size,
  redundant_tokens: duplicates.sum { |c| c[:weight] },
  near_duplicate_families: families.size,
  dynamic_class_attributes: dynamic.size,
  unscannable_class_names: dynamic.count { |d| d[:unscannable] },
  inline_style_attributes: styles.size,
  hardcoded_palette_tokens: palette.sum { |_, v| v[:count] },
  arbitrary_value_tokens: arbitrary.sum { |_, v| v[:count] },
  important_tokens: bangs.sum { |_, v| v[:count] }
}

report = {
  summary: summary,
  duplicates: duplicates.first(opts[:top]),
  near_duplicates: families.first(opts[:top]),
  handrolled_components: handrolled.first(opts[:top]),
  hardcoded_palette: palette.first(opts[:top]).map { |t, v| { token: t }.merge(v) },
  bare_black_white: bare_bw.first(15).map { |t, v| { token: t }.merge(v) },
  arbitrary_values: arbitrary.first(opts[:top]).map { |t, v| { token: t }.merge(v) },
  important: bangs.first(15).map { |t, v| { token: t }.merge(v) },
  unscannable: dynamic.select { |d| d[:unscannable] }.first(opts[:top]),
  inline_styles: styles.first(opts[:top]),
  longest_class_strings: longest.map { |c| { size: c[:size], count: c[:count], at: c[:sites].first, key: c[:key] } },
  top_tokens: token_freq.sort_by { |_, v| -v }.first(opts[:top]).map { |t, n| { token: t, count: n } }
}

if opts[:format] == "json"
  puts JSON.pretty_generate(report)
  exit
end

# -------------------------------------------------------------------- output --

def section(title)
  puts
  puts "═" * 78
  puts title
  puts "═" * 78
end

puts "CSS CENSUS — #{Dir.pwd}"
puts "roots: #{opts[:roots].select { |r| Dir.exist?(r) }.join(", ")}"
summary.each { |k, v| puts format("  %-28s %s", k.to_s.tr("_", " "), v) }

section "1. EXACT DUPLICATE CLASS STRINGS (order-insensitive), by tokens saved"
if duplicates.empty?
  puts "  none above the threshold."
else
  duplicates.first(opts[:top]).each_with_index do |c, i|
    puts format("\n[D%02d] x%-3d %d classes  → saves ~%d tokens", i + 1, c[:count], c[:size], c[:weight])
    puts "      #{c[:key]}"
    c[:sites].first(6).each { |s| puts "        #{s}" }
    puts "        … #{c[:sites].size - 6} more" if c[:sites].size > 6
  end
end

section "2. NEAR-DUPLICATE FAMILIES (drift: same intent, slightly different classes)"
if families.empty?
  puts "  none above the similarity threshold."
else
  families.first(opts[:top]).each_with_index do |f, i|
    puts format("\n[N%02d] %d variants, %d uses", i + 1, f[:variants], f[:occurrences])
    puts "      shared:  #{f[:shared].join(" ")}"
    f[:differing].each { |d| puts format("      x%-3d +/- %-40s %s", d[:count], d[:classes].join(" "), d[:at]) }
  end
end

section "3. HAND-ROLLED daisyUI COMPONENTS (utilities reimplementing a component class)"
if handrolled.empty?
  puts "  none detected."
else
  handrolled.first(opts[:top]).each_with_index do |c, i|
    puts format("\n[C%02d] looks like .%s (x%d uses, confidence %d)", i + 1, c[:looks_like], c[:count], c[:confidence])
    puts "      replace with: #{c[:hint]}"
    puts "      current:      #{c[:key]}"
    c[:sites].first(4).each { |s| puts "        #{s}" }
  end
end

section "4. UNSCANNABLE CLASS NAMES (built by interpolation — Tailwind cannot see these)"
if report[:unscannable].empty?
  puts "  none. good."
else
  puts "  These may already be broken in production: the utility is never compiled."
  report[:unscannable].each { |d| puts "  #{d[:file]}:#{d[:line]}\n      #{d[:raw][0, 140]}" }
end

section "5. HARDCODED PALETTE COLORS (should be daisyUI semantic tokens)"
if palette.empty?
  puts "  none. good."
else
  palette.first(opts[:top]).each { |t, v| puts format("  x%-4d %-34s %s", v[:count], t, v[:sites].first) }
  puts "\n  map to: primary / secondary / accent / neutral / info / success / warning / error"
  puts "          base-100 / base-200 / base-300 / base-content / *-content"
end

unless bare_bw.empty?
  section "5b. bg-white / text-black etc. (breaks theme switching)"
  bare_bw.first(15).each { |t, v| puts format("  x%-4d %-34s %s", v[:count], t, v[:sites].first) }
end

section "6. ARBITRARY VALUES (escape hatches that should be scale steps or tokens)"
if arbitrary.empty?
  puts "  none."
else
  arbitrary.first(opts[:top]).each { |t, v| puts format("  x%-4d %-40s %s", v[:count], t, v[:sites].first) }
end

unless bangs.empty?
  section "7. !important UTILITIES (specificity fights — usually a missing abstraction)"
  bangs.first(15).each { |t, v| puts format("  x%-4d %-40s %s", v[:count], t, v[:sites].first) }
end

section "8. INLINE style=\"\" ATTRIBUTES"
if styles.empty?
  puts "  none."
else
  styles.first(opts[:top]).each { |s| puts "  #{s[:file]}:#{s[:line]}  #{s[:raw][0, 90]}" }
  puts "  (#{styles.size} total)"
end

section "9. LONGEST CLASS STRINGS (extract candidates even when used once)"
longest.first(15).each { |c| puts format("  %2d classes x%-3d %s\n      %s", c[:size], c[:count], c[:sites].first, c[:key]) }

section "10. MOST-USED INDIVIDUAL UTILITIES"
report[:top_tokens].each_slice(4) do |row|
  puts "  " + row.map { |t| format("%-22s", "#{t[:token]} (#{t[:count]})") }.join
end

puts
puts "Rerun with --format json to hand this to a planning pass."
