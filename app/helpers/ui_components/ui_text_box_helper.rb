# frozen_string_literal: true

module UiComponents
  # Text Box Helper
  # The bordered, tinted, padded box a message body, a preview or a rich-text
  # field sits in, so it reads as quoted content apart from the page around it.
  # With max_height: a tall body scrolls inside the box rather than pushing
  # the rest of the page down.
  #
  # A scrolling box is a keyboard stop: tabindex="0" so the arrow keys can
  # scroll it, role="region" and the label: as its accessible name, and the
  # focus ring. max_height: without label: raises.
  #
  # Usage:
  #   <%= ui_text_box do %>
  #     <%= @broadcast.sms_message %>
  #   <% end %>
  #
  #   <%= ui_text_box max_height: "max-h-64", label: "Announcement message",
  #                   class: "lexxy-content" do %>
  #     <%= rich_text(announcement.message) %>
  #   <% end %>
  #
  module UiTextBoxHelper
    include ActionView::Helpers::TagHelper
    include ActionView::Context

    BOX_CLASSES = "rounded-base border border-line bg-default p-3"
    SCROLL_CLASSES = "overflow-y-auto focus-visible:outline-none focus-visible:ring-2 " \
                     "focus-visible:ring-primary focus-visible:ring-offset-2"
    # A Tailwind max-height step, written whole at the call site so the scanner
    # sees it: max-h-48, max-h-64, max-h-96. Never an arbitrary value.
    MAX_HEIGHT_FORMAT = /\Amax-h-\d+\z/

    # Renders the box around the block.
    #
    # @param max_height [String, nil] a max-h-<n> class; the box scrolls past it
    # @param label [String, nil] the scrolling box's accessible name; required with max_height:
    # @param options [Hash] Additional HTML options
    #   - :class - Additional CSS classes
    #
    def ui_text_box(max_height: nil, label: nil, **options, &)
      scroll_classes = nil
      if max_height
        check_scroll_options(max_height, label)
        scroll_classes = [max_height, SCROLL_CLASSES]
        options[:tabindex] = 0
        options[:role] = "region"
        options[:aria] = (options[:aria] || {}).merge(label:)
      end
      options[:class] = class_names(BOX_CLASSES, scroll_classes, options[:class])
      content_tag(:div, options, &)
    end

    private

    def check_scroll_options(max_height, label)
      unless max_height.to_s.match?(MAX_HEIGHT_FORMAT)
        raise ArgumentError, "max_height: takes a Tailwind max-h-<n> class, got #{max_height.inspect}"
      end
      raise ArgumentError, "A scrolling ui_text_box needs label: for its accessible name" if label.blank?
    end
  end
end
