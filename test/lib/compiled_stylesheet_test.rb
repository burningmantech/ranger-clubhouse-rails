# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"
require "tailwindcss/ruby"
require Rails.root.join("lib/css_matchers")

# Three rules of docs/css-dry-rules.md -- no palette colour (rung 2), no
# arbitrary value (hard rule 4), no !important (hard rule 5) -- asked of the
# stylesheet itself.
#
# bin/css_lint.rb counts them by reading source, and a pattern cannot read every
# place a class name gets written: a lone token in a hash
# (`row: "!bg-error/10"`), a string with a quote or an interpolation in it.
# However a utility class was spelled on its way to Tailwind, its rule is in the
# build, so that is where the lists are held.
#
# Each list is exact. A line says why its class is allowed, or that no reason is
# on record. A class that is not listed fails by name; so does a line whose
# class is gone, which keeps the lists from outliving their reasons.
#
# What this cannot see, and what it sees too much of:
# - Stylesheets. A value inside `@apply`, or an !important written as a
#   declaration, is CSS and never becomes a class.
# - Comments. Tailwind reads ERB, HTML and JavaScript comments as text; only
#   Ruby `#` comments are skipped. A class named in one compiles, so it counts
#   as a use: it keeps a listed class alive, and quoting an unlisted one fails.
# - Code. A Ruby bang method or a negation beside a word that is also a utility
#   or a daisyUI component (`rows.filter!`, `if !hidden`) compiles an important
#   class. That is not a class to list: name the token in the
#   `@source not inline(...)` line of app/assets/tailwind/application.css.
class CompiledStylesheetTest < ActiveSupport::TestCase
  PALETTE = {
    "bg-gray-800" => "profile_photos/crop: the surround of the crop canvas, one neutral in both themes",
    "bg-gray-500" => "profile_photos/crop: the canvas itself, for the same reason",
    "from-amber-100" => "UiProgressBoxHelper's badge gradient: raw palette on purpose (design-foundations)",
    "to-orange-100" => "the same gradient",
    "dark:from-amber-900/40" => "its dark twin",
    "dark:to-orange-900/40" => "its dark twin"
  }.freeze

  IMPORTANT = {
    "!bg-error/10" => "SeverityStyleHelper row tint: the odd:/even: stripe is :nth-child and outranks a plain background",
    "!bg-warning/10" => "SeverityStyleHelper, against the same stripe",
    "!bg-success/10" => "TableHelper::ROW_STATES, against the same stripe",
    "!bg-base-300" => "TableHelper::ROW_STATES, against the same stripe",
    "hidden!" => "toggle_controller.js: has to outweigh a display utility on the element it closes"
  }.freeze

  ARBITRARY = {
    "mt-[15vh]" => "search dialog: held near the top so the results can grow downward",
    "w-[calc(100%-2rem)]" => "search dialog: a 1rem gutter on each side of a phone screen",
    "lg:max-h-[70vh]" => "People Search and Salesforce Query results: headings and scrollbar stay on screen together",
    "lg:grid-cols-[1fr_auto_auto]" => "alerts/_alert_group: a grid template",
    "lg:grid-cols-[1fr_20rem]" => "vc/applications/show: a grid template, the body beside a 20rem rail",
    "grid-cols-[8rem_1fr]" => "person/certifications/show: a grid template, label and value",
    "before:content-['']" => "ClipboardHelper: the empty ::before that widens the copy control's press target",
    "max-w-[30ch]" => "ACTION_LOG_EVENT_MAX_WIDTH: a measure in characters",
    "min-h-[90vh]" => "test_harness/autocomplete_fixture: pushes a field to the foot of the viewport",
    "max-w-[90rem]" => "bookmarks/show: the page width, which --spacing-8xl also names",
    "h-[140px]" => "SidebarHelper's logo, no reason on record",
    "w-[140px]" => "SidebarHelper's logo, no reason on record",
    "max-w-[900px]" => "common/available_sign_ups/show, no reason on record",
    "shadow-[0_-4px_6px_-1px_rgba(0,0,0,0.1)]" => "ButtonHelper's sticky row, a raw shadow not yet a theme token",
    "dark:shadow-[0_-4px_6px_-1px_rgba(0,0,0,0.3)]" => "its dark twin"
  }.freeze

  test "every palette colour in the build is on the list" do
    assert_listed PALETTE, :palette?, "palette colour",
                  "It cannot follow the theme: use a semantic token (bg-base-100, text-error, border-line)."
  end

  test "every important in the build is on the list" do
    assert_listed IMPORTANT, :important?, "!important",
                  "If it is Ruby or JavaScript and not a class (a bang method such as rows.filter!, a negation " \
                  "such as !hidden), add it to the `@source not inline(...)` line in " \
                  "app/assets/tailwind/application.css. Otherwise a caller is fighting an abstraction: give the " \
                  "helper the option its caller wanted."
  end

  test "every arbitrary value in the build is on the list" do
    assert_listed ARBITRARY, :arbitrary?, "arbitrary value",
                  "It is usually a scale step or a theme token: use that."
  end

  # A build of its own. app/assets/builds/tailwind.css is only as fresh as the
  # last test:prepare or watcher run, and a stale one would pass a class that
  # has since been written or fail one that has since been removed.
  def self.compiled
    @compiled ||= Dir.mktmpdir do |dir|
      path = File.join(dir, "tailwind.css")
      output, status = Open3.capture2e(Tailwindcss::Ruby.executable, "-i", "app/assets/tailwind/application.css",
                                       "-o", path, "--minify", chdir: Rails.root.to_s)
      raise "tailwindcss failed (a fresh checkout needs `npm install` first):\n#{output}" unless status.success?

      CssMatchers.utility_classes(File.read(path))
    end
  end

  private

  def assert_listed(listed, rule, label, fix)
    compiled = self.class.compiled.select { |name| CssMatchers.public_send(rule, name) }.to_a
    unlisted = (compiled - listed.keys).sort
    stale = (listed.keys - compiled).sort

    # No closing period: Minitest adds one.
    assert_empty unlisted, "Compiled, but not on the #{label} list in #{self.class}: #{unlisted.join(", ")}. " \
                           "#{fix} If it is only quoted in an ERB, HTML or JavaScript comment, reword the " \
                           "comment. If the class is right as it is, add it to the list with its reason"
    assert_empty stale, "On the #{label} list in #{self.class}, but no longer compiled: #{stale.join(", ")}. " \
                        "Delete the line"
  end
end
