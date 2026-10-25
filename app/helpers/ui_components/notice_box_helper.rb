# frozen_string_literal: true

module UiComponents
  module NoticeBoxHelper
    include ActionView::Helpers::TagHelper

    BOX_TYPES = {
      success: { icon: "circle-check", type: :solid, box: "box-success", box_type: "box-accent-success" },
      info: { icon: "circle-info", type: :solid, box: "box-info", box_type: "box-accent-info" },
      warning: { icon: "triangle-exclamation", type: :solid, box: "box-warning", box_type: "box-accent-warning" },
      error: { icon: "triangle-exclamation", type: :solid, box: "box-error", box_type: "box-accent-error" },
      secondary: { icon: "hand-point-right", type: :solid, box: "box-secondary", box_type: "box-accent-secondary" }
    }.freeze

    def ui_callout_box(type, options = {}, &block)
      styling = BOX_TYPES[type] || BOX_TYPES[:info]
      accent = options.delete(:accent) == true
      title = options.delete(:title)
      # Defaults to h4 because most callouts sit inside a section (aria-level 2).
      # A callout at page level, directly under the h1, passes :h2 so the
      # document does not skip two levels to reach it.
      heading_tag = options.delete(:heading_level) || :h4

      # An unknown type keeps the plain, untinted box it has always had.
      box_class = accent ? "box-accent #{styling[:box_type]}" : "box #{BOX_TYPES.dig(type, :box)}"

      padding_class = "p-2"
      layout_class = accent ? "flex items-start gap-2" : "flex flex-row gap-2"

      options[:class] = "#{padding_class} mb-2 #{box_class} #{options[:class]} #{layout_class}".squish
      options[:role] ||= "alert"

      icon = options.delete(:icon)
      hide_icon = (icon == false)

      if icon
        icon_type = options.delete(:icon_type) || :solid
      else
        icon = styling[:icon]
        icon_type = styling[:type]
      end

      content_tag :div, options do
        icon_html = hide_icon ? "".html_safe : content_tag(:div, fa_icon(icon, icon_type), class: "text-lg")
        body_html = if title.present?
                      content_tag(:div) do
                        content_tag(heading_tag, title, class: "my-1 heading-title") +
                          content_tag(:div, capture(&block))
                      end
                    else
                      content_tag(:div, capture(&block))
                    end

        safe_join [icon_html, body_html]
      end
    end

    def ui_alert_banner(label, type, options = {}, &block)
      styling = BOX_TYPES[type] || BOX_TYPES[:success]
      options[:class] = "mb-4 box #{styling[:box_type]} #{options[:class]}".squish

      if %i[warning danger error].include?(type)
        options[:role] ||= "alert"
      else
        options[:role] ||= "region"
        options[:aria] ||= { label: }
      end

      content_tag :div, options do
        content_tag(:div, class: "text-lg px-2 py-1 font-bold flex items-center gap-2") do
          fa_icon(styling[:icon], styling[:type]) + label
        end + content_tag(:div, capture(&block), class: "text-base p-4 text-body bg-base-100 rounded-lg")
      end
    end

    # Empty State Helper
    # Renders a consistent "no items found" message with dashed border styling.
    #
    # @param message [String] The message to display (required unless block given)
    # @param options [Hash] Additional options
    # @option options [String] :class Additional CSS classes
    # @option options [Symbol] :icon Optional FontAwesome icon name
    # @option options [Symbol] :icon_type Icon style (:regular, :solid) - default: :regular.
    #   The regular style draws only the icons in lib/fontawesome/regular-icons.txt;
    #   pass :solid for any other. fa_icon raises in development and test.
    #
    # @example Basic usage
    #   <%= ui_empty_state "No items found." %>
    #
    # @example With icon
    #   <%= ui_empty_state "No messages yet.", icon: "envelope", icon_type: :regular %>
    #
    # @example With block
    #   <%= ui_empty_state do %>
    #     No upcoming shifts found. <%= link_to "Browse available shifts", available_shifts_path %>.
    #   <% end %>
    #
    def ui_empty_state(message = nil, options = {}, &block)
      icon_name = options.delete(:icon)
      icon_type = options.delete(:icon_type) || :regular

      options[:class] = "empty-state #{options[:class]}".squish
      options[:role] ||= "status"

      content_tag :div, options do
        parts = []
        parts << fa_icon(icon_name, icon_type, end: 2) if icon_name
        parts << (block_given? ? capture(&block) : message)
        safe_join(parts)
      end
    end
  end
end
