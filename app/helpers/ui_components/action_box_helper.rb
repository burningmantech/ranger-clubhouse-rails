# frozen_string_literal: true

module UiComponents
  # Action Box Helper
  # Purpose-built component for action-oriented navigation boxes
  # ADHD-friendly design with clear visual hierarchy:
  #   Icon -> Title -> Description -> Action Button
  module ActionBoxHelper
    # Container styling - h-full ensures all boxes in same row match height
    ACTION_BOX_BASE = "bg-base-100 border border-line rounded-lg p-4 flex flex-col items-center text-center h-full"

    # Icon styling - large, brand-colored for quick visual recognition
    ACTION_BOX_ICON = "text-3xl icon-warning mb-2"

    # Title styling - prominent and clear
    ACTION_BOX_TITLE = "heading-title text-heading mb-1"

    # Description styling - muted, scannable
    ACTION_BOX_DESCRIPTION = "text-sm text-body leading-relaxed"

    # Renders an action-oriented card with icon, title, description, and action button
    #
    # @param title [String] Box title (required)
    # @param description [String] Short description text (required)
    # @param url [String] Action button destination (required)
    # @param icon [String] FontAwesome icon name (required)
    # @param icon_type [Symbol] Icon style (:solid, :regular), default :solid
    # @param button_label [String] Button text, default "View"
    # @param button_variant [Symbol] Button style (:primary, :secondary), default :primary
    # @param options [Hash] Additional HTML options for the container
    #
    # @example Basic usage
    #   <%= action_box(
    #     title: "Qualifications",
    #     description: "Track your earnings progress",
    #     url: qualifications_path,
    #     icon: "award"
    #   ) %>
    #
    # @example With custom button label
    #   <%= action_box(
    #     title: "Sign-ups",
    #     description: "Find shifts to sign up for",
    #     url: signups_path,
    #     icon: "calendar-plus",
    #     button_label: "View & Sign Up"
    #   ) %>
    #
    def action_box(title:, description:, url:, icon:, icon_type: :solid, button_label: "View", button_variant: :primary, options: {})
      container_class = "#{ACTION_BOX_BASE} #{options.delete(:class)}".squish
      container_options = options.merge(class: container_class)

      button_options = {
        icon: "arrow-right",
        icon_type: :solid,
        icon_position: :end,
        size: "sm",
        class: "w-full justify-center mt-auto"
      }

      button_options[:data] = options.delete(:button_data)
      content_tag :div, container_options do
        # Content area (grows to fill space, pushing button to bottom)
        content_tag(:div, class: "flex-1 flex flex-col items-center justify-center mb-4") do
          safe_join([
            # Icon - decorative, provides quick visual recognition
            fa_icon(icon, icon_type, class: ACTION_BOX_ICON, aria: { hidden: true }),

            # Title - clear and prominent
            content_tag(:h3, title, class: ACTION_BOX_TITLE),

            # Description - concise, muted
            content_tag(:p, description, class: ACTION_BOX_DESCRIPTION)
          ])
        end +
        # Action button - stays at bottom, full width
        button_link(button_label, button_variant, url, button_options)
      end
    end
  end
end
