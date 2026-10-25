# frozen_string_literal: true

module UiComponents
  # Renders native details/summary disclosure markup with the app's compact collapse styling.
  module UiAccordionHelper
    ACCORDION_BASE = "collapse collapse-arrow rounded-none border-0 bg-transparent"
    ACCORDION_SUMMARY_BASE = [
      "collapse-title",
      "flex",
      "items-center",
      "min-h-9",
      "px-0",
      "py-2",
      "pr-10",
      "text-left",
      "text-sm",
      "font-semibold",
      "text-heading"
    ].join(" ")
    ACCORDION_CONTENT_BASE = "collapse-content px-0 pt-2"

    def ui_accordion(summary_content, options = {}, &block)
      validate_accordion_args(summary_content, block)

      options = options.dup
      unstyled = options.delete(:unstyled)
      summary_html = options.delete(:summary_html)&.dup || {}
      content_html = options.delete(:content_html)&.dup || {}

      tag.details(**accordion_html_options(options, unstyled)) do
        safe_join([
                    tag.summary(summary_content,
                                **accordion_summary_options(summary_html,
                                                            options.delete(:summary_class),
                                                            unstyled)),
                    tag.div(capture(&block),
                            **accordion_content_options(content_html,
                                                        options.delete(:content_class),
                                                        unstyled))
                  ])
      end
    end

    private

    def validate_accordion_args(summary_content, block)
      raise ArgumentError, "ui_accordion requires summary content" if summary_content.nil?
      raise ArgumentError, "ui_accordion requires a block" unless block
    end

    def accordion_html_options(options, unstyled)
      options[:open] = true if options.delete(:open)
      options[:class] = class_names((ACCORDION_BASE unless unstyled), options[:class])
      options
    end

    def accordion_summary_options(summary_html, summary_class, unstyled)
      summary_html[:class] = class_names((ACCORDION_SUMMARY_BASE unless unstyled),
                                         summary_html[:class],
                                         summary_class)
      summary_html
    end

    def accordion_content_options(content_html, content_class, unstyled)
      content_html[:class] = class_names((ACCORDION_CONTENT_BASE unless unstyled),
                                         content_html[:class],
                                         content_class)
      content_html
    end
  end
end
