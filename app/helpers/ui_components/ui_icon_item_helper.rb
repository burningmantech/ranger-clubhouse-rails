# frozen_string_literal: true

module UiComponents
  # Icon List Item Helper
  # One line of an icon list: an icon, and whatever the block says beside it.
  # A helper rather than a partial because the content is free-form -- these
  # lines hold sentences, <strong> runs and links, not a label local.
  #
  # Usage:
  #   <ul class="space-y-2">
  #     <%= ui_icon_item "circle-check", :solid, tone: "icon-success" do %>
  #       Can be transferred to anyone
  #     <% end %>
  #   </ul>
  #
  # `tone` is a whole class name, never a fragment, so Tailwind can read it:
  # icon-success, icon-error, text-stone-subtle. Leave it off and the icon
  # takes the surrounding ink.
  module UiIconItemHelper
    ITEM_CLASSES = "flex items-start gap-2"
    # items-start puts the icon on the first line of a label that wraps; the
    # 2px nudge then sits it on that line's optical centre rather than its box
    # top. Every icon list in the app uses this pair.
    ICON_CLASSES = "mt-0.5 shrink-0"

    def ui_icon_item(icon, icon_type = :solid, tone: nil, &block)
      raise ArgumentError, "ui_icon_item requires a block" unless block

      tag.li(class: ITEM_CLASSES) do
        safe_join([fa_icon(icon, icon_type, class: class_names(tone, ICON_CLASSES)),
                   tag.span(capture(&block))])
      end
    end
  end
end
