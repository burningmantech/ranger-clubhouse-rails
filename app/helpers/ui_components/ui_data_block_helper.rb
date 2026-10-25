# frozen_string_literal: true

module UiComponents
  # Data Block Helper
  # A scrollable, monospaced block for machine output: pretty-printed JSON, a
  # request payload, an exception backtrace. The three admin log helpers each
  # had their own copy of it.
  #
  # Usage:
  #   ui_data_block(pretty_json)
  #   ui_data_block(backtrace, max_height: "max-h-56")
  #
  # max_height is a whole class name the caller chooses, because how much of a
  # payload is worth showing before it scrolls is a per-page judgement. Leave it
  # off and the block grows to its content.
  module UiDataBlockHelper
    # overflow-auto rather than overflow-x-auto: a box with one axis auto and
    # the other visible computes both to auto anyway, so this is the same two
    # rules written once.
    BLOCK_CLASSES = "overflow-auto rounded-base border border-base-300 bg-base-100 p-3 shadow-inner"
    CONTENT_CLASSES = "font-mono text-sm leading-relaxed text-base-content whitespace-pre-wrap break-all"

    def ui_data_block(content, max_height: nil)
      tag.div(class: class_names(BLOCK_CLASSES, max_height)) do
        tag.pre(content, class: CONTENT_CLASSES)
      end
    end
  end
end
