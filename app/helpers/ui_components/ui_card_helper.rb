# frozen_string_literal: true

module UiComponents
  # DaisyUI Card Helper
  # See: https://daisyui.com/components/card/
  module UiCardHelper
    CARD_TITLE = "text-heading text-center p-2"
    CARD_BODY = "text-body px-4"
    CARD_SECTION_TITLE = "mt-4 mb-2 font-semibold text-base text-heading"
    CARD_SECTION_BODY = "font-normal text-body"
    CARD_FOOTER = "flex items-center justify-center px-4 py-2"
    # rounded-t-base, not -lg: the card's own radius is 12px, and a 16px
    # image corner inside it left a sliver of card showing at each top corner.
    CARD_IMAGE = "rounded-t-base w-full object-cover"

    SHADOW_CLASSES = {
      xs: "shadow-xs",
      sm: "shadow-sm",
      md: "shadow-md",
      lg: "shadow-lg",
      xl: "shadow-xl",
      none: ""
    }.freeze

    TITLE_SIZE_CLASSES = {
      sm: "text-sm",
      md: "text-base",
      lg: "text-lg",
      xl: "text-xl"
    }.freeze

    # Options:
    #   :shadow - shadow size (:xs, :sm, :md, :lg, :xl, :none) - default: :xs
    #   :width - custom width in pixels
    #   :height - custom height in pixels
    #   :class - additional CSS classes
    def ui_card(options = {}, &block)
      shadow = options.delete(:shadow) || :xs
      shadow_class = SHADOW_CLASSES[shadow] || SHADOW_CLASSES[:xs]

      apply_dimension_styles(options)
      options[:class] = "card-standard #{shadow_class} #{options[:class]}".squish

      content_tag :div, options, &block
    end

    # Options:
    #   :image - path to image
    #   :alt - alt text for image
    #   :width - custom width in pixels
    #   :height - custom height in pixels
    #   :class - additional CSS classes
    def ui_card_image(options = {}, &block)
      image = options.delete(:image)
      raise ArgumentError, "No image and no block given" if image.nil? && !block_given?

      apply_dimension_styles(options)

      if image
        image_tag image, alt: options.delete(:alt) || "", loading: "lazy", class: CARD_IMAGE
      else
        yield
      end
    end

    def ui_card_body(options = {}, &block)
      options[:class] = "#{CARD_BODY} #{options[:class]}".squish
      content_tag :div, options, &block
    end

    # Options:
    #   :size - title size (:sm, :md, :lg, :xl) - default: :lg
    def ui_card_title(title, options = {}, &block)
      size = options.delete(:size) || :lg
      size_class = TITLE_SIZE_CLASSES[size.to_sym] || TITLE_SIZE_CLASSES[:lg]

      title_classes = "#{size_class} #{CARD_TITLE} #{options[:class]}".squish
      title_div = content_tag :div, title, class: title_classes

      return title_div unless block_given?

      extra_div = content_tag :p, class: "font-normal #{CARD_BODY}", &block
      safe_join([title_div, extra_div])
    end

    def ui_card_section(title, options = {}, &block)
      section_classes = "#{CARD_SECTION_TITLE} #{options[:class]}".squish
      section_title = content_tag :h6, title, class: section_classes
      section_text = content_tag :div, class: CARD_SECTION_BODY, &block
      safe_join([section_title, section_text])
    end

    def ui_card_footer(options = {}, &block)
      options[:class] = "#{CARD_FOOTER} #{options[:class]}".squish
      content_tag :div, options, &block
    end

    private

    # Extract width/height from options and apply as inline styles
    def apply_dimension_styles(options)
      styles = []
      styles << "width: #{options.delete(:width)}px;" if options[:width]
      styles << "height: #{options.delete(:height)}px;" if options[:height]
      options[:style] = styles.join(" ") if styles.any?
    end
  end
end
