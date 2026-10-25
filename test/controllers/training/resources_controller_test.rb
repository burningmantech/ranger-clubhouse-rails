# frozen_string_literal: true

require "test_helper"

# Training > Trainer Resources: the three read states, the split between who may
# read the document and who may write it, and the pointer the position keeps to
# the document it published.
class Training::ResourcesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    # Every ART belongs to a team; the manage gate refuses one that does not,
    # which "an ART without a team turns even an admin away" pins.
    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true,
                                  team_id: teams(:green_dot_cadre).id)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "ART Green Dot Interface")
    ensure_role(Role::TRAINER_RESOURCE_MANAGEMENT_BASE | Position::TRAINING, "Training Resrc Mgmt")
    ensure_role(Role::TRAINER_RESOURCE_MANAGEMENT_BASE | Position::GREEN_DOT_TRAINING,
                "ART Green Dot Resrc Mgmt")

    @admin = person(:active_ranger)
    @trainer = person(:echelon_ranger)
    @resource_manager = person(:alpha_ranger)
    @art_trainer = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    grant_role(@admin, Role::ADMIN)
    grant_role(@trainer, Role::TRAINER)
    grant_role(@resource_manager, Role::TRAINER)
    grant_role(@resource_manager, Role::TRAINER_RESOURCE_MANAGEMENT_BASE | Position::TRAINING)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # --- reading -------------------------------------------------------------

  test "a position with no document says so and offers nothing to a reader" do
    sign_in_as(@trainer)
    get training_resources_path("in-person")

    assert_response :success
    assert_select "h1", text: /Trainer Resources/
    assert_match "No trainer resource document has been written for Training yet.", response.body
    assert_select "a[href=?]", training_edit_resources_path("in-person"), count: 0
  end

  # The only link into the editor before a document exists -- the menu points
  # at the read page, so losing this button strands the people who may write.
  test "a position with no document offers a writer the way to write one" do
    sign_in_as(@resource_manager)
    get training_resources_path("in-person")

    assert_response :success
    assert_select "a[href=?]", training_edit_resources_path("in-person"), text: /Write the Document/
  end

  test "a reader sees the document rendered as authored" do
    write_document(@dirt, body: "<h2>Before you teach</h2><ul><li>Read the outline</li></ul>")

    sign_in_as(@trainer)
    get training_resources_path("in-person")

    assert_response :success
    assert_select ".lexxy-content h2", text: "Before you teach"
    assert_select ".lexxy-content li", text: "Read the outline"
  end

  # A document deleted out from under the pointer must not read as "none was
  # ever written" -- someone has to know the link is broken.
  test "a pointer left behind by a deleted document is called out" do
    @dirt.update_columns(resource_tag: "training-resource")

    sign_in_as(@trainer)
    get training_resources_path("in-person")

    assert_response :success
    assert_match "The Document Is Missing", response.body
    assert_match "training-resource", response.body
  end

  test "the view gate is the interface's, not the document's" do
    sign_in_as(@outsider)
    get training_resources_path("in-person")

    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "only someone who may write the document is offered the edit link" do
    write_document(@dirt)

    sign_in_as(@trainer)
    get training_resources_path("in-person")
    assert_select "a[href=?]", training_edit_resources_path("in-person"), count: 0

    sign_in_as(@resource_manager)
    get training_resources_path("in-person")
    assert_select "a[href=?]", training_edit_resources_path("in-person")

    sign_in_as(@admin)
    get training_resources_path("in-person")
    assert_select "a[href=?]", training_edit_resources_path("in-person")
  end

  # --- who may write -------------------------------------------------------

  test "the resource management role admits its own position and no other" do
    sign_in_as(@resource_manager)

    get training_edit_resources_path("in-person")
    assert_response :success

    get training_edit_resources_path("green-dot")
    assert_redirected_to me_root_path
  end

  # The subject clears the ART's view gate on its own composed interface role,
  # so the refusal below can only come from the write gate -- which is what
  # makes this the test that the role is composed against THIS position rather
  # than a fixed one.
  test "the resource management role for one position does not open another" do
    grant_role(@art_trainer, Role::TRAINER_RESOURCE_MANAGEMENT_BASE | Position::TRAINING)

    sign_in_as(@art_trainer)

    get training_resources_path("green-dot")
    assert_response :success

    get training_edit_resources_path("green-dot")
    assert_redirected_to me_root_path
    assert_match(/not authorized to manage/, flash[:error])
  end

  test "running an ART's sessions does not carry the right to publish its document" do
    sign_in_as(@art_trainer)

    get training_resources_path("green-dot")
    assert_response :success

    get training_edit_resources_path("green-dot")
    assert_redirected_to me_root_path
    assert_match(/not authorized to manage/, flash[:error])
  end

  test "a trainer who reads In-Person Training may not write its document" do
    sign_in_as(@trainer)

    get training_edit_resources_path("in-person")
    assert_redirected_to me_root_path
  end

  test "an ART without a team turns even an admin away" do
    @green_dot.update_columns(team_id: nil)

    sign_in_as(@admin)

    get training_resources_path("green-dot")
    assert_response :success

    get training_edit_resources_path("green-dot")
    assert_redirected_to me_root_path
  end

  # In-Person Training has no team by design, so the team rule cannot apply to it.
  test "In-Person Training is exempt from the team rule" do
    assert_nil @dirt.team_id

    sign_in_as(@admin)
    get training_edit_resources_path("in-person")

    assert_response :success
  end

  # --- the editor ----------------------------------------------------------

  test "a first edit scaffolds a document named after the position" do
    sign_in_as(@admin)
    get training_edit_resources_path("green-dot")

    assert_response :success
    assert_match "green-dot-training-resource", response.body
    assert_match "Green Dot Training Position Document", response.body
    assert_select "form[action=?][method=?]", training_resources_path("green-dot"), "post"
  end

  # The pointer names the document even when the row is gone: what the form
  # shows is what a save will file it under, so anything linking to that tag
  # keeps working.
  test "a scaffold keeps the tag the position already points at" do
    @green_dot.update_columns(resource_tag: "an-older-tag")

    sign_in_as(@admin)
    get training_edit_resources_path("green-dot")

    assert_response :success
    assert_match "an-older-tag", response.body
    assert_no_match "green-dot-training-resource", response.body
  end

  test "an existing document is edited in place" do
    write_document(@dirt, body: "<p>Old text</p>")

    sign_in_as(@admin)
    get training_edit_resources_path("in-person")

    assert_response :success
    assert_select "form[action=?]", training_resources_path("in-person")
    assert_select "input[name=?][value=?]", "_method", "patch"
    # The editor is itself the field that gets submitted, and starts out holding
    # what was saved.
    assert_select "lexxy-editor[name=?][value=?]", "document[body]", "<p>Old text</p>"
    assert_select "a[href=?]", training_resources_path("in-person")
  end

  # Every document is edited with the rich text editor. It keeps a short list of
  # formatting and drops the rest, so each of these -- all drawn from documents
  # already on file -- comes back changed the first time it is saved.
  {
    "a table" => "<table><tr><td>Bring</td><td>Radios</td></tr></table>",
    "a heading below h1" => "<h2>Before you teach</h2><p>Read the outline.</p>",
    "a link that opens in a new tab" =>
      %(<p><a href="https://example.com" target="_blank" rel="noopener">The guide</a></p>),
    "inline styling" => %(<p style="color: red">Bring a radio.</p>),
    "a span" => "<p><span>Bring a radio.</span></p>",
    "only what the editor keeps" =>
      %(<h1>Before you teach</h1><div>Read the <a href="/x">outline</a>.</div><ul><li>Radio</li></ul>)
  }.each do |what, body|
    test "a document containing #{what} is edited with the rich text editor" do
      write_document(@dirt, body:)

      sign_in_as(@admin)
      get training_edit_resources_path("in-person")

      assert_response :success
      assert_select "lexxy-editor"
      assert_select "textarea[name=?]", "document[body]", count: 0
    end
  end

  # --- writing -------------------------------------------------------------

  test "creating the document files it and points the position at it" do
    sign_in_as(@resource_manager)

    assert_difference "Document.count", 1 do
      post training_resources_path("in-person"), params: { document: { body: "<p>Read this first.</p>" } }
    end

    assert_redirected_to training_resources_path("in-person")
    assert_match(/ created\./, flash[:success])

    document = Document.find_by(tag: "training-resource")
    assert_equal "Training Position Document", document.description
    assert_equal "<p>Read this first.</p>", document.body
    assert_equal @resource_manager.id, document.person_create_id
    assert_equal @resource_manager.id, document.person_update_id
    assert_equal "training-resource", @dirt.reload.resource_tag
  end

  test "creating a document repairs a pointer whose row was deleted" do
    @dirt.update_columns(resource_tag: "training-resource")

    sign_in_as(@admin)
    post training_resources_path("in-person"), params: { document: { body: "<p>Rewritten.</p>" } }

    assert_redirected_to training_resources_path("in-person")
    assert_equal "training-resource", @dirt.reload.resource_tag
    assert_equal "<p>Rewritten.</p>", Document.find_by(tag: "training-resource").body
  end

  test "an empty document is refused and the editor comes back with the reason" do
    sign_in_as(@admin)

    assert_no_difference "Document.count" do
      post training_resources_path("in-person"), params: { document: { body: "" } }
    end

    assert_response :unprocessable_entity
    assert_match "Write the document text before saving.", response.body
    assert_nil @dirt.reload.resource_tag
  end

  test "a tag already taken by another document is refused rather than stolen" do
    Document.create!(tag: "training-resource", description: "Someone else's",
                     body: "<p>Not yours.</p>",
                     person_create_id: @admin.id, person_update_id: @admin.id)

    sign_in_as(@admin)
    post training_resources_path("in-person"), params: { document: { body: "<p>Mine.</p>" } }

    assert_response :unprocessable_entity
    assert_nil @dirt.reload.resource_tag
    assert_equal "<p>Not yours.</p>", Document.find_by(tag: "training-resource").body
  end

  test "saving an edit changes the text and records who changed it" do
    document = write_document(@dirt, body: "<p>Old text</p>")

    sign_in_as(@resource_manager)
    patch training_resources_path("in-person"), params: { document: { body: "<p>New text</p>" } }

    assert_redirected_to training_resources_path("in-person")
    assert_match(/ updated\./, flash[:success])

    document.reload
    assert_equal "<p>New text</p>", document.body
    assert_equal @resource_manager.id, document.person_update_id
    assert_equal @admin.id, document.person_create_id
  end

  # The editor is a form control only once its script has run, and it is this
  # form's only field. A form sent before then carries no document at all, which
  # used to be answered with a 400.
  test "a form sent before the editor had loaded saves nothing and says why" do
    document = write_document(@dirt, body: "<p>Old text</p>")

    sign_in_as(@resource_manager)
    patch training_resources_path("in-person"), params: { commit: "Save Document" }

    assert_response :unprocessable_entity
    assert_match "The editor was still loading, so nothing was saved.", response.body
    assert_select "lexxy-editor[value=?]", "<p>Old text</p>"
    assert_equal "<p>Old text</p>", document.reload.body
  end

  test "a first document sent before the editor had loaded is not created" do
    sign_in_as(@resource_manager)

    assert_no_difference "Document.count" do
      post training_resources_path("in-person"), params: { commit: "Save Document" }
    end

    assert_response :unprocessable_entity
    assert_match "The editor was still loading, so nothing was saved.", response.body
    assert_nil @dirt.reload.resource_tag
  end

  # The people who may write this document are not admins, and it is printed as
  # it is stored, here and in the admin preview. So it is cleaned on the way in.
  test "what a writer saves is cleaned before it is stored" do
    sign_in_as(@resource_manager)
    post training_resources_path("in-person"), params: {
      document: { body: %(<p>Read <strong>this</strong> first.</p><img src="x" onerror="alert(1)"><script>alert(2)</script>) }
    }

    assert_redirected_to training_resources_path("in-person")
    stored = Nokogiri::HTML5.fragment(Document.find_by(tag: "training-resource").body)
    assert_equal "this", stored.at_css("p strong").text
    assert_empty stored.css("script, [onerror]")
  end

  # Upstream re-derived the tag on every save, so renaming a position silently
  # re-filed its document -- and collided if the new name was taken.
  test "renaming the position does not re-file its document on the next save" do
    document = write_document(@dirt, body: "<p>Old text</p>")
    @dirt.update_columns(title: "In-Person Training")

    sign_in_as(@admin)
    patch training_resources_path("in-person"), params: { document: { body: "<p>New text</p>" } }

    assert_redirected_to training_resources_path("in-person")
    document.reload
    assert_equal "training-resource", document.tag
    assert_equal "Training Position Document", document.description
    assert_equal "training-resource", @dirt.reload.resource_tag
  end

  test "deleting the document clears the pointer" do
    write_document(@dirt)

    sign_in_as(@resource_manager)

    assert_difference "Document.count", -1 do
      delete training_resources_path("in-person")
    end

    assert_redirected_to training_resources_path("in-person")
    assert_match(/ deleted\./, flash[:success])
    assert_nil @dirt.reload.resource_tag
  end

  test "editing a document that vanished says so instead of erroring" do
    @dirt.update_columns(resource_tag: "training-resource")

    sign_in_as(@admin)

    patch training_resources_path("in-person"), params: { document: { body: "<p>New text</p>" } }
    assert_redirected_to training_resources_path("in-person")
    assert_match(/no longer exists/, flash[:error])

    delete training_resources_path("in-person")
    assert_redirected_to training_resources_path("in-person")
    assert_match(/no longer exists/, flash[:error])
  end

  # A reader of In-Person Training holds Trainer, which clears the interface's
  # view gate -- so each write has to be refused on its own. Counting rows is
  # not enough: an ungated update rewrites a document without changing the count.
  test "a reader cannot write by addressing the actions directly" do
    document = write_document(@dirt, body: "<p>Original.</p>")

    sign_in_as(@trainer)

    assert_no_difference "Document.count" do
      %i[post patch delete].each do |verb|
        send(verb, training_resources_path("in-person"),
             params: { document: { body: "<p>Mine now.</p>" } })

        assert_redirected_to me_root_path
        assert_match(/not authorized to manage/, flash[:error])
      end
    end

    assert_equal "<p>Original.</p>", document.reload.body
    assert_equal "training-resource", @dirt.reload.resource_tag
  end

  # --- navigation ----------------------------------------------------------

  test "the sidebar carries Trainer Resources and marks it active in the editor" do
    sign_in_as(@admin)

    get training_resources_path("in-person")
    assert_select "a[href=?][aria-current=true]", training_resources_path("in-person")

    get training_edit_resources_path("in-person")
    assert_select "a[href=?][aria-current=true]", training_resources_path("in-person")
    assert_select "a[href=?][aria-current=true]", training_path("in-person"), count: 0
  end

  private

  def write_document(position, body: "<p>Bring a radio.</p>")
    document = Document.create!(tag: position.build_resource_tag,
                                description: position.build_resource_title,
                                body:,
                                person_create_id: @admin.id,
                                person_update_id: @admin.id)
    position.update_columns(resource_tag: document.tag)
    document
  end
end
