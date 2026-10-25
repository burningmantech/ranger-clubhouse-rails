# frozen_string_literal: true

# Helpers that return markup -- datetime_format returns a <span> -- have to be
# rendered, not dropped into a string. Interpolated, the markup is escaped and
# the reader sees the tag instead of the time.
#
# A confirmation dialog is escaped inside its attribute on purpose, so the page
# legitimately carries escaped markup there. Counting the layers tells the two
# apart, and the check reads both places:
#
#   the dialog's own markup   escaped once   ->  &lt;span
#   a helper interpolated                        (the confirmation escapes it
#   into a message            escaped twice  ->  &amp;lt;span   again)
#
# So a single layer inside a confirmation is expected and a double layer is the
# mistake, while anywhere else in the page a single layer is already the
# mistake.
module EscapedMarkupTestHelper
  CONFIRM_ATTRIBUTES = /data-(?:turbo-confirm|download-confirm-message-value)="[^"]*"/

  def assert_no_escaped_markup(tag_name = "span")
    body = response.body

    assert_not_includes body.gsub(CONFIRM_ATTRIBUTES, ""), "&lt;#{tag_name}",
                        "a helper that returns markup was interpolated instead of rendered"

    body.scan(CONFIRM_ATTRIBUTES) do |confirmation|
      assert_not_includes confirmation, "&amp;lt;#{tag_name}",
                          "a helper that returns markup was interpolated into a confirmation"
    end
  end
end
