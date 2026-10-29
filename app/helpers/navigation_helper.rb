# frozen_string_literal: true

# DaisyUI Dropdown Navigation Helper
# See: https://daisyui.com/components/dropdown/
#
module NavigationHelper
  # CSS utility class references for navigation dropdown menus
  DROPDOWN_CONTAINER = "dropdown-panel"
  DROPDOWN_ITEM = "dropdown-link"
  DROPDOWN_DISABLED = "dropdown-disabled-item"

  # Renders a dropdown menu as a native <details> disclosure, which DaisyUI
  # styles as a dropdown. The <summary> is the trigger button and the block
  # fills the list. A CSS-only :focus-within dropdown claims aria-haspopup="menu"
  # over a plain list of links, never reports open or closed, and needs a focus
  # event iOS Safari does not reliably send to a button; <details> does all
  # three natively.
  # Only its own summary closes a <details>; application.js also closes an open
  # dropdown from a link inside it or a click outside it, so a page Turbo caches
  # on the way out never holds one open.
  #
  # @param label [String] The trigger button label
  # @param variant [Symbol] ButtonHelper variant for the trigger (default :secondary)
  # @param summary_class [String] Extra classes for the trigger button
  # @param menu_class [String] Extra classes for the <ul>, such as a width
  # @param menu_label [String] Accessible name for the list (default: label); set it
  #   when the visible label is a greeting rather than the menu's name
  # @param trigger_label [String] Accessible name for an icon-only trigger: pass the
  #   icon as label, and the trigger drops its chevron
  # @param options [Hash] HTML options for the <details>; put DaisyUI placement
  #   modifiers such as "dropdown-end" in :class
  # @yield Block containing dropdown_item / dropdown_divider calls
  #
  # @example
  #   <%= dropdown_menu "Actions", class: "dropdown-end" do %>
  #     <%= dropdown_item "Profile", profile_path %>
  #     <%= dropdown_divider %>
  #     <%= dropdown_item "Logout", logout_path, data: { turbo_method: :delete } %>
  #   <% end %>
  #
  def dropdown_menu(label, variant: :secondary, summary_class: nil, menu_class: nil, menu_label: label,
                    trigger_label: nil, **options, &block)
    options[:class] = "dropdown #{options[:class]}".squish
    # An icon-only trigger is a 36px square, with no room for the chevron
    content = trigger_label ? label : safe_join([label, fa_icon("chevron-down", :solid)])

    content_tag :details, options do
      summary = content_tag(:summary, content, aria: { label: trigger_label },
                            class: "#{button_classes({}, variant)} list-none #{summary_class}".squish)
      list = content_tag(:ul, class: "dropdown-content #{DROPDOWN_CONTAINER} mt-2 #{menu_class}".squish,
                              aria: { label: menu_label }, &block)
      summary + list
    end
  end

  # Renders a dropdown menu item as a link
  #
  # @param label [String] The link text
  # @param url [String] The link URL
  # @param options [Hash] HTML options for link_to
  #
  def dropdown_item(label, url, options = {})
    # Add no-decoration class to opt out of base link styling (text-primary underline)
    options[:class] = "no-decoration #{DROPDOWN_ITEM} #{options[:class]}".squish

    content_tag :li do
      link_to label, url, options
    end
  end

  # Renders a dropdown menu item as a button, for an item that acts on the page
  # rather than going somewhere. Styled as dropdown_item's links are; w-full
  # because a block <button>, unlike a block <a>, is only as wide as its label.
  #
  # @param label [String] The button text
  # @param options [Hash] HTML options for the button (data: { action: ... })
  #
  def dropdown_button(label, options = {})
    options[:class] = "#{DROPDOWN_ITEM} w-full text-start #{options[:class]}".squish

    content_tag :li do
      tag.button(label, type: "button", **options)
    end
  end

  # Renders a dropdown menu divider: an empty <li>, which daisyUI's menu draws
  # as a 1px line. An <hr> inside the <li> took the menu's item padding and
  # rounded corners and drew as a hollow pill. Hidden from screen readers, so
  # a list of three links is not announced as five items.
  #
  def dropdown_divider
    content_tag :li, nil, aria: { hidden: true }
  end

  # Renders a disabled dropdown menu item
  #
  # @param label [String] The disabled item text
  #
  def dropdown_item_disabled(label)
    content_tag :li do
      content_tag :span, label, class: DROPDOWN_DISABLED
    end
  end
end
