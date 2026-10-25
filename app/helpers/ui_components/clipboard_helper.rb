# frozen_string_literal: true

module UiComponents
  module ClipboardHelper
    def clipboard_button(text, options = {}, &block)
      content = capture(&block)
      # The visible glyph is ~16px, well under the 36px touch-target floor. The
      # ::before pad grows the hit area to 44px without taking any layout space,
      # so the icon still sits inline beside its label everywhere it is used.
      #
      # A <button> rather than a bare <a>: this was an anchor with no href, which
      # no keyboard can reach and no screen reader announces. The icon is
      # aria-hidden, so :label is the control's only accessible name -- pass one
      # wherever a page shows more than one copy control.
      #
      # A press is answered on the button itself: the controller opens a Copied
      # tip over it for a moment (buttons.css). The tip centres on the button's
      # box, so that box is the glyph and nothing else -- the gap before it is
      # the button's margin, not the icon's, and beside a tall block the button
      # keeps its own height.
      copy_button = tag.button(type: "button",
                               aria: { label: options[:label] || "Copy to clipboard" },
                               class: class_names("no-decoration relative inline-flex items-center " \
                                                  "justify-center align-middle " \
                                                  "before:absolute before:-inset-3.5 before:content-['']",
                                                  "ms-2": !options[:use_flex]),
                          data: {
        controller: "copy-to-clipboard", action: "copy-to-clipboard#copy",
        copy_to_clipboard_success_class: "btn-copy-success", copy_to_clipboard_content_value: text
      }) do
        fa_icon("copy", :regular)
      end
      if options[:use_flex]
        tag.div(class: "flex flex-row items-center") do
          safe_join [tag.div(content), copy_button]
        end
      else
        safe_join [content, copy_button]
      end
    end
  end
end
