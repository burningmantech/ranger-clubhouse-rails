# frozen_string_literal: true

require "application_system_test_case"

# Pages here are updated by morphing, which compares the page against the HTML
# the server sent. The rich text editor builds its own toolbar and holds the
# text being edited in the page, so morphing would throw both away unless the
# editor is left out of the comparison (see app/javascript/application.js).
#
# Only a browser can catch this: the server sends the right HTML either way.
class RichTextEditorTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper
  include RichTextEditorTestHelper

  # What Google Docs puts on the clipboard: one wrapper, and every run of text a
  # <span> whose style carries its colour, its weight and its slant.
  DOCS_RUN = "font-size:11pt;font-family:Arial,sans-serif;color:#000000;background-color:transparent;" \
             "font-variant:normal;text-decoration:none;vertical-align:baseline;white-space:pre-wrap;"
  FROM_GOOGLE_DOCS = %(<meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-9f8e">) +
                     %(<p dir="ltr" style="line-height:1.38;margin-top:0pt;margin-bottom:0pt;">) +
                     %(<span style="#{DOCS_RUN}font-weight:400;font-style:normal;">Shifts open </span>) +
                     %(<span style="#{DOCS_RUN}font-weight:700;font-style:normal;">Friday at noon</span>) +
                     %(<span style="#{DOCS_RUN}font-weight:400;font-style:italic;"> Pacific time</span></p></b>)

  setup do
    Document.delete_all

    @admin = person(:auditor_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    @existing = Document.create!(tag: "taken-tag", description: "A document",
                                 body: "<div>Text</div>",
                                 person_create_id: @admin.id, person_update_id: @admin.id)

    sign_in(@admin)
  end

  test "a rejected form keeps the text that was typed, and saves it once the field is fixed" do
    visit new_admin_document_path
    wait_for_rich_text_editor

    fill_in "Tag", with: @existing.tag
    fill_in "One-Line Description", with: "A document that will be refused"
    type_into_rich_text_editor("Text I typed", bold: true)

    click_on "Save Document"

    # The tag is already taken, so the form comes back with an error.
    assert_text "has already been taken"

    # The point of the test: the editor survived the round trip.
    assert_selector "lexxy-toolbar button", minimum: 1
    assert_selector RICH_TEXT_EDITOR_CONTENT, text: "Text I typed"
    assert_equal "<p><strong>Text I typed</strong></p>", rich_text_editor_value

    fill_in "Tag", with: "a-free-tag"
    click_on "Save Document"

    assert_text "Document a-free-tag created."
    assert_equal "<p><strong>Text I typed</strong></p>", Document.find_by(tag: "a-free-tag").body
  end

  # A refresh -- Turbo fetching the page again and morphing in the difference --
  # compares against the server's HTML, which knows nothing of text that has not
  # been saved yet. The rejected form above survives either way, because the
  # server sends back what was typed; this is the case that needs the guard.
  #
  # Turbo also takes its snapshot of the page before a refresh, and Lexxy answers
  # that by taking its editing area out. The morph leaves the editor alone, so
  # nothing would put it back: lexxy_controller.js does.
  test "a refresh of the page keeps text that has not been saved" do
    visit new_admin_document_path
    wait_for_rich_text_editor
    type_into_rich_text_editor("Text I typed")

    execute_script(<<~JS)
      document.addEventListener("turbo:morph", () => { document.documentElement.dataset.morphed = "true" }, { once: true })
      Turbo.visit(location.href, { action: "replace" })
    JS
    assert_selector "html[data-morphed]"

    assert_selector "lexxy-toolbar button", minimum: 1
    assert_selector RICH_TEXT_EDITOR_CONTENT, text: "Text I typed"
    assert_equal "<p>Text I typed</p>", rich_text_editor_value
  end

  # `required` is checked by the browser, so a document with no text never
  # reaches the server: the form stays where it is.
  test "a form with nothing typed in the editor is held back by the browser" do
    visit new_admin_document_path
    wait_for_rich_text_editor

    fill_in "Tag", with: "a-free-tag"
    fill_in "One-Line Description", with: "A document with no text"
    click_on "Save Document"

    # Lexxy sets this from the browser's own `invalid` event and from nothing
    # else, so it is what tells "held back here" from "sent, and refused by the
    # server": the path, the missing row and the missing "created." are the same
    # in both.
    assert_selector "#{RICH_TEXT_EDITOR_CONTENT}[aria-invalid=true]"
    assert_no_selector "#form-error-summary"
    assert_current_path new_admin_document_path
    assert_no_text "created."
    assert_nil Document.find_by(tag: "a-free-tag")
  end

  # Nothing here serves uploads, and coloured text is not part of the design
  # system. The editor has both; the page turns them off.
  test "the toolbar offers neither an upload nor a text colour" do
    visit new_admin_document_path
    wait_for_rich_text_editor

    assert_selector "lexxy-toolbar button[name=bold]"
    assert_no_selector "lexxy-toolbar button[name=image]"
    assert_no_selector "lexxy-toolbar button[name=file]"
    assert_no_selector "lexxy-toolbar button[name=highlight]"
  end

  # A custom element cannot take focus, so the browser has nowhere to put a
  # click on the label unless the page does it (lexxy_controller.js).
  test "clicking the label puts the caret in the editor" do
    visit new_admin_document_path
    wait_for_rich_text_editor

    find("label", text: "Document Text").click

    assert_selector "#{RICH_TEXT_EDITOR_CONTENT}:focus"
  end

  # Documents are older than this editor. What the last one wrote has to open
  # with its text, not blank.
  test "a document written before this editor opens with its text" do
    visit edit_admin_document_path(@existing)
    wait_for_rich_text_editor

    assert_selector RICH_TEXT_EDITOR_CONTENT, text: "Text"
    assert_equal "<p>Text</p>", rich_text_editor_value
  end

  # Lexxy tears its editing area down when Turbo caches the page, on the
  # assumption that the page is about to be replaced. Turbo also caches the page
  # when the address moves to a place on it without a visit -- a link left to the
  # browser, the back button across a hash -- and then nothing replaces it: the
  # toolbar stays and the editing area is gone (basecamp/lexxy#1200). The page is
  # still cached; lexxy_controller.js puts the editor back with what was typed.
  #
  # Not a click on a link: Turbo takes those over and fetches the page again,
  # which empties every field on it, editor or not.
  test "moving to a place on the same page leaves the editor and its text in place" do
    visit new_admin_document_path
    wait_for_rich_text_editor
    type_into_rich_text_editor("Text I typed")

    # hashchange follows popstate, which is where Turbo answers the move, so by
    # the time the flag is up whatever it did to the editor has been done.
    execute_script(<<~JS)
      window.addEventListener("hashchange", () => { document.documentElement.dataset.moved = "true" }, { once: true })
      location.hash = "jump-target"
    JS
    assert_selector "html[data-moved]"

    assert_selector RICH_TEXT_EDITOR_CONTENT, text: "Text I typed"
    assert_equal "<p>Text I typed</p>", rich_text_editor_value
  end

  # Turbo keeps a snapshot of a page that is left, and the Back button returns
  # to it. Lexxy rebuilds from its value attribute there, which holds what the
  # server sent, so the typed text has to be written to it before the snapshot
  # is taken (lexxy_controller.js). The other fields come back by themselves.
  test "the Back button returns to the form as it was left, the editor's text included" do
    visit new_admin_document_path
    wait_for_rich_text_editor

    fill_in "Tag", with: "typed-tag"
    fill_in "One-Line Description", with: "Typed description"
    type_into_rich_text_editor("Text I typed", bold: true)

    first(:link, href: admin_documents_path).click
    assert_current_path admin_documents_path
    assert_no_selector "lexxy-editor"

    page.go_back
    assert_current_path new_admin_document_path
    wait_for_rich_text_editor

    assert_field "Tag", with: "typed-tag"
    assert_field "One-Line Description", with: "Typed description"
    assert_selector "#{RICH_TEXT_EDITOR_CONTENT} strong", text: "Text I typed"
    assert_equal "<p><strong>Text I typed</strong></p>", rich_text_editor_value
  end

  # Lexxy's link box is an <input type="url"> inside the editor, so inside the
  # form. An address typed without "https://" is refused by the box and stays in
  # it when the box closes; the browser then would not submit the form, and said
  # nothing about why, because the field at fault was hidden.
  test "an address left in the link box does not stop the form from saving" do
    visit new_admin_document_path
    wait_for_rich_text_editor

    fill_in "Tag", with: "a-free-tag"
    fill_in "One-Line Description", with: "A document with an abandoned link"
    type_into_rich_text_editor("Text I typed")

    find("lexxy-toolbar button[name=link]").click
    link_box = find("lexxy-toolbar input[type=url]")
    link_box.send_keys("www.burningman.org", :enter)
    assert_equal true, evaluate_script('document.querySelector("lexxy-toolbar input[type=url]").validity.typeMismatch')
    link_box.send_keys(:escape)
    assert_no_selector "lexxy-toolbar input[type=url]", visible: :visible

    click_on "Save Document"

    assert_text "Document a-free-tag created."
    assert_equal "<p>Text I typed</p>", Document.find_by(tag: "a-free-tag").body
  end

  # Beside a divider with no line of text after it, Lexxy keeps an empty
  # paragraph for the caret to land in, marked with a class named "hidden".
  # Tailwind has a utility of that name, which took the paragraph out of the page
  # and sent the typed text into the first line instead.
  test "text typed after a click below a closing divider goes after the divider" do
    @existing.update_column(:body, "<p>Line one</p><hr>")

    visit edit_admin_document_path(@existing)
    wait_for_rich_text_editor

    # The caret has to be somewhere else first: that is when the paragraph is
    # marked hidden.
    find("#{RICH_TEXT_EDITOR_CONTENT} p", text: "Line one").click
    assert_selector "#{RICH_TEXT_EDITOR_CONTENT} p.provisional-paragraph.hidden"

    below = evaluate_script(<<~JS)
      (() => {
        const divider = document.querySelector("lexxy-editor .lexxy-editor__content figure").getBoundingClientRect()
        return { x: Math.round(divider.left + 40), y: Math.round(divider.bottom + 30) }
      })()
    JS
    page.driver.browser.action.move_to_location(below["x"], below["y"]).click.perform
    page.driver.browser.action.send_keys("after").perform

    assert_selector "#{RICH_TEXT_EDITOR_CONTENT} figure + p", text: "after"
    assert_equal "<p>Line one</p><hr><p>after</p>", rich_text_editor_value
  end

  # Lexxy takes any <span> with a colour for a highlight and reads nothing else
  # from it, and Google Docs writes every run as such a span, bold or not.
  test "text pasted from Google Docs keeps its bold and its italic" do
    visit new_admin_document_path
    wait_for_rich_text_editor
    find(RICH_TEXT_EDITOR_CONTENT).click

    execute_script(<<~JS, FROM_GOOGLE_DOCS)
      const data = new DataTransfer()
      data.setData("text/html", arguments[0])
      data.setData("text/plain", "Shifts open Friday at noon Pacific time")
      document.querySelector("lexxy-editor .lexxy-editor__content")
        .dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
    JS

    assert_selector "#{RICH_TEXT_EDITOR_CONTENT} strong", text: "Friday at noon", exact_text: true
    assert_selector "#{RICH_TEXT_EDITOR_CONTENT} em", text: "Pacific time"
    assert_equal "<p>Shifts open <strong>Friday at noon</strong><em> Pacific time</em></p>", rich_text_editor_value
  end

  # The editor shows a merged cell and used to leave its span out of what it
  # submitted, so the cells beside it slid into the wrong columns once saved.
  test "a merged table cell is still merged in what the editor submits" do
    @existing.update_column(:body, '<table><tbody><tr><td colspan="2"><p>Monday shifts</p></td></tr>' \
                                   "<tr><td><p>06:00</p></td><td><p>Hubcap</p></td></tr></tbody></table>")

    visit edit_admin_document_path(@existing)
    wait_for_rich_text_editor

    assert_selector "#{RICH_TEXT_EDITOR_CONTENT} td[colspan='2']", text: "Monday shifts"
    assert_includes rich_text_editor_value, '<td colspan="2">'
  end

  # The morph leaves the editor alone, and with it the class that says the field
  # is in error. application.js carries the server's classes across, and takes
  # them off again once the server stops sending them.
  test "a field the server refused shows it, until the server stops refusing it" do
    visit new_admin_document_path
    wait_for_rich_text_editor

    fill_in "Tag", with: "a-free-tag"
    fill_in "One-Line Description", with: "A document with no text"
    # Past the browser's own check, so that it is the server that refuses.
    bypass_html5_validation
    click_on "Save Document"

    assert_selector "#form-error-summary"
    assert_selector "lexxy-editor.border-error"

    fill_in "Tag", with: @existing.tag
    type_into_rich_text_editor("Text I typed")
    click_on "Save Document"

    assert_text "has already been taken"
    assert_no_selector "lexxy-editor.border-error"
    assert_equal "<p>Text I typed</p>", rich_text_editor_value
  end

  # The page the Back button returns to is a copy of the one that was left. What
  # application.js remembers about the editor's classes is on the element, so the
  # copy has it too; kept anywhere else, the border stayed for good.
  test "a refused field that was left and returned to loses its border like any other" do
    visit new_admin_document_path
    wait_for_rich_text_editor

    fill_in "Tag", with: "a-free-tag"
    fill_in "One-Line Description", with: "A document with no text"
    bypass_html5_validation
    click_on "Save Document"
    assert_selector "lexxy-editor.border-error"

    first(:link, href: admin_documents_path).click
    assert_current_path admin_documents_path
    page.go_back
    wait_for_rich_text_editor
    assert_selector "lexxy-editor.border-error"

    fill_in "Tag", with: @existing.tag
    type_into_rich_text_editor("Text I typed")
    click_on "Save Document"

    assert_text "has already been taken"
    assert_no_selector "lexxy-editor.border-error"
  end

  private

  # What the editor will submit.
  def rich_text_editor_value
    evaluate_script('document.querySelector("lexxy-editor").value')
  end
end
