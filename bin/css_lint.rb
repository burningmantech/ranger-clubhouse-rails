#!/usr/bin/env ruby
# frozen_string_literal: true

# css_lint.rb — a ratchet on the CSS numbers bin/css_census.rb measures.
#
# No gems, no Rails boot. Run from the Rails root:
#
#   ruby bin/css_lint.rb                    # compare to the baseline, warn only
#   ruby bin/css_lint.rb --strict           # ...and exit non-zero on any regression
#   ruby bin/css_lint.rb --update-baseline  # record the current numbers as the new ceiling
#
# The point is a ratchet, not a wall. The codebase is not at zero on most of
# these and never will be -- some inline styles are genuinely dynamic, some
# palette colours are deliberate. So the recorded numbers are the ceiling: they
# may fall, and lowering them is a commit anyone can make with
# --update-baseline. They may not rise.
#
# One rule ignores the ratchet and the --strict flag both: a class name built by
# interpolation is invisible to Tailwind's scanner, so the utility is never
# compiled and the element silently renders unstyled. That is a bug the moment
# it is written, so it always exits non-zero.
#
# See docs/css-dry-rules.md for the rules these numbers stand in for, and run
# /css:census to regenerate the full report.

require "json"
require "optparse"

ROOT = File.expand_path("..", __dir__)
CENSUS = File.join(ROOT, "bin", "css_census.rb")
DEFAULT_BASELINE = File.join(ROOT, ".css-baseline.json")

# Always fatal, whatever the baseline says.
HARD_FAIL = {
  "unscannable_class_names" => {
    key: "unscannable",
    why: "a class name built by interpolation is never compiled -- the element renders unstyled",
    fix: "use a literal lookup: STATUS_CLASS = { active: \"badge-success\" }.freeze"
  }
}.freeze

# Ratcheted: may fall, may not rise.
RATCHET = {
  "hardcoded_palette_tokens" => {
    key: "hardcoded_palette",
    why: "a palette colour in a view cannot be re-themed",
    fix: "use a semantic token: bg-base-100, text-error, bg-warning/10, border-line"
  },
  "important_tokens" => {
    key: "important",
    why: "an !important utility means a caller is fighting an abstraction",
    fix: "give the helper the parameter its caller wanted"
  },
  "inline_style_attributes" => {
    key: "inline_styles",
    why: "inline style= is not themeable and not scannable",
    fix: "use a utility, or a CSS custom property for a genuinely dynamic number"
  },
  "arbitrary_value_tokens" => {
    key: "arbitrary_values",
    why: "an arbitrary value is usually a pixel that should be a scale step",
    fix: "use a scale step or a theme token, or record why the value is exact"
  },
  "duplicate_clusters" => { key: nil, why: "duplicate class strings are drifting apart", fix: "extract on the third occurrence -- partial, helper, or @utility" },
  "redundant_tokens" => { key: nil, why: "repeated class tokens across duplicate clusters", fix: "see docs/css-dry-rules.md for which rung of the ladder applies" }
}.freeze

opts = { baseline: DEFAULT_BASELINE, strict: false, update: false }
OptionParser.new do |o|
  o.banner = "Usage: ruby bin/css_lint.rb [options]"
  o.on("--strict", "Exit non-zero on any regression, not just on hard failures") { opts[:strict] = true }
  o.on("--update-baseline", "Record the current numbers as the new ceiling") { opts[:update] = true }
  o.on("--baseline PATH", "Baseline file (default: .css-baseline.json)") { |v| opts[:baseline] = v }
  o.on("-h", "--help") { puts o; exit 0 }
end.parse!(ARGV)

unless File.exist?(CENSUS)
  warn "css_lint: bin/css_census.rb is missing -- the numbers come from it."
  exit 1
end

# --- run the census over the same roots the baseline was recorded with -------

roots = if File.exist?(opts[:baseline])
          JSON.parse(File.read(opts[:baseline])).fetch("roots", ["app/views"])
        else
          ["app/views"]
        end

args = ["--format", "json", "--min", "2", "--top", "200", "--roots", roots.join(",")]
json = IO.popen([RbConfig.ruby, CENSUS, *args], &:read)
unless $?.success?
  warn "css_lint: css_census.rb failed"
  exit 1
end
census = JSON.parse(json)
summary = census.fetch("summary")

# --- update mode ------------------------------------------------------------

if opts[:update]
  thresholds = (HARD_FAIL.keys + RATCHET.keys).to_h { |m| [m, summary.fetch(m, 0)] }
  File.write(opts[:baseline], JSON.pretty_generate(
    "_comment" => "Ceiling for bin/css_lint.rb. These may fall, never rise. Regenerate with: ruby bin/css_lint.rb --update-baseline",
    "recorded_at" => Time.now.strftime("%Y-%m-%d"),
    "roots" => roots,
    "thresholds" => thresholds
  ) + "\n")
  puts "css_lint: baseline written to #{opts[:baseline].sub(ROOT + '/', '')}"
  thresholds.each { |m, v| puts format("  %-28s %d", m, v) }
  exit 0
end

unless File.exist?(opts[:baseline])
  warn "css_lint: no baseline at #{opts[:baseline]}. Record one with: ruby bin/css_lint.rb --update-baseline"
  exit 1
end

baseline = JSON.parse(File.read(opts[:baseline])).fetch("thresholds")

# --- compare ----------------------------------------------------------------

def sites_for(census, key, limit = 8)
  return [] if key.nil?

  (census[key] || []).flat_map { |e|
    e["sites"] || ["#{e['file']}:#{e['line']}"]
  }.first(limit)
end

hard = []
regressions = []
improvements = []

(HARD_FAIL.merge(RATCHET)).each do |metric, meta|
  now = summary.fetch(metric, 0)
  was = baseline.fetch(metric, 0)
  entry = { metric: metric, now: now, was: was, meta: meta }

  if HARD_FAIL.key?(metric) && now.positive?
    hard << entry
  elsif now > was
    regressions << entry
  elsif now < was
    improvements << entry
  end
end

def report(entry, census, label)
  m = entry[:meta]
  puts "  #{label} #{entry[:metric]}: #{entry[:now]} (ceiling #{entry[:was]})"
  puts "      why: #{m[:why]}"
  puts "      fix: #{m[:fix]}"
  sites = sites_for(census, m[:key])
  sites.each { |s| puts "      at:  #{s}" }
  puts "      at:  …" if sites.size >= 8
end

puts "css_lint: #{roots.join(', ')}"

hard.each { |e| report(e, census, "FAIL") }
regressions.each { |e| report(e, census, opts[:strict] ? "FAIL" : "WARN") }

unless improvements.empty?
  puts "  below the ceiling -- lower it with: ruby bin/css_lint.rb --update-baseline"
  improvements.each { |e| puts format("      %-28s %d (ceiling %d)", e[:metric], e[:now], e[:was]) }
end

if hard.empty? && regressions.empty?
  puts "  ok -- nothing above the recorded ceiling"
  exit 0
end

# An interpolated class name is a bug now, so it fails whatever the mode.
exit 1 if hard.any?
exit(opts[:strict] ? 1 : 0)
