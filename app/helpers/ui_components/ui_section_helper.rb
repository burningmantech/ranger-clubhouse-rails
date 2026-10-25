# frozen_string_literal: true

module UiComponents
  module UiSectionHelper
    BOX_BASE = "box box-default mb-4"
    SECTION_TITLE_BASE = "px-4 pt-2 mb-1 heading-section text-heading-primary"
    BODY_BASE = "text-body rounded-xl px-4 pb-2"
    SUBHEADING_BASE = "heading-title text-heading mt-4 first:mt-0 mb-2"

    def ui_section(title_or_options = nil, options = {}, &block)
      if title_or_options.is_a?(Hash)
        options = title_or_options
        title = nil
      else
        title = title_or_options
      end

      html_attrs = build_section_html_attrs(options)
      body_class = build_body_class(options)
      title_options = options.slice(:badge, :badge_color)

      tag.section(**html_attrs) do
        safe_join([
                    render_section_header(title, options, title_options),
                    tag.div(capture(&block), class: body_class)
                  ].compact)
      end
    end

    def ui_section_title(title = nil, options = {}, &)
      title = capture(&) if block_given?

      tag.div(title_with_badge(title, options), **build_title_attrs(options))
    end

    # A heading one level under a section title: a group of rows, a month of
    # sessions. An <h3>, so a screen reader can step through the groups; the
    # block form takes a badge or a muted span beside the title.
    def ui_subheading(title = nil, &)
      title = capture(&) if block_given?

      tag.h3(title, class: SUBHEADING_BASE)
    end

    private

    def build_section_html_attrs(options)
      html = options.fetch(:html, {}).dup
      html[:class] = class_names(BOX_BASE, options[:class])
      html[:id] = options[:id] if options[:id]
      html[:style] = options[:style] if options[:style]
      html
    end

    def build_body_class(options)
      has_border = options.fetch(:border, true)
      class_names(BODY_BASE, options[:body_class], "px-4 pb-1": has_border)
    end

    def build_title_attrs(options)
      {
        class: class_names(SECTION_TITLE_BASE, options[:class]),
        role: "heading",
        "aria-level": "2"
      }
    end

    def render_section_header(title, options, title_options)
      return "".html_safe if title.blank?

      icon_html = build_icon_html(options)
      title_html = ui_section_title(safe_join([icon_html, title]), title_options)

      if options[:edit_link] || options[:link]
        render_title_with_edit(title_html, title, options[:edit_link] || options[:link], is_edit: options[:edit_link].present?)
      elsif options[:action]
        render_title_with_action(title_html, title, options[:action])
      else
        title_html
      end
    end

    def build_icon_html(options)
      options[:icon] ? fa_icon(options[:icon], options.fetch(:icon_type, "regular"), end: 2) : ""
    end

    def render_title_with_edit(title_html, title, edit_or_link, is_edit: false)
      if is_edit
        # The section title is already title case, so it carries into the
        # accessible name unchanged -- downcasing it here spelled the same
        # control two ways depending on where a reader met it.
        label = "Edit #{title}"
        link = edit_link(edit_or_link,
                         class: "whitespace-nowrap",
                         aria: { label: },
                         title: label)
      else
        link = edit_or_link
      end

      tag.div(class: "flex flex-col lg:flex-row items-center justify-between") do
        safe_join([
                    title_html,
                    tag.div(link, class: "px-4 py-2")
                  ])
      end
    end

    def render_title_with_action(title_html, title, actions)
      # Below lg the row stacks, so the action slot fills the width and its
      # buttons' own "w-full lg:w-auto" can land. Centring here would shrink-wrap
      # the slot and strand full-width buttons inside a content-width box.
      tag.div(class: "flex flex-col lg:flex-row lg:items-center justify-between") do
        safe_join([
                    title_html,
                    tag.div(render(partial: actions[:partial], locals: actions[:locals]),
                            class: "w-full px-4 py-2 lg:w-auto")
                  ])
      end
    end

    # The badge sits beside the title, as a subheading's does, not at the far
    # edge of the bar: a count belongs to the words it counts. An empty list
    # reads "none" rather than a bare zero.
    def title_with_badge(title, options)
      badge = options[:badge]
      return title unless badge

      badge = "none" if badge == "0"
      safe_join([title, " ", ui_badge(badge, options[:badge_color] || :secondary, size: "base")])
    end
  end
end
