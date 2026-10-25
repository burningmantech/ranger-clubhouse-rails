# frozen_string_literal: true

require "test_helper"

class Admin::DocumentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  # The text of the document every test starts with.
  BODY = "<strong>Hello from the test document</strong>"

  setup do
    Rails.cache.clear
    Document.delete_all

    @admin = person(:auditor_ranger)
    @outsider = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    @document = create_document
  end

  teardown do
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- index

  test "admin sees a row per document" do
    create_document(tag: "second-doc", description: "Another document")

    sign_in_as(@admin)

    get admin_documents_path

    assert_response :success
    assert_select "h1", text: /Documents/
    assert_select "th[scope=row]", text: /test-doc/
    assert_select "th[scope=row]", text: /second-doc/
  end

  test "a tag the Clubhouse looks up by name is marked, and a plain tag is not" do
    create_document(tag: Document::SANDMAN_AFFIDAVIT_TAG, description: "A named document")

    sign_in_as(@admin)

    get admin_documents_path

    assert_response :success
    # Two documents, one of them named in the code: only that row is marked.
    # The badge in the callout above the table explains the mark, so the count
    # is taken inside the table.
    assert_select "tbody .badge", text: /Referenced/, count: 1
  end

  test "the refresh minutes of a bookmark are shown, and a document without them reads as blank" do
    create_document(tag: "bookmark-test", description: "A bookmark", refresh_time: 5)

    sign_in_as(@admin)

    get admin_documents_path

    assert_response :success
    assert_select "td", text: /5 min/
    # The starting document sets no refresh minutes, so its cell reads as blank.
    assert_select "td", text: "—"
  end

  test "an empty table says why it is empty" do
    Document.delete_all

    sign_in_as(@admin)

    get admin_documents_path

    assert_response :success
    assert_select "body", text: /No documents have been added yet/
  end

  test "a preview loads on demand rather than with the list" do
    sign_in_as(@admin)

    get admin_documents_path

    assert_response :success
    # The list ships the frame, not the document text.
    assert_select "turbo-frame[src=?]", body_admin_document_path(@document)
    assert_select "body", text: /Hello from the test document/, count: 0
  end

  test "the preview renders the document the way a display page does" do
    sign_in_as(@admin)

    get body_admin_document_path(@document)

    assert_response :success
    assert_select "turbo-frame#document-body-frame-#{@document.id}"
    assert_select "strong", text: "Hello from the test document"
  end

  # ----------------------------------------------------------- authorization

  test "a person without the admin role is turned away" do
    sign_in_as(@outsider)

    get admin_documents_path

    assert_redirected_to me_root_path
  end

  test "a person without the admin role may not read a document body" do
    sign_in_as(@outsider)

    get body_admin_document_path(@document)

    assert_redirected_to me_root_path
  end

  test "a person without the admin role may not reach the write pages" do
    sign_in_as(@outsider)

    get new_admin_document_path
    assert_redirected_to me_root_path

    get edit_admin_document_path(@document)
    assert_redirected_to me_root_path
  end

  test "a person without the admin role may not create, edit, or delete a document" do
    sign_in_as(@outsider)

    assert_no_difference "Document.count" do
      post admin_documents_path, params: {
        document: { tag: "sneaky-doc", description: "Not allowed", body: "<div>Text</div>" }
      }
    end
    assert_redirected_to me_root_path

    patch admin_document_path(@document), params: {
      document: { tag: @document.tag, description: "Not allowed", body: @document.body }
    }
    assert_redirected_to me_root_path
    assert_equal "A test document", @document.reload.description

    assert_no_difference "Document.count" do
      delete admin_document_path(@document)
    end
    assert_redirected_to me_root_path
  end

  # --------------------------------------------------------------- editor

  test "a document is edited with the rich text editor, whatever it holds" do
    carries_more = create_document(tag: "rich-doc",
                                   body: %(<h4 style="color: red">Heading</h4><table><tr><td>Cell</td></tr></table>))

    sign_in_as(@admin)

    [@document, carries_more].each do |document|
      get edit_admin_document_path(document)

      assert_response :success
      assert_select "lexxy-editor"
      assert_select "textarea#document_body", count: 0
    end
  end

  # --------------------------------------------------------------- writes

  test "admin creates a document and is recorded as its author" do
    sign_in_as(@admin)

    assert_difference "Document.count", 1 do
      post admin_documents_path, params: {
        document: { tag: "new-doc", description: "A new document", body: "<div>Text</div>" }
      }
    end

    assert_redirected_to admin_documents_path

    created = Document.find_by(tag: "new-doc")
    assert_equal @admin.id, created.person_create_id
    assert_equal @admin.id, created.person_update_id
  end

  # Which tags are refused is settled in the model test; this covers the page
  # the person is handed back when one is.
  test "a document the model refuses comes back as a form to fix" do
    sign_in_as(@admin)

    assert_no_difference "Document.count" do
      post admin_documents_path, params: {
        document: { tag: @document.tag, description: "A duplicate", body: "<div>Text</div>" }
      }
    end

    assert_response :unprocessable_entity
    assert_select "form input#document_tag"
    # The reason, and everything already typed, both come back.
    assert_select ".text-error", text: /has already been taken/i
    assert_select "input#document_description[value=?]", "A duplicate"
  end

  test "an edit records who made it" do
    @document.update_columns(person_update_id: @outsider.id)

    sign_in_as(@admin)

    patch admin_document_path(@document), params: {
      document: { tag: @document.tag, description: "A better description", body: @document.body }
    }

    assert_redirected_to admin_documents_path

    @document.reload
    assert_equal "A better description", @document.description
    assert_equal @admin.id, @document.person_update_id
  end

  test "saving a document no one changed leaves its byline alone" do
    @document.update_columns(person_update_id: @outsider.id)

    sign_in_as(@admin)

    patch admin_document_path(@document), params: {
      document: { tag: @document.tag, description: @document.description, body: @document.body }
    }

    assert_redirected_to admin_documents_path
    assert_equal @outsider.id, @document.reload.person_update_id
  end

  test "an edit that empties the document text is refused" do
    sign_in_as(@admin)

    patch admin_document_path(@document), params: {
      document: { tag: @document.tag, description: @document.description, body: "" }
    }

    assert_response :unprocessable_entity
    assert_equal BODY, @document.reload.body
  end

  test "admin deletes a document" do
    sign_in_as(@admin)

    assert_difference "Document.count", -1 do
      delete admin_document_path(@document)
    end

    assert_redirected_to admin_documents_path
  end

  private

  # Documents are created here rather than in a fixture file: a fixture would
  # exist for every test in the suite, and the presence of some tags changes
  # what roles a person holds.
  def create_document(tag: "test-doc", description: "A test document",
                      body: BODY, refresh_time: nil)
    Document.create!(tag:, description:, body:, refresh_time:,
                     person_create_id: @admin.id, person_update_id: @admin.id)
  end
end
