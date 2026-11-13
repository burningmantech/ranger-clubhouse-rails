# frozen_string_literal: true

# Splits findings.json into one work list per plan package (see ../plan.md):
#   plan/<package>.tsv            DIVERGENT findings to fix
#   plan/<package>.ambiguous.tsv  "ambiguous <RULE>" findings, used only for rules the guide package makes firm
# Run from the repo root: mise exec -- ruby docs/design-audit/tools/plan_slices.rb

require "json"

ROOT = File.expand_path("..", __dir__)
# The audit's own grouping, read from classify.rb so the two cannot drift.
eval(File.read(File.join(__dir__, "classify.rb"))[/^GROUP_PATHS = \{.*?^\}\.freeze/m]) # rubocop:disable Security/Eval

SHARED = {
  "shared-forms" => %w[app/helpers/form_helper.rb app/assets/stylesheets/components/forms.css app/javascript/controllers/form_controller.js],
  "shared-css" => %w[app/assets/],
  "shared-js" => %w[app/javascript/],
  "shared-helpers" => %w[app/helpers/]
}.freeze

# Rule (or path) -> the ruling in plan.md an agent must read before acting on the finding.
RULING_BY_RULE = {
  "RADIUS-01" => "R2", "CARD-01" => "R2", "COLOR-01" => "R2", "COLOR-06" => "R2", "COLOR-07" => "R2", "FORM-07" => "R2",
  "FORM-03" => "R3/R13", "TYPE-03" => "R4", "TYPE-02" => "R4", "MODAL-02" => "R5/R8", "EMPTY-02" => "R6/R14", "BTN-04" => "R7",
  "NAV-02" => "R15"
}.freeze
SIGN_IN = %r{app/views/(?:sessions|sso)/|login\.css}
OUTSIDE_SHELL = %r{\Aapp/views/(?:bookmarks|test_harness)/|\Apublic/|print_sheet|signup_sheet|trainers_report|info_sheet|apparel\.html|roc_photo_board}

def package_of(file)
  group = GROUP_PATHS.find { |_, prefixes| prefixes.any? { |p| file.start_with?(p) } }&.first || "helpers-shared"
  return group unless group == "helpers-shared"

  SHARED.find { |_, prefixes| prefixes.any? { |p| file.start_with?(p) } }&.first || "shared-helpers"
end

def ruling_for(finding)
  return "R9" if finding["file"].match?(SIGN_IN)
  return "R10" if finding["file"].match?(OUTSIDE_SHELL)

  ruling = RULING_BY_RULE.fetch(finding["rule_id"], "-")
  # R2 is about the shared theme and helper defaults only; the same rule broken in a view is a real fix.
  ruling == "R2" && finding["file"].start_with?("app/views/") ? "-" : ruling
end

findings = File.readlines(File.join(ROOT, "findings.json")).filter_map { |l| JSON.parse(l.strip.delete_suffix(",")) if l.lstrip.start_with?("{") }
out = File.join(ROOT, "plan")
Dir.mkdir(out) unless Dir.exist?(out)

# Vague rules whose approved wording (plan/vague-rules.md) leaves cases to fix. Their "ambiguous" findings join the
# work list with ruling "V": the agent judges each against the new wording.
TO_JUDGE = %w[BTN-07 EMPTY-01 ALERT-01 EMPTY-02 LAYOUT-02 HERO-04 FORM-07 FORM-06 HERO-02 SPACE-01 BTN-05 TYPE-03 COLOR-06
              CARD-03 ICON-04 DISC-01 BTN-02 BADGE-01 SPACE-02 LIST-01 COPY-04 COLOR-02 BTN-06 NAV-04 NAV-01 FORM-09 FORM-04
              COPY-02].freeze
ambiguous = ->(f) { f["classification"] == "UNCOVERED" && f["note"].to_s.start_with?("ambiguous") }
vague_rule = ->(f) { f["note"][/ambiguous ([A-Z0-9-]+)/, 1] }

{ "" => ->(f) { f["classification"] == "DIVERGENT" || (ambiguous.(f) && TO_JUDGE.include?(vague_rule.(f))) },
  ".ambiguous" => ambiguous }.each do |suffix, pick|
  findings.select(&pick).group_by { |f| package_of(f["file"]) }.sort.each do |package, list|
    rows = list.sort_by { |f| [f["file"], f["line"].to_i] }.map do |f|
      rule = f["rule_id"] || vague_rule.(f)
      ruling = ruling_for(f.merge("rule_id" => rule))
      ruling = "V" if ambiguous.(f) && !%w[R9 R10].include?(ruling) # sign-in and outside-shell exemptions outrank
      [f["id"], f["severity"] || "-", rule, ruling, f["file"], f["line"], f["pattern"], f["note"].to_s.tr("\t\n", "  ")].join("\t")
    end
    File.write(File.join(out, "#{package}#{suffix}.tsv"), "id\tseverity\trule\truling\tfile\tline\tpattern\tnote\n#{rows.join("\n")}\n")
    next unless suffix.empty?

    sev = list.group_by { |f| f["severity"] }.transform_values(&:size)
    puts format("%-22s %4d findings  %3d files  high %2d  medium %3d  low %3d", package, list.size, list.map { |f| f["file"] }.uniq.size,
                sev["high"].to_i, sev["medium"].to_i, sev["low"].to_i)
  end
end
