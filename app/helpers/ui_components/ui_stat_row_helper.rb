# frozen_string_literal: true

module UiComponents
  # Stat Row Helper
  # The wrapper a page's summary metrics sit in: a wrapping row of ui_stat_box
  # tiles, tightened one gap step below lg so a phone fits more than one tile
  # per line.
  #
  # Usage:
  #   <%= ui_stat_row do %>
  #     <%= ui_stat_box @people.size.to_s, "People" %>
  #     <%= ui_stat_box @flagged.to_s, "Flagged", variant: :warning %>
  #   <% end %>
  #
  module UiStatRowHelper
    include ActionView::Helpers::TagHelper
    include ActionView::Context

    ROW_CLASSES = "flex flex-row flex-wrap gap-2 lg:gap-4 my-4"

    # Renders the container for a row of stat boxes.
    #
    # @param options [Hash] Additional HTML options
    #   - :class - Additional CSS classes
    #
    def ui_stat_row(**options, &block)
      options[:class] = [ROW_CLASSES, options[:class]].compact.join(" ")
      content_tag(:div, options, &block)
    end
  end
end
