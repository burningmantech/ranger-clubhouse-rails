# frozen_string_literal: true

module IconHelper
  # The stylesheet ships only the icons this codebase was found to name (see
  # `bin/rails fontawesome:subset`). A name outside that set draws no glyph,
  # only a blank 1.25em gap where the icon should be, and the browser says
  # nothing. So development and test check every name against both the shipped
  # subset and the complete Font Awesome catalog it was cut from, and raise on
  # a name either one lacks. Production runs no check.
  #
  # The two ways a name can be missing are not the same failure, and the error
  # says which it is:
  #
  #   In the catalog but not the subset — the scan missed a name the code really
  #   uses. Rerunning the subset task fixes it.
  #
  #   In neither — the name is not a Font Awesome Free 7.1 icon at all: a
  #   misspelling, or a Pro icon. No subset would ever draw it.
  #
  # The style is checked too, also in development and test only. It is
  # positional, so options written before it (fa_icon "ban", end: 2) land in
  # it, the icon gets no style class, and it draws nothing at all. Anything but
  # regular, solid or brands raises.
  #
  # The third check is the regular style's own glyphs. Font Awesome Free's
  # regular font draws only a small part of the catalog; for any other name the
  # browser falls back past the icon font and draws a crossed box, the subset
  # carrying the name or not. So a regular icon, asked for by default or by
  # name, raises unless it is on REGULAR_ICONS_PATH, the list
  # `node bin/fontawesome_regular_icons.js` reads out of the font. Solid and
  # brands coverage is not checked: solid draws nearly every name, and the
  # brand-only names the subset carries are words its scan picked up.
  SUBSET_PATH = "app/assets/stylesheets/fontawesome-subset.css"
  CATALOG_PATH = "lib/fontawesome/fontawesome-7.1.0-all.css"
  REGULAR_ICONS_PATH = "lib/fontawesome/regular-icons.txt"
  FREE_STYLES = %w[regular solid brands].freeze

  # Every icon is a single-selector block holding one custom property,
  # `.fa-house { --fa: "\f015"; }`. The catalog's utility classes (.fa-spin,
  # .fa-2x, .fa-solid) are declared too, but hold no --fa, so they are no icon.
  # fontawesome.rake keeps its own copy: Rake loads every .rake file before
  # autoloading is set up, so naming this one at its namespace level would
  # break every task.
  ICON_BLOCK = /^\.fa-([a-z0-9-]+)\s*\{\s*--fa:\s*"[^"]*";\s*\}/

  # start:/end: margins as whole class names, so Tailwind can read each one.
  ICON_START_MARGINS = { 1 => "ms-1", 2 => "ms-2" }.freeze
  ICON_END_MARGINS = { 1 => "me-1", 2 => "me-2" }.freeze

  def self.icon_names(path)
    file = Rails.root.join(path)
    file.exist? ? file.read.scan(ICON_BLOCK).flatten.to_set : nil
  end

  def self.subset_icons
    return @subset_icons if defined?(@subset_icons)

    @subset_icons = icon_names(SUBSET_PATH)
  end

  def self.catalog_icons
    return @catalog_icons if defined?(@catalog_icons)

    @catalog_icons = icon_names(CATALOG_PATH)
  end

  # One bare name per line, under a # header.
  def self.regular_icons
    return @regular_icons if defined?(@regular_icons)

    file = Rails.root.join(REGULAR_ICONS_PATH)
    @regular_icons = file.exist? ? file.readlines(chomp: true).grep_v(/\A#/).compact_blank.to_set : nil
  end

  # label: is for an icon that says something on its own -- a mark in a table
  # row with no words beside it. aria-hidden rides on every icon, so the meaning
  # is given twice: as a title for a pointer, and as a screen-reader-only
  # sentence straight after the icon. Leave it off an icon that only decorates
  # the words next to it.
  def fa_icon(name, style = nil, html_options = {}, text = nil)
    style = "regular" if style.nil?

    # Callers write both fa_icon(:chevron_down) and fa_icon("chevron-down").
    # Font Awesome only knows the hyphenated form, and an underscore silently
    # produced a class that matched no icon.
    name = name.to_s.tr("_", "-")
    if Rails.env.local?
      verify_icon_style!(name, style)
      verify_icon_available!(name)
      verify_regular_glyph!(name, style)
    end

    html_options[:class] = "fa-#{style} fa-#{name} #{html_options[:class]}"
    html_options["aria-hidden"] ||= true

    start_margin = html_options.delete(:start)
    if start_margin
      html_options[:class] += " #{ICON_START_MARGINS.fetch(start_margin)}"
    end

    end_margin = html_options.delete(:end)
    if end_margin
      html_options[:class] += " #{ICON_END_MARGINS.fetch(end_margin)}"
    end

    if (size = html_options.delete(:size))
      html_options[:class] += " fa-#{size}"
    end

    if html_options.delete(:fixed)
      html_options[:class] += " fa-fw"
    end

    label = html_options.delete(:label).presence&.to_s
    html_options[:title] ||= label if label

    context = @template || self
    html = context.content_tag(:i, "", html_options)
    html << context.content_tag(:span, icon_label_sentence(label), class: "sr-only") if label
    html << text.to_s if text.present?
    html
  end

  private

  # The label as a sentence. The full stop is what makes a screen reader pause
  # before whatever follows the icon, so "Not on site" does not run into the
  # callsign after it.
  def icon_label_sentence(label)
    label.match?(/[.!?]\z/) ? label : "#{label}."
  end

  # A Hash here is the caller's options, written where the style goes.
  def verify_icon_style!(name, style)
    return if FREE_STYLES.include?(style.to_s)

    raise ArgumentError,
          "fa_icon \"#{name}\" got #{style.inspect} as its style, which is not regular, solid or brands. " \
          "The style is the second argument and options go after it: fa_icon \"ban\", :solid, end: 2"
  end

  def verify_icon_available!(name)
    subset = IconHelper.subset_icons
    return if subset.nil? || name.blank? || subset.include?(name)

    catalog = IconHelper.catalog_icons
    if catalog.nil? || catalog.include?(name)
      raise ArgumentError,
            "fa-#{name} is a Font Awesome icon, but the generated subset does not carry it, " \
            "so it would render as nothing. Rerun `bin/rails fontawesome:subset`."
    end

    raise ArgumentError,
          "fa-#{name} is not an icon in Font Awesome Free 7.1.0: neither the generated subset nor the " \
          "full stylesheet it was cut from defines it. Check the spelling, and that it is not a Pro icon."
  end

  # The default arrives as "regular" and a caller's as :regular, so both count.
  def verify_regular_glyph!(name, style)
    regular = IconHelper.regular_icons
    return if style.to_s != "regular" || regular.nil? || name.blank? || regular.include?(name)

    raise ArgumentError,
          "fa-#{name} has no glyph in Font Awesome Free's regular style, so it would draw a crossed box. " \
          "Pass :solid (fa_icon \"#{name}\", :solid), or choose a name from #{REGULAR_ICONS_PATH}."
  end
end
