# frozen_string_literal: true

# AppFormBuilder provides accessible form fields styled with DaisyUI 5 form classes
#
# Design Principles:
#   - Compact layout that minimizes scrolling
#   - WCAG 2.1 Level AA compliant (24px minimum touch targets)
#   - Clear visual hierarchy with visible labels
#   - Strong focus states for keyboard navigation
#   - Smooth transitions for state changes
#
# Supports three layout modes:
#   - :vertical (default) - Labels above inputs
#   - :horizontal - Labels beside inputs
#   - :auto - Vertical on mobile, horizontal on desktop (lg: breakpoint)
#
# @example Basic usage
#   ui_form(@user, users_path) do |f|
#     f.text_field :name, label: "Full Name", required: true
#   end
#
class AppFormBuilder < ActionView::Helpers::FormBuilder
  include ButtonHelper
  include IconHelper

  VALID_LAYOUTS = %i[vertical horizontal auto].freeze

  # =============================================================================
  # FIELD STYLING (DaisyUI 5 form classes)
  # =============================================================================

  DEFAULT_WIDTH_CLASSES = "w-auto"
  TEXTAREA_DEFAULT_WIDTH = "w-full"

  SELECT_FIELD_OPTION_KEYS = %i[
    label help_text help_mode show_counter wrapper_class wrapper wrapper_id hidden
    layout width required required_label hide_label icon icon_type icon_class
    replace_class
  ].freeze

  # Icon padding override — CSS class triggers padding-inline-start rule in forms.css
  ICON_PADDING_CLASS = "has-icon"

  # =============================================================================
  # ICON PREFIX STYLING
  # =============================================================================

  ICON_CONTAINER_CLASSES = "relative"
  ICON_CLASSES = "absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-stone-muted"
  ICON_ERROR_CLASSES = "absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-error"

  # =============================================================================
  # COMPOSITE CSS CLASSES (DaisyUI form classes with width defaults)
  # =============================================================================

  INPUT_CLASSES = "input w-auto"
  INPUT_ERROR_CLASSES = "input input-error w-auto"

  LABEL_CLASSES = "block mb-1 font-medium text-heading text-base"
  LABEL_ERROR_CLASSES = "block mb-1 font-medium text-error text-base"

  # Fieldset styling - left accent border for clear visual grouping (ADHD-friendly)
  FIELDSET_CLASSES = "form-fieldset"
  LEGEND_CLASSES = "form-legend"

  HELP_TEXT_CLASSES = "mt-1 text-sm text-body leading-snug"
  ERROR_TEXT_CLASSES = "mt-1 text-sm text-error font-medium flex items-center gap-1"
  ERROR_ICON_TEXT_CLASSES = "text-error shrink-0"

  WRAPPER_CLASSES = "mb-3"
  # Stacked checkboxes/radios sit tighter than other fields (half the gap)
  TOGGLE_FIELD_WRAPPER_CLASSES = "mb-1"

  # =============================================================================
  # CHECKBOX & RADIO STYLING
  # =============================================================================

  CHECKBOX_CLASSES = "checkbox checkbox-primary checkbox-sm"
  CHECKBOX_ERROR_CLASSES = "checkbox checkbox-error checkbox-sm"

  RADIO_CLASSES = "radio radio-primary radio-sm"
  RADIO_ERROR_CLASSES = "radio radio-error radio-sm"

  # min-h-9 keeps the tap target at the 36px accessibility minimum. Without it
  # the label collapses to its line box (~24px with the sm checkbox), which is
  # the whole hit area for every f.check_box and f.radio_button in the app.
  TOGGLE_LABEL_CLASSES = "ms-2 inline-flex items-center min-h-9 text-base text-heading select-none cursor-pointer leading-tight"
  TOGGLE_LABEL_ERROR_CLASSES = "ms-2 inline-flex items-center min-h-9 text-base text-error select-none cursor-pointer leading-tight"
  TOGGLE_WRAPPER_CLASSES = "flex items-center"

  SELECT_CLASSES = "select w-auto"
  SELECT_ERROR_CLASSES = "select select-error w-auto"

  TEXTAREA_CLASSES = "textarea w-full resize-y"
  TEXTAREA_ERROR_CLASSES = "textarea textarea-error w-full resize-y"

  FILE_INPUT_CLASSES = "file-input w-auto"
  FILE_INPUT_ERROR_CLASSES = "file-input file-input-error w-auto"

  # The rich text editor draws its own border, padding and toolbar in the
  # vendored lexxy-editor.css, re-themed by components/lexxy.css. Both are
  # imported into @layer components -- so a plain utility here wins and the error
  # state needs no `!`. lexxy-content gives the text being edited the rules a
  # saved document is read with. w-auto is here so `width:` has something to
  # substitute, the way it does for input and select.
  RICH_TEXT_CLASSES = "lexxy-content w-auto"
  RICH_TEXT_ERROR_CLASSES = "lexxy-content w-auto border-error border-2"

  # A link written relative to a folder: "docs/map.pdf", "me/schedule". See
  # editor_ready.
  FOLDER_RELATIVE_HREF = %r{\A[^/?#.:\s]+/}

  # =============================================================================
  # HORIZONTAL LAYOUT CLASSES
  # =============================================================================

  HORIZONTAL_WRAPPER_CLASSES = "flex flex-col lg:flex-row lg:items-start gap-1 lg:gap-3"
  HORIZONTAL_LABEL_CLASSES = "font-medium text-heading text-base lg:pt-2 lg:w-1/4 lg:shrink-0 lg:mr-2"
  HORIZONTAL_LABEL_ERROR_CLASSES = "font-medium text-error text-base lg:pt-2 lg:w-1/4 lg:shrink-0"
  HORIZONTAL_INPUT_CONTAINER_CLASSES = "flex-1 min-w-0"

  # =============================================================================
  # AUTO LAYOUT CLASSES (vertical on mobile, horizontal on desktop)
  # =============================================================================

  AUTO_WRAPPER_CLASSES = "mb-3 lg:flex lg:flex-row lg:items-start lg:gap-3"
  AUTO_LABEL_CLASSES = "block mb-1 font-medium text-heading text-base lg:mb-0 lg:pt-2 lg:w-1/8 lg:shrink-0 "
  AUTO_LABEL_ERROR_CLASSES = "block mb-1 font-medium text-error text-base lg:mb-0 lg:pt-2 lg:w-1/8 lg:shrink-0"
  AUTO_INPUT_CONTAINER_CLASSES = "lg:flex-1 lg:min-w-0"

  # =============================================================================
  # VANILLA CALENDAR PRO DEFAULTS
  # =============================================================================

  VANILLA_CALENDAR_DEFAULTS = {
    selectionTimeMode: 24,
    inputMode: true
  }.freeze

  # =============================================================================
  # FIELD CLASS MAPPINGS
  # =============================================================================

  FIELD_CLASSES = {
    input: { normal: INPUT_CLASSES, error: INPUT_ERROR_CLASSES },
    textarea: { normal: TEXTAREA_CLASSES, error: TEXTAREA_ERROR_CLASSES },
    select: { normal: SELECT_CLASSES, error: SELECT_ERROR_CLASSES },
    file: { normal: FILE_INPUT_CLASSES, error: FILE_INPUT_ERROR_CLASSES },
    rich_text: { normal: RICH_TEXT_CLASSES, error: RICH_TEXT_ERROR_CLASSES },
    checkbox: { normal: CHECKBOX_CLASSES, error: CHECKBOX_ERROR_CLASSES },
    radio: { normal: RADIO_CLASSES, error: RADIO_ERROR_CLASSES },
    label: { normal: LABEL_CLASSES, error: LABEL_ERROR_CLASSES },
    horizontal_label: { normal: HORIZONTAL_LABEL_CLASSES, error: HORIZONTAL_LABEL_ERROR_CLASSES },
    auto_label: { normal: AUTO_LABEL_CLASSES, error: AUTO_LABEL_ERROR_CLASSES },
    toggle_label: { normal: TOGGLE_LABEL_CLASSES, error: TOGGLE_LABEL_ERROR_CLASSES }
  }.freeze

  # =============================================================================
  # FIELDSET LEGEND CAPTURER
  # =============================================================================

  # Helper class for capturing legend content in fieldset blocks
  class FieldsetLegendCapturer
    attr_reader :content

    def initialize(template) = @template = template

    def legend(text = nil, &)
      @content = block_given? ? @template.capture(&) : text
    end
  end

  # =============================================================================
  # INITIALIZATION
  # =============================================================================

  def initialize(object_name, object, template, options)
    @layout = options.delete(:layout) || :vertical
    @layout = :vertical unless @layout.in?(VALID_LAYOUTS)
    super
  end

  # =============================================================================
  # TEXT-BASED INPUT FIELDS
  # =============================================================================

  %i[text_field email_field password_field number_field url_field telephone_field
     search_field date_field time_field color_field].each do |field_type|
    define_method(field_type) do |attribute, options = {}|
      build_field(attribute, options) { |opts| super(attribute, opts) }
    end
  end

  # =============================================================================
  # DATETIME FIELD (Vanilla Calendar Pro)
  # =============================================================================

  def datetime_field(attribute, options = {})
    calendar_options = options.delete(:calendar_options) || {}
    use_calendar = options.delete(:use_calendar) != false

    build_field(attribute, options) do |opts|
      if use_calendar
        add_vanilla_calendar_attributes(opts, calendar_options)
        str = @template.text_field(object_name, attribute, objectify_options(opts))
        str
      else
        @template.datetime_local_field(object_name, attribute, objectify_options(opts))
      end
    end
  end

  # =============================================================================
  # AUTOCOMPLETE FIELD
  # =============================================================================

  # Renders an autocomplete search field with JSON-powered results dropdown.
  #
  # @param attribute [Symbol] The form attribute (used for label, hidden field)
  # @param options [Hash] Field options
  # @option options [String] :url The autocomplete endpoint URL (required)
  # @option options [String] :mode Search mode sent as query param
  # @option options [Integer] :limit Max results (default 5)
  # @option options [Integer] :min_length Min chars before search (default 2)
  # @option options [Hash] :meta_mapping Maps item.meta keys to hidden field IDs
  # @option options [Boolean] :submit_on_select Submit form on selection
  # @option options [String] :recents_key LocalStorage key for recents
  # @option options [String] :display_attribute Attribute for display value (default: attribute)
  #
  # @example Basic usage
  #   f.autocomplete_field :person_id, url: autocomplete_search_path,
  #     mode: "person_manage", label: "Search Person"
  #
  # @example With metadata writeback
  #   f.autocomplete_field :person_id, url: autocomplete_search_path,
  #     meta_mapping: { "id" => "person_id", "status" => "person_status" }
  #
  def autocomplete_field(attribute, options = {})
    ac_url = options.delete(:url)
    ac_mode = options.delete(:mode)
    ac_limit = options.delete(:limit) || 5
    ac_min_length = options.delete(:min_length) || 2
    ac_meta_mapping = options.delete(:meta_mapping)
    ac_submit_on_select = options.delete(:submit_on_select) || false
    ac_recents_key = options.delete(:recents_key)
    ac_display_attribute = options.delete(:display_attribute)

    build_field(attribute, options) do |opts|
      # Label targets sanitized_field_id(attribute) — assign that to the visible input
      # so label click/focus and screen reader association work correctly.
      input_id = sanitized_field_id(attribute)
      hidden_id = "#{input_id}_value"
      wrapper_id = "#{input_id}-ac"
      results_id = "#{wrapper_id}-results"

      data_attrs = {
        controller: "autocomplete",
        autocomplete_url_value: ac_url,
        autocomplete_response_type_value: "json",
        autocomplete_min_length_value: ac_min_length,
        autocomplete_limit_value: ac_limit
      }

      data_attrs[:autocomplete_mode_value] = ac_mode if ac_mode.present?
      data_attrs[:autocomplete_meta_mapping_value] = ac_meta_mapping.to_json if ac_meta_mapping.present?
      data_attrs[:autocomplete_submit_on_select_value] = "true" if ac_submit_on_select
      data_attrs[:autocomplete_recents_key_value] = ac_recents_key if ac_recents_key.present?

      # Build the composite widget
      @template.tag.div(
        id: wrapper_id,
        data: data_attrs,
        role: "combobox",
        aria: { expanded: "false", haspopup: "listbox", owns: results_id },
        class: "relative"
      ) do
        # Display input
        display_value = if ac_display_attribute && object.respond_to?(ac_display_attribute)
                          object.send(ac_display_attribute)
                        else
                          ""
                        end

        # Propagate required, disabled, aria-describedby and aria-invalid from build_field opts
        input_aria = { autocomplete: "list", controls: results_id }
        input_aria[:describedby] = opts.dig(:aria, :describedby) if opts.dig(:aria, :describedby)
        input_aria[:invalid] = true if opts.dig(:aria, :invalid)
        input_aria[:required] = "true" if opts[:required]

        input_tag = @template.tag.input(
          type: "text",
          id: input_id,
          name: nil,
          value: display_value,
          placeholder: opts.delete(:placeholder) || "Search…",
          autocomplete: "off",
          spellcheck: "false",
          # Callsigns are not words: iOS would offer to correct "Cust" to "Crust".
          autocorrect: "off",
          autocapitalize: "off",
          required: opts[:required],
          disabled: opts[:disabled],
          class: opts[:class],
          data: { autocomplete_target: "input" },
          aria: input_aria
        )

        # Hidden field for actual value (not the label target)
        hidden_value = object.respond_to?(attribute) ? object.send(attribute) : ""
        hidden_tag = @template.hidden_field(
          object_name, attribute,
          id: hidden_id,
          value: hidden_value,
          data: { autocomplete_target: "hidden" }
        )

        # Loading indicator
        loading_tag = @template.tag.div(
          data: { autocomplete_target: "loading" },
          hidden: true,
          class: "ac-loading"
        ) { "Searching…" }

        # Results container
        results_tag = @template.tag.div(
          id: results_id,
          data: { autocomplete_target: "results" },
          role: "listbox",
          class: "ac-results",
          hidden: true
        )

        safe_join([input_tag, hidden_tag, loading_tag, results_tag])
      end
    end
  end

  # =============================================================================
  # CALLSIGN CHIPS FIELD
  # =============================================================================

  # Several callsigns as removable chips in one input box, over the
  # shared/_autocomplete whose suggestions the url answers (the messages
  # compose form's recipients). Each chip sends <object>[<attribute>][], so the
  # attribute reads an array; callsign_chips_controller adds and removes them.
  #
  # @option options [String] :url The suggestions endpoint, answering autocomplete JSON (required)
  # @option options [Integer] :max The most chips it holds: a new one past it replaces the oldest (the HQ
  #   window's relay names one sender)
  # @option options [String] :placeholder The input's placeholder and, less its ellipsis, its accessible name
  #
  # @example
  #   f.callsign_chips_field :callsigns, url: suggest_callsigns_messages_path, label: "To"
  #   f.callsign_chips_field :callsigns, url: suggest_callsigns_messages_path, label: "From", max: 1
  #
  def callsign_chips_field(attribute, options = {})
    url = options.delete(:url)
    max = options.delete(:max)
    placeholder = options.delete(:placeholder) || (max == 1 ? "Choose a callsign…" : "Add a callsign…")

    build_field(attribute, options) do |opts|
      @template.render("shared/callsign_chips",
                       name: "#{object_name}[#{attribute}][]", callsigns: Array(object.public_send(attribute)),
                       url:, max:, field_id: sanitized_field_id(attribute), placeholder:,
                       describedby: opts.dig(:aria, :describedby), invalid: opts.dig(:aria, :invalid),
                       box_class: "#{opts[:class]} h-auto flex flex-wrap items-center gap-2 py-1")
    end
  end

  # =============================================================================
  # TEXTAREA FIELD
  # =============================================================================

  def text_area(attribute, options = {})
    options[:width] ||= TEXTAREA_DEFAULT_WIDTH
    build_field(attribute, options.merge(field_type: :textarea)) { |opts| super(attribute, opts) }
  end

  # =============================================================================
  # RICH TEXT FIELD
  # =============================================================================

  # A formatted-text field: bold, italic, lists, links and tables, stored as HTML.
  #
  #   f.rich_text_area :message, label: "Message", required: true
  #
  # <lexxy-editor> is a form control in its own right. It submits under its own
  # name, so no hidden input carries the value and the one id serves the label.
  # It is form-associated, so it reports its own validity: `required` blocks
  # submission the way it does on any other field, and sets aria-required.
  def rich_text_area(attribute, options = {})
    build_field(attribute, options.merge(field_type: :rich_text)) do |opts|
      # Lexxy is 640KB and is not in the application bundle. The controller named
      # here is what imports it (and answers a click on the field's label), so the
      # editor's JavaScript is fetched by the pages that have an editor rather than
      # by every page in the app. morph_skip: the editor builds its toolbar and
      # holds the typed text itself, so a page update must leave it as it stands
      # (see application.js).
      data = opts[:data] || {}
      opts[:data] = data.merge(controller: merge_data_controllers(data[:controller], "lexxy"), morph_skip: true)

      # Nothing here serves uploads, so attachments are off: no toolbar buttons,
      # and a pasted or dropped file is ignored (no node is made, no upload
      # starts). The value goes in as a plain String because the tag helper
      # escapes only the quotes of a SafeBuffer, and text that was saved as
      # &lt;b&gt; would reach the editor as a real tag.
      current = (object.public_send(attribute) if object).to_s.to_str
      # The warning is about what is on file, not what the form holds: after a
      # rejected save the form holds what the editor sent, which has no image
      # left in it, while the saved text still has every one.
      on_file = (object.try(:attribute_in_database, attribute) || current).to_s
      safe_join([
                  lost_images_warning(on_file),
                  @template.tag.lexxy_editor(**opts, id: sanitized_field_id(attribute), name: field_name(attribute),
                                             value: editor_ready(current), attachments: "false")
                ])
    end
  end

  # =============================================================================
  # SELECT FIELDS
  # =============================================================================

  def select(attribute, choices = nil, options = {}, html_options = {}, &block)
    options, html_options = normalize_select_field_options(options, html_options)

    build_field(attribute, options.merge(html_options:, field_type: :select)) do |opts|
      merged_html_options = extract_select_html_options!(opts)
      super(attribute, choices, opts, merged_html_options, &block)
    end
  end

  def collection_select(attribute, collection, value_method, text_method, options = {}, html_options = {})
    options, html_options = normalize_select_field_options(options, html_options)

    build_field(attribute, options.merge(html_options:, field_type: :select)) do |opts|
      merged_html_options = extract_select_html_options!(opts)
      super(attribute, collection, value_method, text_method, opts, merged_html_options)
    end
  end

  # =============================================================================
  # CHECKBOX FIELD
  # =============================================================================

  def check_box(attribute, options = {}, checked_value = "1", unchecked_value = "0")
    field_opts = extract_field_options(options, attribute)
    inline_label = options.delete(:inline_label)

    options[:class] = merge_classes(classes_for(:checkbox, field_opts[:has_errors]), options[:class])
    options[:aria] = (options[:aria] || {}).merge(invalid: true) if field_opts[:has_errors]
    checkbox_tag = super

    build_toggle_field(:checkbox, attribute, checkbox_tag, field_opts, inline_label:)
  end

  # =============================================================================
  # RADIO BUTTON
  # =============================================================================

  def radio_button(attribute, tag_value, options = {})
    field_opts = extract_field_options(options, tag_value, attribute)

    options[:class] = merge_classes(classes_for(:radio, field_opts[:has_errors]), options[:class])
    options[:aria] = (options[:aria] || {}).merge(invalid: true) if field_opts[:has_errors]
    radio_tag = super

    build_toggle_field(:radio, attribute, radio_tag, field_opts, tag_value:)
  end

  # =============================================================================
  # COLLECTION RADIO BUTTONS
  # =============================================================================

  def collection_radio_buttons(attribute, collection, value_method, text_method, options = {}, html_options = {})
    field_opts = extract_field_options(options, attribute)

    case field_opts[:layout]
    when :horizontal
      build_horizontal_collection_radio_buttons(attribute, collection, value_method, text_method, options, html_options, field_opts)
    when :auto
      build_auto_collection_radio_buttons(attribute, collection, value_method, text_method, options, html_options, field_opts)
    else
      build_vertical_collection_radio_buttons(attribute, collection, value_method, text_method, options, html_options, field_opts)
    end
  end

  # =============================================================================
  # FILE FIELD
  # =============================================================================

  def file_field(attribute, options = {})
    build_field(attribute, options.merge(field_type: :file)) { |opts| super(attribute, opts) }
  end

  # =============================================================================
  # FIELDSET
  # =============================================================================

  def fieldset(legend_text = nil, options = {}, &block)
    legend_class = options.delete(:legend_class) || LEGEND_CLASSES
    fieldset_class = options.delete(:class) || FIELDSET_CLASSES
    icon = options.delete(:icon)
    icon_type = options.delete(:icon_type) || :regular

    capturer = FieldsetLegendCapturer.new(@template)
    block_content = @template.capture(capturer, &block)

    final_legend = legend_text || capturer.content
    raise ArgumentError, "fieldset requires a legend text argument or legend block" if final_legend.blank?

    # Add icon to legend if provided
    if icon
      icon_html = @template.fa_icon(icon, icon_type, end: 2)
      final_legend = "#{icon_html}#{final_legend}".html_safe
    end

    @template.tag.fieldset(**options, class: fieldset_class) do
      @template.tag.legend(final_legend, class: legend_class) +
        @template.tag.div(block_content, class: "space-y-3")
    end
  end

  # =============================================================================
  # SUBMIT BUTTON
  # =============================================================================

  def submit(value = nil, options = {})
    variant = options.delete(:variant) || :primary
    options[:class] = button_classes(options, variant)
    super
  end

  private

  # =============================================================================
  # FIELD OPTIONS EXTRACTION
  # =============================================================================

  def extract_field_options(options, label_source, attribute = nil)
    attribute ||= label_source if label_source.is_a?(Symbol)

    # Extract and validate label_position (for collection_radio_buttons)
    label_position = options.delete(:label_position)
    label_position = :inline unless %i[inline stacked].include?(label_position)

    {
      label_text: options.delete(:label),
      help_text: options.delete(:help_text),
      help_mode: options.delete(:help_mode) || :inline,
      show_counter: options.delete(:show_counter),
      wrapper_class: options.delete(:wrapper_class),
      skip_wrapper: options.delete(:wrapper) == false,
      layout: extract_layout(options),
      wrapper_id: options.delete(:wrapper_id),
      hidden: options.delete(:hidden),
      has_errors: attribute && object_has_error?(attribute),
      width: options.delete(:width),
      required: options.delete(:required),
      required_label: options.delete(:required_label),
      hide_label: options.delete(:hide_label),
      icon: options.delete(:icon),
      icon_type: options.delete(:icon_type) || :solid,
      icon_class: options.delete(:icon_class),
      replace_class: options.delete(:replace_class),
      label_position:
    }
  end

  def extract_layout(options)
    field_layout = options.delete(:layout) || @layout
    field_layout.in?(VALID_LAYOUTS) ? field_layout : :vertical
  end

  def normalize_select_field_options(options, html_options)
    normalized_options = options.dup
    normalized_html_options = html_options.dup

    SELECT_FIELD_OPTION_KEYS.each do |key|
      next unless normalized_html_options.key?(key)
      next if normalized_options.key?(key)

      normalized_options[key] = normalized_html_options.delete(key)
    end

    [normalized_options, normalized_html_options]
  end

  def extract_select_html_options!(options)
    html_options = options.delete(:html_options) || {}

    if options[:class].present?
      html_options[:class] = merge_classes(html_options[:class], options.delete(:class))
    end

    %i[required].each do |key|
      html_options[key] = options.delete(key) if options.key?(key)
    end

    %i[aria data].each do |key|
      next unless options[key].present?

      html_options[key] = (html_options[key] || {}).merge(options.delete(key))
    end

    html_options
  end

  # Merges Stimulus controller names, avoiding duplicates
  def merge_data_controllers(existing, new_controller)
    return new_controller if existing.blank?

    controllers = existing.to_s.split(" ")
    controllers << new_controller unless controllers.include?(new_controller)
    controllers.join(" ")
  end

  # The editor keeps no image: nothing here stores one, and with uploads off it
  # drops every <img> it is handed. So saving text that has one removes it. Said
  # on the form, before the save, rather than found out after it.
  def lost_images_warning(html)
    count = Nokogiri::HTML5.fragment(html).css("img").size
    return if count.zero?

    images, them = count == 1 ? ["an image", "it"] : ["#{count} images", "them"]
    @template.ui_callout_box(:warning) do
      safe_join([
                  @template.tag.strong("This text has #{images}, which the editor cannot keep."),
                  " Saving removes #{them}. To keep #{them}, leave this page without saving."
                ])
    end
  end

  # The text, with the two things the editor would damage put right before it
  # loads them. Text with neither comes back as it was.
  #
  # An image is dropped by the editor in any case, and takes the spaces on either
  # side with it ("Press <img> to continue" came back as "Pressto continue"). It
  # is taken out here instead, where the spaces stay, along with a link that held
  # nothing else. That also keeps a photo pasted in as megabytes of text out of
  # the page.
  #
  # A link written relative to a folder gets "https://" put in front of it by the
  # editor, which sends it to a host that does not exist. "./" in front says the
  # same thing in a form the editor leaves alone.
  def editor_ready(html)
    fragment = Nokogiri::HTML5.fragment(html)
    images = fragment.css("img")
    relative = fragment.css("a[href]").select { |link| link["href"].match?(FOLDER_RELATIVE_HREF) }
    return html if images.empty? && relative.empty?

    images.each do |image|
      holder = image.parent
      image.remove
      holder.remove if holder.name == "a" && holder.children.empty?
    end
    relative.each { |link| link["href"] = "./#{link["href"]}" }
    fragment.to_html
  end

  # =============================================================================
  # CLASS SELECTION
  # =============================================================================

  def classes_for(field_type, has_errors, custom_width = nil, has_icon: false)
    field_type = :input unless FIELD_CLASSES.key?(field_type)
    base_classes = FIELD_CLASSES.dig(field_type, has_errors ? :error : :normal)

    # Add icon padding class (CSS override since DaisyUI handles padding internally)
    base_classes = "#{base_classes} #{ICON_PADDING_CLASS}" if has_icon

    custom_width ? base_classes.gsub(DEFAULT_WIDTH_CLASSES, custom_width) : base_classes
  end

  # =============================================================================
  # FIELD BUILDING
  # =============================================================================

  def build_field(attribute, options = {})
    field_type = options.delete(:field_type)
    field_opts = extract_field_options(options, attribute)

    # Use replace_class to completely override default styling (e.g., for dark theme contexts)
    options[:class] = if field_opts[:replace_class] && options[:class].present?
                        options[:class]
                      else
                        merge_classes(
                          classes_for(field_type || :input, field_opts[:has_errors], field_opts[:width], has_icon: field_opts[:icon].present?),
                          options[:class]
                        )
                      end

    options[:required] = true if field_opts[:required]

    # Add character counter if show_counter is true and maxlength is present
    if field_opts[:show_counter] && options[:maxlength]
      options[:data] ||= {}
      options[:data][:controller] = merge_data_controllers(options[:data][:controller], "input-counter")
      options[:data][:input_counter_css_value] = "text-sm ms-2 text-body"
    end

    # Add aria-describedby for help text or errors (WCAG 1.3.1), and aria-invalid
    # for errors (WCAG 3.3.1): the red border alone says nothing to a screen reader.
    if field_opts[:help_text] || field_opts[:has_errors]
      options[:aria] ||= {}
      options[:aria][:describedby] = "#{sanitized_field_id(attribute)}_hint"
      options[:aria][:invalid] = true if field_opts[:has_errors]
    end

    field_tag = yield(options)

    # Wrap field with icon if specified
    field_tag = wrap_with_icon(field_tag, field_opts) if field_opts[:icon].present?

    return field_tag if field_opts[:skip_wrapper]

    case field_opts[:layout]
    when :horizontal then build_horizontal_field(attribute, field_tag, field_opts)
    when :auto then build_auto_field(attribute, field_tag, field_opts)
    else build_vertical_field(attribute, field_tag, field_opts)
    end
  end

  def build_vertical_field(attribute, field_tag, field_opts)
    wrapper_options = build_wrapper_options(field_opts, WRAPPER_CLASSES)

    @template.tag.div(**wrapper_options) do
      safe_join([
                  build_label(attribute, field_opts, :label),
                  field_tag,
                  field_suffix(attribute, field_opts)
                ])
    end
  end

  def build_horizontal_field(attribute, field_tag, field_opts)
    wrapper_options = build_wrapper_options(field_opts, HORIZONTAL_WRAPPER_CLASSES)

    @template.tag.div(**wrapper_options) do
      safe_join([
                  build_label(attribute, field_opts, :horizontal_label),
                  @template.tag.div(class: HORIZONTAL_INPUT_CONTAINER_CLASSES) do
                    safe_join([field_tag, field_suffix(attribute, field_opts)])
                  end
                ])
    end
  end

  def build_auto_field(attribute, field_tag, field_opts)
    wrapper_options = build_wrapper_options(field_opts, AUTO_WRAPPER_CLASSES)

    @template.tag.div(**wrapper_options) do
      safe_join([
                  build_label(attribute, field_opts, :auto_label),
                  @template.tag.div(class: AUTO_INPUT_CONTAINER_CLASSES) do
                    safe_join([field_tag, field_suffix(attribute, field_opts)])
                  end
                ])
    end
  end

  # The mark that says a field has to be answered. A radio group is named by a
  # legend rather than a label, so this is built on its own and put wherever the
  # name is, instead of only being appended by build_label.
  def required_marker(field_opts)
    if field_opts[:required_label] == ""
      @template.fa_icon("asterisk", :solid, class: "text-error", start: 2)
    else
      @template.tag.span("(required)", class: "ml-2 text-xs text-error")
    end
  end

  # A radio group's name, marked the same way a required field's label is.
  def group_label_text(field_opts)
    return field_opts[:label_text] unless field_opts[:required]

    safe_join([field_opts[:label_text], required_marker(field_opts)])
  end

  def build_label(attribute, field_opts, label_type)
    return "".html_safe if field_opts[:hide_label] || field_opts[:label_text].nil?

    label_parts = [field_opts[:label_text]]
    label_parts << required_marker(field_opts) if field_opts[:required]

    # Add tooltip icon for help text in tooltip mode
    if field_opts[:help_mode] == :tooltip && field_opts[:help_text]
      hint_id = "#{sanitized_field_id(attribute)}_hint"
      tooltip_icon = @template.tag.span(
        class: "inline-block ms-1 text-stone-muted hover:text-primary cursor-help",
        title: field_opts[:help_text]
      ) do
        @template.fa_icon("circle-info", :solid, class: "text-sm")
      end
      label_parts << tooltip_icon
    end

    label_content = safe_join(label_parts)
    label(attribute, label_content, class: classes_for(label_type, field_opts[:has_errors]))
  end

  def build_wrapper_options(field_opts, default_class)
    wrapper_class = field_opts[:wrapper_class] || default_class
    wrapper_class = "#{wrapper_class} hidden" if field_opts[:hidden]

    { class: wrapper_class }.tap do |opts|
      opts[:id] = field_opts[:wrapper_id] if field_opts[:wrapper_id]
    end
  end

  def field_suffix(attribute, field_opts)
    hint_id = "#{sanitized_field_id(attribute)}_hint"

    if field_opts[:has_errors]
      error_message(attribute, hint_id)
    elsif field_opts[:help_text] && field_opts[:help_mode] != :tooltip
      # Only show inline help text if not in tooltip mode
      help_text_tag(field_opts[:help_text], hint_id)
    else
      "".html_safe
    end
  end

  # =============================================================================
  # TOGGLE FIELD BUILDING (CHECKBOXES & RADIOS)
  # =============================================================================

  def build_toggle_field(field_type, attribute, input_tag, field_opts, inline_label: nil, tag_value: nil)
    case field_opts[:layout]
    when :horizontal
      build_horizontal_toggle(field_type, attribute, input_tag, field_opts, inline_label, tag_value)
    when :auto
      build_auto_toggle(field_type, attribute, input_tag, field_opts, inline_label, tag_value)
    else
      build_vertical_toggle(field_type, attribute, input_tag, field_opts, inline_label, tag_value)
    end
  end

  def build_vertical_toggle(field_type, attribute, input_tag, field_opts, inline_label, tag_value)
    wrapper_class = field_opts[:wrapper_class] || TOGGLE_FIELD_WRAPPER_CLASSES

    field_html = case field_type
                 when :checkbox then build_checkbox_content(attribute, input_tag, field_opts, inline_label)
                 else build_radio_content(attribute, input_tag, field_opts, tag_value)
                 end

    return field_html if field_opts[:skip_wrapper]

    @template.tag.div(class: wrapper_class) do
      safe_join([field_html, field_suffix(attribute, field_opts)])
    end
  end

  def build_horizontal_toggle(field_type, attribute, input_tag, field_opts, inline_label, tag_value)
    wrapper_class = field_opts[:wrapper_class] || HORIZONTAL_WRAPPER_CLASSES

    @template.tag.div(class: wrapper_class) do
      label_html = if field_opts[:label_text].present? && field_type == :checkbox
                     @template.tag.span(field_opts[:label_text],
                                        class: "#{classes_for(:horizontal_label, field_opts[:has_errors])} pt-0")
                   else
                     "".html_safe
                   end

      content = case field_type
                when :checkbox then build_checkbox_content(attribute, input_tag, field_opts.merge(label_text: nil), inline_label)
                else build_radio_content(attribute, input_tag, field_opts, tag_value)
                end

      safe_join([
                  label_html,
                  @template.tag.div(class: HORIZONTAL_INPUT_CONTAINER_CLASSES) do
                    safe_join([content, field_suffix(attribute, field_opts)])
                  end
                ])
    end
  end

  def build_auto_toggle(field_type, attribute, input_tag, field_opts, inline_label, tag_value)
    wrapper_class = field_opts[:wrapper_class] || AUTO_WRAPPER_CLASSES

    @template.tag.div(class: wrapper_class) do
      label_html = if field_opts[:label_text].present? && field_type == :checkbox
                     @template.tag.span(field_opts[:label_text],
                                        class: "#{classes_for(:auto_label, field_opts[:has_errors])} lg:pt-0")
                   else
                     "".html_safe
                   end

      content = case field_type
                when :checkbox then build_checkbox_content(attribute, input_tag, field_opts.merge(label_text: nil), inline_label)
                else build_radio_content(attribute, input_tag, field_opts, tag_value)
                end

      safe_join([
                  label_html,
                  @template.tag.div(class: AUTO_INPUT_CONTAINER_CLASSES) do
                    safe_join([content, field_suffix(attribute, field_opts)])
                  end
                ])
    end
  end

  def build_checkbox_content(attribute, checkbox_tag, field_opts, inline_label)
    label_text = field_opts[:label_text] || inline_label
    label_class = classes_for(:toggle_label, field_opts[:has_errors])

    @template.tag.div(class: TOGGLE_WRAPPER_CLASSES) do
      # min-h-9: this label is the hit area -- it wraps both the box and its text.
      @template.tag.label(for: sanitized_field_id(attribute), class: "inline-flex items-center min-h-9 cursor-pointer") do
        safe_join([
                    checkbox_tag,
                    label_text ? @template.tag.span(label_text, class: label_class) : "".html_safe
                  ])
      end
    end
  end

  def build_radio_content(attribute, radio_tag, field_opts, tag_value)
    value_slug = tag_value.to_s.parameterize(separator: "_")
    radio_id = "#{sanitized_object_name}_#{attribute}_#{value_slug}"
    label_class = classes_for(:toggle_label, field_opts[:has_errors])

    @template.tag.div(class: TOGGLE_WRAPPER_CLASSES) do
      safe_join([
                  radio_tag,
                  @template.tag.label(field_opts[:label_text], for: radio_id, class: label_class)
                ])
    end
  end

  # =============================================================================
  # COLLECTION RADIO BUTTONS
  # =============================================================================

  def build_vertical_collection_radio_buttons(attribute, collection, value_method, text_method,
                                              options, html_options, field_opts)
    wrapper_class = field_opts[:wrapper_class] || WRAPPER_CLASSES

    @template.tag.fieldset(class: wrapper_class, role: "radiogroup") do
      legend = field_opts[:label_text] ?
                 @template.tag.legend(group_label_text(field_opts), class: classes_for(:label, field_opts[:has_errors])) :
                 "".html_safe

      buttons = build_collection_radio_buttons(attribute, collection, value_method, text_method,
                                               options, html_options, field_opts[:has_errors], field_opts[:layout])

      safe_join([legend, buttons, field_suffix(attribute, field_opts)])
    end
  end

  def build_horizontal_collection_radio_buttons(attribute, collection, value_method, text_method,
                                                options, html_options, field_opts)
    buttons = build_collection_radio_buttons(attribute, collection, value_method, text_method,
                                             options, html_options, field_opts[:has_errors], field_opts[:layout])

    if field_opts[:label_position] == :stacked
      # Stacked: legend on its own line, radios on next line.
      # A fieldset/legend gives the radio group an accessible name so screen
      # readers announce the group label with each option.
      wrapper_class = field_opts[:wrapper_class] || WRAPPER_CLASSES

      @template.tag.fieldset(class: wrapper_class, role: "radiogroup") do
        legend_html = field_opts[:label_text] ?
                        @template.tag.legend(group_label_text(field_opts), class: classes_for(:label, field_opts[:has_errors])) :
                        "".html_safe

        safe_join([legend_html, buttons, field_suffix(attribute, field_opts)])
      end
    else
      # Inline: label beside radio group (default behavior)
      wrapper_class = field_opts[:wrapper_class] || HORIZONTAL_WRAPPER_CLASSES

      @template.tag.div(class: wrapper_class) do
        label_html = field_opts[:label_text] ?
                       @template.tag.span(group_label_text(field_opts), class: classes_for(:horizontal_label, field_opts[:has_errors])) :
                       "".html_safe

        safe_join([
                    label_html,
                    @template.tag.div(class: HORIZONTAL_INPUT_CONTAINER_CLASSES) do
                      safe_join([buttons, field_suffix(attribute, field_opts)])
                    end
                  ])
      end
    end
  end

  def build_auto_collection_radio_buttons(attribute, collection, value_method, text_method,
                                          options, html_options, field_opts)
    buttons = build_collection_radio_buttons(attribute, collection, value_method, text_method,
                                             options, html_options, field_opts[:has_errors], field_opts[:layout])

    if field_opts[:label_position] == :stacked
      # Stacked: legend on its own line, radios on next line.
      # A fieldset/legend gives the radio group an accessible name so screen
      # readers announce the group label with each option.
      wrapper_class = field_opts[:wrapper_class] || WRAPPER_CLASSES

      @template.tag.fieldset(class: wrapper_class, role: "radiogroup") do
        legend_html = field_opts[:label_text] ?
                        @template.tag.legend(group_label_text(field_opts), class: classes_for(:label, field_opts[:has_errors])) :
                        "".html_safe

        safe_join([legend_html, buttons, field_suffix(attribute, field_opts)])
      end
    else
      # Inline: label beside radio group (default behavior)
      wrapper_class = field_opts[:wrapper_class] || AUTO_WRAPPER_CLASSES

      @template.tag.div(class: wrapper_class) do
        label_html = field_opts[:label_text] ?
                       @template.tag.span(group_label_text(field_opts), class: classes_for(:auto_label, field_opts[:has_errors])) :
                       "".html_safe

        safe_join([
                    label_html,
                    @template.tag.div(class: AUTO_INPUT_CONTAINER_CLASSES) do
                      safe_join([buttons, field_suffix(attribute, field_opts)])
                    end
                  ])
      end
    end
  end

  def build_collection_radio_buttons(attribute, collection, value_method, text_method,
                                     options, html_options, has_errors, layout = :vertical)
    wrapper_class = case layout
                    when :horizontal then "columns-1 sm:columns-2 lg:columns-3 xl:columns-4 gap-x-4"
                    when :auto then "space-y-1 lg:columns-2 xl:columns-3 lg:gap-x-4 lg:space-y-0"
                    else "space-y-1"
                    end
    item_class = "#{TOGGLE_WRAPPER_CLASSES} break-inside-avoid"

    @template.tag.div(class: wrapper_class) do
      @template.collection_radio_buttons(
        object_name, attribute, collection, value_method, text_method,
        options.merge(object:), html_options
      ) do |b|
        @template.tag.div(class: item_class) do
          safe_join([
                      b.radio_button(class: classes_for(:radio, has_errors), aria: { invalid: (true if has_errors) }),
                      b.label(class: classes_for(:toggle_label, has_errors))
                    ])
        end
      end
    end
  end

  # =============================================================================
  # ERROR & HELP TEXT
  # =============================================================================

  def object_has_error?(attribute)
    object&.respond_to?(:errors) && object.errors[attribute].any?
  end

  # errors.format prints a message alone, so most messages here are whole
  # sentences, and those join with a space: ", " would read "...uses that
  # slug., The slug may hold...". Fragments still join with a comma.
  def error_message(attribute, hint_id = nil)
    return "".html_safe unless object_has_error?(attribute)

    errors = object.errors[attribute]
    messages = errors.join(errors.all? { |message| message.end_with?(".", "!", "?") } ? " " : ", ")

    @template.tag.div(class: ERROR_TEXT_CLASSES, id: hint_id, role: "alert") do
      safe_join([
                  fa_icon("circle-exclamation", :solid, class: ERROR_ICON_TEXT_CLASSES),
                  @template.tag.span(messages)
                ])
    end
  end

  def help_text_tag(text, hint_id = nil)
    return "".html_safe unless text

    @template.tag.div(text, class: HELP_TEXT_CLASSES, id: hint_id)
  end

  # Public for the view that has to draw one of these itself: the help and error
  # lines of a fieldset, around a group of controls the builder does not label.
  public :error_message, :help_text_tag

  # =============================================================================
  # UTILITY METHODS
  # =============================================================================

  def merge_classes(*classes) = classes.compact_blank.join(" ")

  def sanitized_object_name = @object_name.to_s.tr("[]", "_")

  # Matches how Rails builds the id it puts on the field itself: with no model
  # -- a filter_bar opening its own scopeless GET form -- Rails drops the empty
  # object name, so prefixing an underscore unconditionally aimed every label's
  # `for` and every hint's `aria-describedby` at an id that does not exist. A
  # present-but-unmatched `for` beats the descendant control, so those labels
  # labelled nothing: the text was not clickable and screen readers announced
  # an unnamed field.
  def sanitized_field_id(attribute) = [sanitized_object_name.presence, attribute].compact.join("_")

  def safe_join(array) = @template.safe_join(array)

  # =============================================================================
  # ICON PREFIX
  # =============================================================================

  # The icon comes AFTER the field in the markup. daisyUI's .input is
  # position: relative with an opaque background, and two positioned siblings
  # paint in document order, so an icon placed before the input sat under it:
  # invisible behind a solid field, a quarter-strength ghost behind the login's
  # 85% one. Order is all it takes; the span is aria-hidden and takes no focus,
  # so nothing else reads it.
  def wrap_with_icon(field_tag, field_opts)
    icon_class = field_opts[:icon_class] || (field_opts[:has_errors] ? ICON_ERROR_CLASSES : ICON_CLASSES)

    @template.tag.div(class: ICON_CONTAINER_CLASSES) do
      safe_join([
                  field_tag,
                  @template.tag.span(class: icon_class, aria: { hidden: true }) do
                    fa_icon(field_opts[:icon], field_opts[:icon_type])
                  end
                ])
    end
  end

  # =============================================================================
  # VANILLA CALENDAR INTEGRATION
  # =============================================================================

  def add_vanilla_calendar_attributes(opts, calendar_options)
    opts[:data] ||= {}
    opts[:data][:controller] = [opts.dig(:data, :controller), "vanilla-calendar"].compact_blank.join(" ")
    opts[:data]["vanilla-calendar-options-value"] = VANILLA_CALENDAR_DEFAULTS.merge(calendar_options.presence || {}).to_json
  end
end

# =============================================================================
# FORM HELPER MODULE
# =============================================================================

module FormHelper
  # Creates a row for multiple fields side by side
  #
  # @example Two fields side by side
  #   form_row do
  #     f.text_field :first_name, label: "First"
  #     f.text_field :last_name, label: "Last"
  #   end
  #
  def form_row(options = {}, &block)
    options[:class] = class_names("flex flex-col lg:flex-row gap-3 mb-1", options[:class])
    tag.div(**options, &block)
  end

  # Displays form errors in a callout box
  #
  # @param model [ActiveRecord::Base] The model with errors
  # @return [String] HTML for the error summary
  #
  def form_error_summary(model)
    return "".html_safe unless model.respond_to?(:errors) && model.errors.any?

    error_word = model.errors.one? ? "error" : "errors"

    error_list = tag.ul(class: "mt-2 space-y-1") do
      safe_join(
        model.errors.full_messages.map do |msg|
          tag.li(class: "flex items-start gap-2") do
            safe_join([
                        tag.span("&bullet;".html_safe, class: AppFormBuilder::ERROR_ICON_TEXT_CLASSES, aria: { hidden: true }),
                        tag.span(msg)
                      ])
          end
        end
      )
    end

    ui_callout_box :error, id: "form-error-summary", tabindex: "-1" do
      safe_join([tag.div("Please fix the following #{error_word}:", class: "font-semibold"), error_list])
    end
  end

  # Data attributes for input character counter
  #
  # @param target_id [String, nil] Optional target element ID
  # @return [Hash] Data attributes for the counter controller
  #
  def input_counter_data(target_id = nil)
    {
      controller: "input-counter",
      input_counter_css_value: "text-sm ms-2 text-body"
    }.tap do |data|
      data[:input_counter_target_id_value] = target_id if target_id
    end
  end
end
