# frozen_string_literal: true

require "test_helper"

# The kiosk bookmark page. Nothing here signs in: that is the whole point of the
# page, and every test would still pass if it did, so none of them do.
class BookmarksControllerTest < ActionDispatch::IntegrationTest
  BODY = "<ul><li><a href=\"https://example.com/\">A place to go</a></li></ul>"

  setup do
    Document.delete_all

    # Documents are built here rather than loaded from a fixture file: whether a
    # dept-nda row exists decides who keeps their Event Management roles, so this
    # table has no fixtures at all.
    @author = person(:auditor_ranger)
    @document = create_document
  end

  # ------------------------------------------------------------------ show

  test "a bookmark document is readable without signing in" do
    get bookmark_path("kiosk")

    assert_response :success
    assert_select "a[href='https://example.com/']", text: "A place to go"
    assert_select "title", text: /Test bookmarks/
  end

  test "the page carries no navigation and asks not to be indexed" do
    get bookmark_path("kiosk")

    assert_response :success
    assert_select "nav", false, "the kiosk page should have no navigation"
    assert_select "meta[name=robots][content='noindex,nofollow']"
  end

  test "the refresh time is handed to the page in seconds" do
    get bookmark_path("kiosk")

    assert_select "main[data-bookmark-refresh-seconds-value='300']"
  end

  test "a document with no refresh time asks for none" do
    create_document(tag: "#{Document::BOOKMARK_TAG_PREFIX}still",
                    description: "Never refreshes", refresh_time: nil)

    get bookmark_path("still")

    assert_response :success
    assert_select "main[data-bookmark-refresh-seconds-value='0']"
  end

  test "an unknown bookmark says so" do
    get bookmark_path("nowhere")

    assert_response :not_found
    assert_select ".empty-state", text: /was not found/
  end

  # This is the reason the page can be public at all. Agreements, contact lists,
  # and team resource documents all share this table.
  test "a document that is not a bookmark cannot be reached" do
    create_document(tag: Document::DEPT_NDA_TAG, description: "Private document",
                    body: "Secrets")

    get bookmark_path(Document::DEPT_NDA_TAG)

    assert_response :not_found
    assert_no_match(/Secrets/, response.body)
  end

  test "an address a tag cannot appear in has no page at all" do
    get "/bookmark/kiosk.json"
    assert_response :not_found

    get "/bookmark/kiosk/elsewhere"
    assert_response :not_found
  end

  # -------------------------------------------------------------- document

  test "the refresh answers with the document in a frame and no page around it" do
    get bookmark_document_path("kiosk")

    assert_response :success
    assert_select "turbo-frame#bookmark"
    assert_select "a[href='https://example.com/']"
    assert_no_match(/<html/, response.body)
  end

  # A frame naming the address it came from reads as a loop, and Turbo refuses
  # to follow it -- the kiosk would empty itself on its first refresh.
  test "the refresh answer names no source of its own" do
    get bookmark_document_path("kiosk")

    assert_select "turbo-frame#bookmark:not([src])"
  end

  test "the refresh of an unknown bookmark is simply not found" do
    get bookmark_document_path("nowhere")

    assert_response :not_found
  end

  private

  def create_document(tag: "#{Document::BOOKMARK_TAG_PREFIX}kiosk",
                      description: "Test bookmarks", body: BODY, refresh_time: 5)
    Document.create!(tag:, description:, body:, refresh_time:,
                     person_create_id: @author.id, person_update_id: @author.id)
  end
end
