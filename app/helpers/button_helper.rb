# frozen_string_literal: true

module ButtonHelper
  # DaisyUI button CSS classes
  # See: https://daisyui.com/components/button/

  # Base styling - all buttons share these classes
  BUTTON_BASE = "btn"

  # `full_width: true` -- a bar on a phone and a tablet, an ordinary button from
  # lg up. The breakpoint is lg, not sm: design-forms reserves sm: for field
  # widths, and every other responsive width in the app turns at lg.
  # A sticky row's spacer keys on `w-full` to know its bars stay one to a line
  # until lg (`.button-row-spacer`, components/buttons.css).
  FULL_WIDTH_CLASSES = "w-full lg:w-auto"

  # Variant CSS class mapping
  VARIANT_CLASSES = {
    primary: "btn-primary",
    secondary: "btn-secondary btn-outline",
    tertiary: "btn-ghost",
    success: "btn-success",
    error: "btn-error",
    warning: "btn-warning",
    dark: "btn-neutral",
    ghost: "btn-ghost"
  }.freeze

  DISABLED_CLASS = "btn-disabled"

  # Size mapping - DaisyUI btn sizes
  SIZE_CLASSES = {
    "xs" => "btn-xs",
    "sm" => "btn-sm",
    "base" => "btn-md",
    "lg" => "btn-lg",
    "xl" => "btn-xl"
  }.freeze

  DEFAULT_SIZE = "sm"

  # Button row container
  # Options:
  #   :sticky - if true, makes the button row sticky at the bottom of the viewport on mobile devices
  #   :class - additional CSS classes
  #
  # A row whose every button is behind a condition renders nothing when they
  # all turn out false, rather than an empty div inside whatever margin the
  # caller wrapped it in. Spelled by hand, that guard has to be repeated at the
  # wrapper of every such call site, and the callers that forget it leave a
  # blank band on the page.
  def button_row(options = {})
    content = block_given? ? capture { yield } : nil
    return if content.blank?

    sticky = options.delete(:sticky)
    base_class = "button-row"

    if sticky
      # Fixed positioning on mobile for full-width coverage, normal positioning on desktop (lg: breakpoint)
      # Uses fixed + inset-x-0 for edge-to-edge positioning, with explicit width to prevent gaps
      # `.button-row-spacer` adds this box up, and border-t and the top of py-4 are restated in its sum: change them together.
      base_class = "#{base_class} fixed bottom-0 left-0 right-0 w-full z-50 bg-base-100 py-4 px-4 border-t border-line shadow-[0_-4px_6px_-1px_rgba(0,0,0,0.1)] dark:shadow-[0_-4px_6px_-1px_rgba(0,0,0,0.3)] lg:static lg:inset-auto lg:w-auto lg:z-auto lg:bg-transparent lg:border-0 lg:shadow-none lg:px-0 lg:py-0"

      options[:class] = "#{base_class} #{options[:class]}".squish

      # Spacer div reserves space in document flow on mobile (hidden on desktop where button is static)
      #
      # The row is fixed, so nothing in the flow knows how tall it is. What this
      # helper does know is how many controls it just rendered: each top-level
      # element is one line of the stack below md, and a hidden field draws nothing.
      # `.button-row-spacer` (components/buttons.css) turns that count into the
      # row's own height. It is a genuinely dynamic number, so it travels as a
      # custom property -- the one thing that may be styled inline.
      #
      # The spacer also wears the tallest size class in the row (SIZE_CLASSES runs
      # smallest to largest). It is not a button: that class is where DaisyUI, and
      # the 36px floor in accessibility.css, keep --size, and reading the control
      # height from there beats restating it.
      fragment = Nokogiri::HTML5.fragment(content)
      controls = fragment.element_children.count { |node| node["type"] != "hidden" }
      tallest = SIZE_CLASSES.values.reverse.find { |size_class| fragment.at_css(".#{size_class}") } || SIZE_CLASSES[DEFAULT_SIZE]
      spacer = content_tag(:div, "", class: "button-row-spacer #{tallest}", style: "--button-row-controls: #{controls}", aria: { hidden: true })

      # The captured content, not a second `yield`: the count above and the
      # controls in the row then come from the same evaluation of the block.
      safe_join([spacer, content_tag(:div, content, options)])
    else
      options[:class] = "#{base_class} #{options[:class]}".squish
      content_tag(:div, content, options)
    end
  end

  # Generic button with Stimulus action
  # Options:
  #   :variant - button style (:primary, :secondary, :tertiary, :success, :error, :warning, :dark, :ghost) - default: :primary
  #   :controller - a Stimulus controller on the button itself (data-controller). Never
  #     the name of a controller wrapping the button: that starts a second copy scoped
  #     to the button alone, which owns none of the wrapper's targets, so every click
  #     silently does nothing. To act on the wrapper, pass only data: { action: ... }.
  #   :icon - FontAwesome icon name
  #   :icon_type - FontAwesome icon type (regular, solid, etc.)
  #   :disabled - disable the button
  #   :size - text size (xs, sm, base, lg, xl, 2xl, etc.)
  #   :class - additional CSS classes
  def button_action(label, variant, controller: nil, **options)
    icon_content = extract_icon_options(options)
    disabled = options.delete(:disabled)

    options[:type] ||= "button"
    options[:disabled] = true if disabled
    if controller
      options[:data] ||= {}
      options[:data][:controller] = controller
    end

    apply_button_classes(options, variant, disabled)

    button_tag options do
      render_button_content(icon_content, label)
    end
  end

  # Link styled as a button
  # Options:
  #   :size - text size (xs, sm, base, lg, xl, 2xl, etc.)
  #   :icon - FontAwesome icon name
  #   :icon_type - FontAwesome icon type
  #   :disabled - disable the link
  #   :class - additional CSS classes
  #   :method - HTTP method, submitted by Turbo (data-turbo-method)
  #   :params - query params added to the URL; with :method Turbo submits them as the form fields
  def button_link(label, variant, url, options = {}, &block)
    if block_given?
      raise ArgumentError, "Both a label and block given." if label
      label = capture(&block)
    end

    options = options.clone

    method = options.delete(:method)
    if method
      options[:data] ||= {}
      options[:data][:turbo_method] = method
    end

    # link_to has no params: option; a stray hash would render as an HTML attribute.
    if (params = options.delete(:params))
      url = "#{url}#{url.to_s.include?("?") ? "&" : "?"}#{params.to_query}"
    end

    icon_content = extract_icon_options(options)
    disabled = options.delete(:disabled)

    apply_button_classes(options, variant, disabled)
    options[:class] = "#{options[:class]} no-decoration".squish
    content = render_button_content(icon_content, label)

    # `disabled` means nothing on an <a>, and btn-disabled only stops the pointer:
    # the link stayed in the tab order and Enter still followed it. Without an
    # href it is neither; the role keeps it announced as a (dimmed) link.
    return content_tag(:a, content, options.except(:disabled).merge(role: "link")) if disabled

    link_to content, url, options
  end

  # Cancel button (secondary button style)
  # Accepts: (url), (url, label), (url, options), (url, label, options)
  def cancel_button(url, label = nil, options = {})
    label, options = normalize_button_args(label, options)
    button_link label || "Cancel", :secondary, url, options
  end

  # Cancel link (secondary button style) - alias for cancel_button
  alias cancel_link cancel_button

  # Edit link (secondary style, pen-to-square icon)
  # Accepts: (url), (url, label), (url, options), (url, label, options)
  #
  # This is the ONE edit affordance. It carries its own icon so that every
  # "edit this record" control in the app reads the same whether it sits in a
  # table row, a section header, or a detail page's button row -- the icon used
  # to be opt-in, and the app drifted into `pen`, `pen-to-square` and no icon
  # at once. Pass `icon:` only to deliberately override it.
  def edit_link(url, label = nil, options = {})
    label, options = normalize_button_args(label, options)
    options = { icon: "pen-to-square", icon_type: :solid }.merge(options)
    button_link label || "Edit", :secondary, url, options
  end

  # CSV export link (secondary style, file-csv icon)
  # Accepts: (url), (url, label), (url, options), (url, label, options)
  #
  # This is the ONE export affordance, for the same reason edit_link is the one
  # edit affordance. Every report page spells the same variant and icon, so
  # spelling them by hand is how they drift.
  #
  # A whole-report export says so in its label ("Export All to CSV"); a
  # filtered one carries its filters in the url. See
  # `UiComponents::FilterBarHelper#filter_bar` -- on a page with a filter bar
  # this belongs in its `actions:`.
  # Pass `variant:` only where an export is the page's primary action, as the
  # payroll page's recommended download is.
  def export_csv_link(url, label = nil, options = {})
    label, options = normalize_button_args(label, options)
    options = { icon: "file-csv", icon_type: :solid }.merge(options)
    variant = options.delete(:variant) || :secondary
    button_link label || "Export CSV", variant, url, options
  end

  # Delete button (danger style)
  # Accepts: (url), (url, label), (url, options), (url, label, options)
  # Options:
  #   :confirm_message - plain text message shown in the standard confirm modal
  #   :confirm_modal   - options hash passed to confirm_modal helper for a custom dialog
  # Either dialog's Confirm button is red (variant: :error) unless the hash says otherwise.
  def delete_button(url, label = nil, options = {})
    label, options = normalize_button_args(label, options)

    confirm_message = options.delete(:confirm_message)
    confirm_modal_options = options.delete(:confirm_modal)
    variant = options.delete(:variant) || :error

    options[:data] ||= {}

    if confirm_modal_options
      options[:data].merge!(confirm_modal({ variant: :error }.merge(confirm_modal_options)))
    elsif confirm_message
      options[:data][:turbo_confirm] = confirm_modal_dialog(message: confirm_message, variant: :error)
    end

    options[:method] ||= :delete

    button_link label || "Delete", variant, url, options
  end

  # Submit button for forms
  # Accepts: (), (label), (options), (label, options)
  def submit_button(label = nil, options = {})
    label, options = normalize_button_args(label, options)
    label ||= "Submit"
    variant = options.delete(:variant) || :primary
    disabled = options.delete(:disabled)
    options[:disabled] = true if disabled
    apply_button_classes(options, variant, disabled)
    submit_tag label, options
  end

  private

  # Extract icon options from options hash and return icon content
  def extract_icon_options(options)
    icon_name = options.delete(:icon)
    icon_type = options.delete(:icon_type) || "regular"
    icon_name ? { name: icon_name, type: icon_type } : nil
  end

  # Render button content with optional icon
  def render_button_content(icon_content, label)
    if icon_content
      icon = fa_icon(icon_content[:name], icon_content[:type])
      icon.html_safe + label
    else
      label
    end
  end

  # Normalize button arguments for flexible method signatures
  # Handles: (label), (options), (label, options)
  def normalize_button_args(label, options)
    if label.is_a?(Hash)
      [nil, label]
    else
      [label, options]
    end
  end

  # Apply button CSS classes to options hash (modifies options in place)
  def apply_button_classes(options, variant, disabled = false)
    size = options.delete(:size) || DEFAULT_SIZE
    size_class = SIZE_CLASSES[size.to_s] || SIZE_CLASSES[DEFAULT_SIZE]
    variant_class = disabled ? DISABLED_CLASS : variant_class_for(variant)
    width_class = FULL_WIDTH_CLASSES if options.delete(:full_width)

    options[:class] = "#{BUTTON_BASE} #{variant_class} #{size_class} #{width_class} #{options[:class]}".squish

    if disabled
      options[:disabled] = true
      options["aria-disabled"] = "true"
    end
  end

  # Returns button CSS classes as a string (for use in class attributes)
  # @param options [Hash] options hash (size will be extracted if present)
  # @param variant [Symbol] button variant (:primary, :secondary, etc.)
  # @return [String] CSS class string
  # The class string on its own, for the few places that style something other
  # than a button as one -- a <summary> that has to look like the button it
  # replaces. Takes the same size: and full_width: options as the helpers do.
  def button_classes(options, variant)
    size = options.delete(:size) || DEFAULT_SIZE
    size_class = SIZE_CLASSES[size.to_s] || SIZE_CLASSES[DEFAULT_SIZE]
    width_class = FULL_WIDTH_CLASSES if options.delete(:full_width)

    "#{BUTTON_BASE} #{variant_class_for(variant)} #{size_class} #{width_class} #{options[:class]}".squish
  end

  # Get button CSS class by variant
  def variant_class_for(variant)
    VARIANT_CLASSES[variant] || VARIANT_CLASSES[:primary]
  end
end
