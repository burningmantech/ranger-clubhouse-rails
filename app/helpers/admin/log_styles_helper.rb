# frozen_string_literal: true

module Admin
  # Shared text styling for the five admin log tables, which had written the
  # same two class strings out twenty-eight times between them.
  module LogStylesHelper
    # The ink a log cell and the text inside it share. Alignment and wrapping
    # stay with the caller: a cell in the Clubhouse 1 log aligns to the top
    # where the others centre, and only some columns refuse to wrap.
    LOG_TEXT = "text-sm leading-snug text-body"

    # The label above a block in an expanded detail row -- "Metadata", "Data",
    # "What was sent".
    LOG_DETAIL_HEADING = "mb-2 text-sm font-semibold text-heading"

    # Methods rather than the bare constants, because ERB cannot resolve an
    # included module's constant unqualified -- that raises
    # `uninitialized constant`, measured rather than assumed -- and
    # `Admin::LogStylesHelper::LOG_TEXT` at every call site is longer than the
    # string it replaces.
    def log_text_class(*extra) = class_names(LOG_TEXT, *extra)

    def log_heading_class = LOG_DETAIL_HEADING

    # One line of a log cell, the whole value in its title: a long path, event
    # or error type would otherwise wrap two or three times and push the other
    # columns out of reach.
    def log_truncated(text) = tag.div(text, class: log_text_class("truncate"), title: text)
  end
end
