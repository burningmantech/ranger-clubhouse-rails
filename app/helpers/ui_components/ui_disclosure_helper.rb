# frozen_string_literal: true

module UiComponents
  # Renders native details/summary disclosure markup as a plain disclosure —
  # either a bare inline expander (default) or a boxed card with a rotating
  # chevron (variant: :card). For the DaisyUI collapse-arrow accordion
  # styling, use ui_accordion instead.
  module UiDisclosureHelper
    # The 36px touch floor. No flex: the summary must stay display: list-item,
    # which is what draws the disclosure triangle -- its only affordance.
    INLINE_SUMMARY_BASE = "cursor-pointer min-h-9 py-2"

    # disclosure-card is a hook, not a style: components/disclosure.css reads it
    # to leave a closed explanation card off a printed page.
    CARD_WRAPPER_BASE = "disclosure-card rounded-base border border-line"
    CARD_SUMMARY_BASE = "cursor-pointer list-none [&::-webkit-details-marker]:hidden px-4 py-3"
    CARD_SUMMARY_LAYOUT = "flex items-center justify-between gap-3"
    CARD_TITLE_BASE = "text-base text-heading"
    CARD_SUBTITLE_BASE = "text-sm text-stone-muted"
    CARD_CHEVRON = "shrink-0 text-stone-muted transition-transform group-open:rotate-180"
    CARD_CONTENT_BASE = "border-t border-line px-4 pb-4 pt-3"

    def ui_disclosure(summary_content, options = {}, &block)
      raise ArgumentError, "ui_disclosure requires summary content" if summary_content.nil?
      raise ArgumentError, "ui_disclosure requires a block" unless block

      options = options.dup
      variant = options.delete(:variant) || :inline
      subtitle = options.delete(:subtitle)
      raise ArgumentError, "ui_disclosure subtitle: requires variant: :card" if subtitle && variant != :card

      case variant
      when :inline then inline_disclosure(summary_content, options, &block)
      when :card then card_disclosure(summary_content, subtitle, options, &block)
      else
        raise ArgumentError, "ui_disclosure unknown variant: #{variant.inspect}"
      end
    end

    private

    def inline_disclosure(summary_content, options, &block)
      summary_html = disclosure_part_options(options, :summary, INLINE_SUMMARY_BASE)
      content_html = disclosure_part_options(options, :content, nil)

      tag.details(**disclosure_details_options(options)) do
        safe_join([
                    tag.summary(summary_content, **summary_html),
                    tag.div(capture(&block), **content_html)
                  ])
      end
    end

    def card_disclosure(summary_content, subtitle, options, &block)
      wrapper_class = class_names(CARD_WRAPPER_BASE, options.delete(:class))
      summary_html = disclosure_part_options(options, :summary, CARD_SUMMARY_BASE)
      content_html = disclosure_part_options(options, :content, CARD_CONTENT_BASE)
      details_options = disclosure_details_options(options)
      details_options[:class] = class_names("group", details_options[:class])

      tag.div(class: wrapper_class) do
        tag.details(**details_options) do
          safe_join([
                      tag.summary(**summary_html) do
                        tag.div(class: CARD_SUMMARY_LAYOUT) do
                          safe_join([
                                      card_disclosure_heading(summary_content, subtitle),
                                      tag.span(fa_icon("chevron-down", :solid), class: CARD_CHEVRON)
                                    ])
                        end
                      end,
                      tag.div(capture(&block), **content_html)
                    ])
        end
      end
    end

    # Plain-string titles get the bold treatment; rich HTML summaries control
    # their own weight (e.g. selectively bolding one span).
    def card_disclosure_heading(summary_content, subtitle)
      title_class = class_names(CARD_TITLE_BASE, "font-semibold" => !summary_content.html_safe?)
      title = tag.div(summary_content, class: title_class)
      return title unless subtitle

      tag.div(safe_join([title, tag.div(subtitle, class: CARD_SUBTITLE_BASE)]))
    end

    def disclosure_part_options(options, part, base_class)
      part_html = options.delete(:"#{part}_html")&.dup || {}
      part_html[:class] = class_names(base_class, part_html[:class], options.delete(:"#{part}_class")).presence
      part_html
    end

    def disclosure_details_options(options)
      options[:open] = true if options.delete(:open)
      options
    end
  end
end
