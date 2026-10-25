# frozen_string_literal: true

require "test_helper"

class IconHelperTest < ActionView::TestCase
  # Where the code writes an icon name as a literal: fa_icon's or
  # ui_icon_item's first argument, an icon: or empty_icon: value, and the
  # name: of a { name:, style: } map (DashboardHelper::STEP_ICONS,
  # AgreementHelper::ICONS). A name holds no space and no interpolation.
  ICON_LITERAL = /(?:"([^"\s#]+)"|'([^'\s#]+)'|:([a-z0-9_]+)\b)/
  ICON_POSITIONS = [
    /\b(?:fa_icon|ui_icon_item)\b[\s(]*#{ICON_LITERAL}/,
    /\b(?:icon|empty_icon):\s*#{ICON_LITERAL}/,
    /\{\s*name:\s*#{ICON_LITERAL},\s*style:/
  ].freeze
  # An fa- class in a class string, in Ruby, ERB or JS.
  ICON_CLASS = /(?<![\w-])fa-([a-z0-9-]+)/
  ICON_SCAN_GLOBS = %w[app/**/*.{rb,erb,js,yml} config/**/*.{rb,erb,js,yml}].freeze
  ICON_SCAN_EXCLUDED = %w[app/javascript/vendor/ app/assets/builds/].freeze
  # A regular icon written by hand, as fa_icon would write it: fa-regular fa-sun.
  REGULAR_ICON_CLASS = /(?<![\w-])fa-regular\s+fa-([a-z0-9-]+)/
  # The font the regular icon list is read out of; the catalog is the other source.
  REGULAR_FONT_PATH = "app/assets/webfonts/fa-regular-400.woff2"

  # An icon is aria-hidden, so one that carries meaning on its own has to say
  # it twice: as a title for a pointer and in words for a screen reader.
  test "label: gives the icon a title and a screen-reader sentence after it" do
    render inline: <<~ERB
      <div><%= fa_icon "ban", :solid, class: "icon-warning", label: "Not on site" %>Hubcap</div>
    ERB

    assert_select "div > i.fa-solid.fa-ban.icon-warning[aria-hidden='true'][title='Not on site']", count: 1
    assert_select "div > i + span.sr-only", text: "Not on site.", count: 1
    # The option is consumed, not passed through as an attribute.
    assert_select "i[label]", count: 0
  end

  test "label: keeps the punctuation a label already ends with" do
    render inline: <<~ERB
      <%= fa_icon "pen", :solid, label: "Changed, not yet saved." %>
    ERB

    assert_select "i[title='Changed, not yet saved.']", count: 1
    assert_select "span.sr-only", text: "Changed, not yet saved.", count: 1
  end

  test "an explicit title: wins over the label for the tooltip" do
    render inline: <<~ERB
      <%= fa_icon "bell", :solid, title: "Spam", label: "Marked as spam" %>
    ERB

    assert_select "i[title='Spam']", count: 1
    assert_select "span.sr-only", text: "Marked as spam.", count: 1
  end

  test "an icon without a label stays a bare decoration" do
    render inline: <<~ERB
      <%= fa_icon "ban", :solid %>
    ERB

    assert_select "i.fa-ban[aria-hidden='true']", count: 1
    assert_select "i[title]", count: 0
    assert_select "span.sr-only", count: 0
  end

  # A Pro name, or a misspelt one, draws a blank gap where the icon should be.
  test "a name that is not a Font Awesome Free icon raises" do
    error = assert_raises(ArgumentError) { fa_icon "arrow-up-right", :solid }

    assert_match "fa-arrow-up-right is not an icon in Font Awesome Free 7.1.0", error.message
  end

  # .fa-spin is declared in the catalog, but holds no glyph.
  test "a utility class is not an icon" do
    error = assert_raises(ArgumentError) { fa_icon "spin" }

    assert_match "Font Awesome Free 7.1.0", error.message
  end

  test "a catalog icon the subset lacks still asks for the subset to be rerun" do
    name = (IconHelper.catalog_icons - IconHelper.subset_icons).min

    error = assert_raises(ArgumentError) { fa_icon name, :solid }

    assert_match "the generated subset does not carry it", error.message
  end

  # Options written before the style land in it, and the icon draws nothing.
  test "a style other than regular, solid or brands raises" do
    error = assert_raises(ArgumentError) { fa_icon "ban", end: 2 }
    assert_match "options go after it", error.message
    assert_match "{end: 2}", error.message

    error = assert_raises(ArgumentError) { fa_icon "ban", :light }
    assert_match ":light", error.message
  end

  test "regular, solid and brands pass as a symbol or a string" do
    assert_nothing_raised do
      fa_icon "circle-check"
      fa_icon "ban", :solid
      fa_icon "ban", "solid"
      fa_icon "circle-check", :regular
      # Only the regular style's glyphs are checked. Solid and brands coverage
      # deliberately is not, so meta, a brand only, passes as one.
      fa_icon "meta", :brands
    end
  end

  # Font Awesome Free's regular font has no magnifying-glass. Asked for in
  # regular, by default or by name, it would draw a crossed box.
  test "a regular icon the regular font has no glyph for raises" do
    [[], [:regular], ["regular"]].each do |style|
      error = assert_raises(ArgumentError) { fa_icon "magnifying-glass", *style }
      assert_match "fa-magnifying-glass has no glyph in Font Awesome Free's regular style", error.message
      assert_match 'fa_icon "magnifying-glass", :solid', error.message
    end

    assert_nothing_raised do
      fa_icon "envelope"
      fa_icon "magnifying-glass", :solid
    end
  end

  test "a missing regular icon list skips the regular check" do
    saved = IconHelper.regular_icons
    IconHelper.instance_variable_set(:@regular_icons, nil)

    assert_nothing_raised { fa_icon "magnifying-glass" }
  ensure
    IconHelper.instance_variable_set(:@regular_icons, saved)
  end

  test "production runs no check" do
    with_rails_env("production") do
      assert_nothing_raised do
        fa_icon "arrow-up-right", :solid
        fa_icon "ban", end: 2
        fa_icon "magnifying-glass"
      end
    end
  end

  # The list is read out of the regular font for the catalog's names, so a new
  # copy of either one leaves it stale.
  test "the regular icon list was generated from the vendored font and catalog" do
    header = regular_icon_list.take_while { |line| line.start_with?("#") }.join("\n")

    [REGULAR_FONT_PATH, IconHelper::CATALOG_PATH].each do |path|
      digest = Digest::SHA256.file(Rails.root.join(path)).hexdigest
      assert_match(/^#.* #{Regexp.escape(path)} sha256 #{digest}$/, header,
                   "#{IconHelper::REGULAR_ICONS_PATH} was not generated from this #{path}. " \
                   "Rerun `node bin/fontawesome_regular_icons.js`")
    end
  end

  test "the regular icon list is catalog names, sorted, each once" do
    names = regular_icon_list.reject { |line| line.start_with?("#") }

    assert_not_empty names
    assert_equal names.sort, names, "#{IconHelper::REGULAR_ICONS_PATH} is not sorted"
    assert_equal names.uniq, names, "#{IconHelper::REGULAR_ICONS_PATH} names an icon twice"
    assert_empty names - IconHelper.catalog_icons.to_a, "Not icons in Font Awesome Free 7.1.0"
  end

  # fa_icon's own check sees only a name some test renders; hour-glass, on a
  # badge no test draws, shipped past it. This reads the names where the code
  # writes them. It can't see one chosen in a branch or a map without one of
  # these keys: fa_icon's check catches those once rendered.
  test "every icon name written in app/ and config/ is a Font Awesome Free 7.1 icon" do
    catalog = Rails.root.join(IconHelper::CATALOG_PATH).read
    # A class string may hold a utility as well as an icon: fa-solid, fa-fw.
    selectors = catalog.scan(/\.fa-([a-z0-9-]+)/).flatten.to_set
    # Stat boxes pass a tint, not a name, under icon:.
    stat_classes = (UiComponents::UiStatBoxHelper::STAT_VARIANTS.values +
                    UiComponents::UiStatBoxHelper::STAT_SIZES.values).pluck(:icon)

    missing = icon_scan_files.flat_map do |path|
      source = File.read(path)
      names = ICON_POSITIONS.flat_map { |pattern| literal_matches(source, pattern) }
                            .map { |line, name| [line, name.tr("_", "-")] }
                            .reject { |_, name| IconHelper.catalog_icons.include?(name) || stat_classes.include?(name) }
      classes = literal_matches(source, ICON_CLASS).reject { |_, name| selectors.include?(name) }
      (names + classes).sort.map { |line, name| "#{Pathname(path).relative_path_from(Rails.root)}:#{line} #{name}" }
    end

    assert_empty missing, "Not icons in Font Awesome Free 7.1.0:\n#{missing.join("\n")}"
  end

  # fa_icon's regular check never sees a class written by hand, in ERB or in a
  # Stimulus controller. This reads them where the code writes them.
  test "every fa-regular class written in app/ and config/ names an icon the regular font draws" do
    missing = icon_scan_files.flat_map do |path|
      literal_matches(File.read(path), REGULAR_ICON_CLASS)
        .reject { |_, name| IconHelper.regular_icons.include?(name) }
        .map { |line, name| "#{Pathname(path).relative_path_from(Rails.root)}:#{line} #{name}" }
    end

    assert_empty missing, "No glyph in Font Awesome Free's regular style, so each draws a crossed box. " \
                          "Write fa-solid, or choose a name from #{IconHelper::REGULAR_ICONS_PATH}:\n" \
                          "#{missing.join("\n")}"
  end

  private

  def regular_icon_list
    Rails.root.join(IconHelper::REGULAR_ICONS_PATH).readlines(chomp: true)
  end

  def icon_scan_files
    ICON_SCAN_GLOBS.flat_map { |glob| Dir.glob(Rails.root.join(glob)) }
                   .reject { |path| ICON_SCAN_EXCLUDED.any? { |dir| path.include?("/#{dir}") } }
  end

  # [line, name] for each match, the name being its one captured group.
  def literal_matches(source, pattern)
    source.to_enum(:scan, pattern).map do
      match = Regexp.last_match
      [source[0, match.begin(0)].count("\n") + 1, match.captures.compact.first]
    end
  end

  # Rails.env is process-wide, and the suite runs one test at a time.
  def with_rails_env(name)
    saved = Rails.env
    Rails.env = name
    yield
  ensure
    Rails.env = saved
  end
end
