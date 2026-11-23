# frozen_string_literal: true

module UiComponents
  module UiLabelValueHelper
    VARIANT_CLASSES = {
      default: nil,
      success: "text-success",
      warning: "text-warning",
      error: "text-error",
      primary: "text-primary",
      info: "text-info"
    }.freeze

    SIZE_CLASSES = {
      sm: "text-sm",
      base: "text-base"
    }.freeze

    # How the rows are laid out. Each is a modifier in components/label-value.css.
    LAYOUT_CLASSES = {
      default: nil,
      fitted: "ui-label-value-fitted"
    }.freeze

    # Renders a semantic label-value list using CSS Grid on <dl>.
    # dt/dd are direct children — no wrapper divs.
    #
    # ==== Options
    # * <tt>label_width</tt> - CSS value for label column width on desktop (e.g., "6rem", "150px", "max-content").
    #   Sets the --label-width custom property. Defaults to "auto". The default layout only.
    # * <tt>size</tt> - Text size: :base (default) or :sm
    # * <tt>layout</tt> - :default puts the label above its value below lg and beside it from lg up.
    #   :fitted keeps them side by side at every width, the label column as wide as its longest label:
    #   a few short labels in a narrow column.
    # * Additional HTML attributes are passed through to the <dl> element.
    #
    # ==== Example
    #   <%= ui_label_value label_width: "6rem" do |list| %>
    #     <% list.row "Email", @person.email %>
    #     <% list.row "Status", "Suspended", variant: :error %>
    #     <% list.row "Address" do %>
    #       Multi-line content here
    #     <% end %>
    #   <% end %>
    def ui_label_value(label_width: nil, size: :base, layout: :default, **options, &block)
      unless LAYOUT_CLASSES.key?(layout)
        raise ArgumentError, "ui_label_value layout: must be one of #{LAYOUT_CLASSES.keys.inspect}, got #{layout.inspect}"
      end
      if label_width && layout != :default
        raise ArgumentError, "ui_label_value label_width: sets the default layout's column; layout: #{layout.inspect} sizes its own"
      end

      builder = LabelValueBuilder.new(self, size:)
      capture(builder, &block)

      html_attrs = options.except(:class, :style)
      html_attrs[:class] = class_names("ui-label-value", LAYOUT_CLASSES.fetch(layout), SIZE_CLASSES[size], options[:class])
      html_attrs[:style] = build_label_value_style(label_width, options[:style])

      tag.dl(**html_attrs) { builder.render }
    end

    private

    def build_label_value_style(label_width, extra_style)
      parts = []
      parts << "--label-width: #{label_width}" if label_width
      parts << extra_style if extra_style.present?
      parts.join("; ").presence
    end

    class LabelValueBuilder
      def initialize(template, size:)
        @template = template
        @size = size
        @rows = []
      end

      def row(label, value = nil, variant: :default, **options, &block)
        value_content = block ? @template.capture(&block) : value
        @rows << { label:, value: value_content, variant:, options: }
      end

      def render
        @template.safe_join(@rows.map { |row_data| render_row(row_data) })
      end

      private

      def render_row(row_data)
        variant_class = VARIANT_CLASSES.fetch(row_data[:variant], nil)
        value_classes = ["text-body", variant_class].compact.join(" ")
        dt_options = row_data[:options].delete(:label_class) || {}
        dd_options = row_data[:options].merge(class: value_classes)

        @template.safe_join([
          @template.tag.dt(row_data[:label], **dt_options),
          @template.tag.dd(row_data[:value], **dd_options)
        ])
      end
    end
  end
end
