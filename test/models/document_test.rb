# frozen_string_literal: true

require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  # ----------------------------------------------------------- validation

  test "a tag already in use is refused" do
    existing = Document.create!(tag: "taken-tag", description: "A document", body: "<div>Text</div>",
                                person_create_id: person(:auditor_ranger).id,
                                person_update_id: person(:auditor_ranger).id)
    duplicate = Document.new(tag: existing.tag, description: "Another", body: "<div>Text</div>")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:tag], "Tag has already been taken."
  end

  test "a tag with a space in it is refused" do
    document = Document.new(tag: "not a tag", description: "A document", body: "<div>Text</div>")

    assert_not document.valid?
    assert_includes document.errors[:tag], "The tag may not contain spaces."
  end

  # More than the column holds has to come back as a message beside the field,
  # not as an error page that loses everything else the writer had typed.
  test "a tag or description longer than the column holds is refused" do
    too_long = "a" * (Document::TEXT_COLUMN_LIMIT + 1)

    document = Document.new(tag: too_long, description: too_long, body: "<div>Text</div>")

    assert_not document.valid?
    assert_includes document.errors[:tag], "Tag is too long (maximum is 191 characters)."
    assert_includes document.errors[:description], "Description is too long (maximum is 191 characters)."
  end

  # An emptied editor still submits its empty block, and that is present? to
  # Ruby, so a plain presence check lets a document with no text through. The
  # block is not always a paragraph: a tool clicked with nothing typed leaves an
  # empty list, heading, quote, code block or table, and a space typed in bold is
  # wrapped in the bold (each one the editor's own output).
  test "a body with no words in it is refused, whichever editor wrote it" do
    untouched_table = '<p><br></p><figure class="lexxy-content__table-wrapper"><table><tbody><tr>' \
                      '<th class="lexxy-content__table-cell--header"><p><br></p></th><td><p><br></p></td>' \
                      "</tr></tbody></table></figure><p><br></p>"

    ["<p><br></p>", "<p></p>", "<div><br></div>", "<p><br></p>\n<p><br></p>", "<p>&nbsp;</p>", "",
     "<ul><li value=\"1\"></li></ul>", "<ol><li value=\"1\"></li></ol>", "<h2><br></h2>",
     "<blockquote><p><br></p></blockquote>",
     "<pre data-language=\"plain\" data-highlight-language=\"plain\"></pre>",
     untouched_table, "<p><strong> </strong></p>", "<p><em>&nbsp;</em></p>"].each do |body|
      document = Document.new(tag: "a-tag", description: "A document", body:)

      assert_equal "", document.body, "stored form of #{body.inspect}"
      assert_not document.valid?, "#{body.inspect} should be refused"
      assert document.errors.added?(:body, :blank), "for #{body.inspect}"
    end
  end

  # Words are content, and so is a divider or an image with none: a document
  # that is one of those has something to show.
  test "a body with anything in it is kept as it arrived" do
    ["<hr>", "<p><br></p><hr><p><br></p>", "<p><img src=\"/a.png\"></p>", "<p>Text</p>",
     "<p><br></p><p>Text</p>", "<div>Text</div>", "<ul><li value=\"1\">Item</li></ul>",
     "<figure class=\"lexxy-content__table-wrapper\"><table><tbody><tr><td><p>Cell</p></td></tr></tbody></table></figure>"].each do |body|
      assert_equal body, Document.new(body:).body
    end
  end

  # ----------------------------------------------------- referenced_tags

  test "the tags named in the code are referenced" do
    referenced = Document.referenced_tags

    assert_includes referenced, Document::DEPT_NDA_TAG
    assert_includes referenced, Document::SANDMAN_AFFIDAVIT_TAG
    assert_not_includes referenced, "a-tag-nothing-points-at"
  end

  # The dashboard reads these four, so renaming one blanks a panel on every
  # dashboard. They have to carry the badge that says so.
  test "the tags the dashboard reads are referenced" do
    referenced = Document.referenced_tags

    assert_includes referenced, Document::DASHBOARD_LINKS_RANGER_TAG
    assert_includes referenced, Document::DASHBOARD_LINKS_PNV_TAG
    assert_includes referenced, Document::CONTACTS_RANGER_TAG
    assert_includes referenced, Document::CONTACTS_PNV_TAG
  end

  test "a tag a position points at is referenced" do
    position = Position.first
    position.update_columns(resource_tag: "a-position-document")

    assert_includes Document.referenced_tags, "a-position-document"
  end

  test "a tag a team points at is referenced" do
    team = Team.first
    team.update_columns(resource_tag: "a-team-document")

    assert_includes Document.referenced_tags, "a-team-document"
  end

  # ---------------------------------------------------------- bookmark_slug

  test "a bookmark document knows the address of its kiosk page" do
    document = Document.new(tag: "#{Document::BOOKMARK_TAG_PREFIX}kiosk")

    assert_equal "kiosk", document.bookmark_slug
  end

  test "a document that is not a bookmark has no kiosk page" do
    assert_nil Document.new(tag: Document::DEPT_NDA_TAG).bookmark_slug
    assert_nil Document.new(tag: nil).bookmark_slug
  end

  # The lists that show these links would otherwise fail to build one.
  test "a bookmark tag the address cannot carry has no kiosk page" do
    assert_nil Document.new(tag: "#{Document::BOOKMARK_TAG_PREFIX}has.a.dot").bookmark_slug
    assert_nil Document.new(tag: Document::BOOKMARK_TAG_PREFIX).bookmark_slug
  end

  # ------------------------------------------------- resource document pointers

  # Team and Position Records store a pointer as typed. Only a tag a resource
  # document may have is followed: stripped, and never a document the code
  # reads by name or a bookmark page anyone can read without signing in.
  test "a resource pointer is followed only where a resource document may live" do
    assert_equal "dirt-team-info", Document.resource_tag("dirt-team-info")
    assert_equal "dirt-team-info", Document.resource_tag("  dirt-team-info ")

    [nil, "", "   ", "dirt team info", "a" * (Document::TEXT_COLUMN_LIMIT + 1),
     Document::DEPT_NDA_TAG, Document::MOTORPOOL_POLICY_TAG, "DEPT-NDA", "bookmark-gate", "Bookmark-Gate"].each do |pointer|
      assert_nil Document.resource_tag(pointer), "#{pointer.inspect} must not be followed"
    end
  end

  # The column compares without regard to case or trailing spaces; a list keyed
  # by the stored tag would disagree with find_by on the same pointer.
  test "a list of pointers finds each document as find_by would" do
    by = person(:auditor_ranger)
    Document.create!(tag: "dirt-team-info", description: "DIRT Team Document", body: "<p>Text</p>",
                     person_create_id: by.id, person_update_id: by.id)

    found = Document.listed_by_pointer(["DIRT-Team-Info", "dirt-team-info ", "no-such-info", nil, "dept-nda"])

    assert_equal %w[DIRT-Team-Info dirt-team-info\ ].sort, found.keys.sort
    assert(found.values.all? { |document| document.tag == "dirt-team-info" })
    assert_raises(ActiveModel::MissingAttributeError) { found.values.first.body }
  end
end
