# frozen_string_literal: true

# Driving a rich text editor (f.rich_text_area, Lexxy) in a system test. The
# helpers expect one editor on the page.
module RichTextEditorTestHelper
  # The area text is typed into. It is mounted a frame after the element
  # connects, so it is what to wait for.
  RICH_TEXT_EDITOR_CONTENT = "lexxy-editor .lexxy-editor__content"

  def wait_for_rich_text_editor
    assert_selector RICH_TEXT_EDITOR_CONTENT
    assert_selector "lexxy-toolbar button", minimum: 1
  end

  # Typed with real key presses, so the editor sees what a person's keyboard
  # would send. Bold is switched on from the toolbar first, as a person would.
  def type_into_rich_text_editor(text, bold: false)
    find(RICH_TEXT_EDITOR_CONTENT).click
    find("lexxy-toolbar button[name=bold]").click if bold
    find(RICH_TEXT_EDITOR_CONTENT).send_keys(text)
  end
end
