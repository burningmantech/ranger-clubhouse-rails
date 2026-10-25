# frozen_string_literal: true

module ShirtHelper
  # The one place shirt types are named. Both the person swag page and the
  # quartermaster catalog read this so the same shirt reads the same everywhere.
  SHIRT_TYPE_LABELS = {
    Swag::SHIRT_T_SHIRT => "T-Shirt",
    Swag::SHIRT_LONG_SLEEVE => "Long Sleeve Shirt"
  }.freeze

  # A shirt size for display. A missing size is flagged with an icon as well as
  # colour, so it still reads as a gap in grayscale.
  def shirt_size_title(title)
    return title unless title == ShirtTotals::UNKNOWN

    tag.span(safe_join([fa_icon("circle-question", :solid, class: "icon-warning"), title], " "),
             class: "inline-flex items-center gap-2 text-warning")
  end

  # The same, read off a person's shirt of the given kind.
  def shirt_size_label(person, reader)
    shirt_size_title(ShirtTotals.title_for(person, reader))
  end

  def shirt_select_options(shirts, include_none = true)
    {
      tshirt_options: shirt_build_options(shirts, Swag::SHIRT_T_SHIRT, include_none),
      long_sleeve_options: shirt_build_options(shirts, Swag::SHIRT_LONG_SLEEVE, include_none)
    }
  end

  def shirt_build_options(shirts, shirt_type, include_none = false)
    options = shirts.select do |shirt|
      shirt.active && shirt.type == Swag::TYPE_DEPT_SHIRT && shirt.shirt_type == shirt_type
    end.map do |shirt|
      [shirt.title, shirt.id]
    end

    options.unshift(["Not Selected", ""]) if include_none
    options
  end
end
