# frozen_string_literal: true

# Font Awesome ships every icon it has: 7.1.0's combined stylesheet declares
# 2,529 of them, and this application draws on a few hundred. The rest is dead
# weight in the CSS bundle that every page downloads.
#
# This task rewrites the vendored stylesheet into a subset containing only the
# icons the codebase actually names. It is regenerated, never hand-edited, so a
# Font Awesome upgrade is: drop in the new all.css, rerun the task.
#
#   bin/rails fontawesome:subset
#
# An upgrade also drops the new fonts into app/assets/webfonts and rebuilds
# lib/fontawesome/regular-icons.txt, the names the regular font has a glyph for,
# which IconHelper checks every regular icon against. That is a Node script, not
# part of this task, so every Rake task still runs without Node:
#
#   node bin/fontawesome_regular_icons.js
#
# Safety net: an icon whose name this scan cannot see would draw a blank gap
# where its glyph should be. IconHelper#fa_icon therefore raises in development
# and test when asked for any name the subset does not carry, Font Awesome Free
# or not, which turns a silent missing glyph into a failure on the first page
# that hits it.
#
# The scan skips app/javascript/vendor/, which holds third-party JavaScript,
# and app/assets/builds/, where a bundle built later would land. A bundle's
# ordinary words match icon names (a regex flag "g", an event "paste", a
# language "python"), so reading one would put icons into the subset that no
# page draws, and every upgrade of it would move the subset. The skip assumes
# no bundle in either folder draws a Font Awesome icon. One that did would
# lose its icons without a sound: fa_icon's check never sees a class written
# in JavaScript, and IconHelperTest's scan skips the same folders. So such a
# bundle's icon names have to be written in the app's own code.
namespace :fontawesome do
  # The complete stylesheet lives outside app/assets so Propshaft does not
  # publish 110KB that no page ever asks for. It is the input to this task.
  SOURCE = Rails.root.join("lib/fontawesome/fontawesome-7.1.0-all.css")
  SUBSET = Rails.root.join("app/assets/stylesheets/fontawesome-subset.css")

  # Every icon in Font Awesome 7 is declared as a single-selector block holding
  # one custom property: `.fa-house { --fa: "\f015"; }`
  # IconHelper::ICON_BLOCK is its twin. Never name that here: every .rake file is
  # loaded before :environment sets up autoloading, so an IconHelper constant at
  # this level raises NameError on every Rake task, db:migrate included.
  ICON_BLOCK = /^\.fa-([a-z0-9-]+)\s*\{\s*--fa:\s*"[^"]*";\s*\}\n?/

  # Where an icon name can be written. Names reach fa_icon as string or symbol
  # literals — passed directly, held in constant maps, or chosen by a ternary —
  # so every literal in the application is a candidate, and the intersection
  # with the real icon list does the filtering.
  SCANNED = %w[
    app/**/*.rb app/**/*.erb app/**/*.js
    lib/**/*.rb config/**/*.rb
  ].freeze

  LITERAL = /
    (?:"([a-z0-9_-]+)")   # "circle-check"
    |(?:'([a-z0-9_-]+)')  # 'circle-check'
    |(?::([a-z0-9_]+))    # :circle_check
    |(?:\bfa-([a-z0-9-]+))
  /x

  desc "Rewrite the Font Awesome stylesheet as a subset of the icons this codebase uses"
  task subset: :environment do
    css = SOURCE.read
    available = css.scan(ICON_BLOCK).flatten.to_set

    referenced = Set.new
    SCANNED.each do |pattern|
      Dir.glob(Rails.root.join(pattern)).each do |path|
        next if path.include?("/assets/stylesheets/")
        # Third-party JavaScript: its ordinary words match icon names, and no
        # bundle there writes an fa- class. ICON_SCAN_EXCLUDED in
        # test/helpers/icon_helper_test.rb is this list's twin, kept twice
        # because Rake never loads a test class: change the two together.
        next if %w[app/javascript/vendor/ app/assets/builds/].any? { |dir| path.include?("/#{dir}") }

        File.read(path).scan(LITERAL) do |match|
          name = match.compact.first
          # fa_icon(:chevron_down) and fa_icon("chevron-down") name one icon.
          referenced << name.tr("_", "-")
        end
      end
    end

    kept = available & referenced
    subset = css.gsub(ICON_BLOCK) { kept.include?(Regexp.last_match(1)) ? Regexp.last_match(0) : "" }

    SUBSET.write(<<~HEADER + subset)
      /*
       * GENERATED — do not edit. Run `bin/rails fontawesome:subset` to rebuild.
       *
       * A subset of fontawesome-7.1.0-all.css carrying #{kept.size} of its
       * #{available.size} icons: the ones named anywhere in this codebase.
       */
    HEADER

    saved = SOURCE.size - SUBSET.size
    puts "Kept #{kept.size} of #{available.size} icons."
    puts "#{SUBSET.relative_path_from(Rails.root)}: #{SUBSET.size} bytes " \
         "(#{saved} smaller, #{(100.0 * saved / SOURCE.size).round(1)}%)"
  end
end
