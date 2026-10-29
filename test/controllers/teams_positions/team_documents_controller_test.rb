# frozen_string_literal: true

require "test_helper"

# Teams & Positions › Team Documents: who reaches which team's document, the
# list that never carries a document's text, the read page's states, and the
# pointer each team keeps to the document it published. The editor's own
# behavior is the shared concern's, pinned by the Trainer Resources test.
class TeamsPositions::TeamDocumentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::VEHICLE_INFO_UPDATE, "Vehicle Info Update")
    ensure_role(Role::TEAM_RESOURCE_MANAGEMENT, "Team Resource Doc Mgmt")

    @admin = person(:active_ranger)
    @manager = person(:retired_ranger)       # manages @team, holds the role
    @roleless_manager = person(:alpha_ranger) # manages @team, lacks the role

    # Upstream's Ember ops area wanted Event Management of everyone, so every
    # reader here holds it unless a test says otherwise.
    [@admin, @manager, @roleless_manager].each { |person| grant_role(person, Role::EVENT_MANAGEMENT) }
    grant_role(@admin, Role::ADMIN)
    grant_role(@manager, Role::TEAM_RESOURCE_MANAGEMENT)

    @team = teams(:dirt_team)
    @other_team = teams(:operations_team)
    TeamManager.create!(team_id: @team.id, person_id: @manager.id)
    TeamManager.create!(team_id: @team.id, person_id: @roleless_manager.id)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # --- who gets in ---------------------------------------------------------

  test "an admin is offered every team" do
    sign_in_as(@admin)
    get teams_positions_team_documents_path

    assert_response :success
    assert_select "h1", /Team Documents/
    assert_match "You can open the document of any of the #{Team.count} teams.", response.body
    assert_select "a[href=?]", teams_positions_team_document_path(@other_team)
  end

  test "a manager holding the role is offered only the teams they manage" do
    sign_in_as(@manager)
    get teams_positions_team_documents_path

    assert_response :success
    assert_match "You manage 1 team.", response.body
    assert_select "a[href=?]", teams_positions_team_document_path(@team)
    assert_select "a[href=?]", teams_positions_team_document_path(@other_team), count: 0
  end

  # Upstream's Ember route for the page (ops) turned away anyone without Event
  # Management or Vehicle Info Update before the role was ever asked about.
  test "a manager holding the role but not Event Management is turned away" do
    revoke_event_management(@manager)

    sign_in_as(@manager)
    get teams_positions_team_documents_path

    assert_redirected_to me_root_path
    assert_match(/Event Management or Vehicle Info Update/, flash[:error])
  end

  test "Vehicle Info Update opens the page as Event Management does" do
    revoke_event_management(@manager)
    grant_role(@manager, Role::VEHICLE_INFO_UPDATE)

    sign_in_as(@manager)
    get teams_positions_team_document_path(@team)

    assert_response :success
  end

  # The list and the editor answer the same way, with the message that names
  # what is missing -- not the concern's general refusal.
  test "a manager without the role is turned away from the list and the editor alike" do
    sign_in_as(@roleless_manager)

    get teams_positions_team_documents_path
    assert_redirected_to me_root_path
    assert_match(/Team Resource Doc Mgmt/, flash[:error])

    get teams_positions_edit_team_document_path(@team)
    assert_redirected_to me_root_path
    assert_match(/Team Resource Doc Mgmt/, flash[:error])
  end

  test "managing one team does not open another's document" do
    sign_in_as(@manager)

    [-> { get teams_positions_team_document_path(@other_team) },
     -> { get teams_positions_edit_team_document_path(@other_team) },
     -> { post teams_positions_team_document_path(@other_team), params: { document: { body: "<p>Mine now.</p>" } } }].each do |request|
      request.call
      assert_redirected_to me_root_path
      assert_equal "That team's document is not available to you.", flash[:error]
    end
    assert_nil @other_team.reload.resource_tag
  end

  # An Admin reaches every team, so one they cannot find has been deleted.
  test "an admin following a link to a deleted team is told it is gone" do
    gone = Team.maximum(:id) + 1

    sign_in_as(@admin)
    get "/teams-positions/team-documents/#{gone}/edit"

    assert_redirected_to teams_positions_team_documents_path
    assert_equal "That team no longer exists.", flash[:error]
  end

  test "a manager holding the role reaches their team's editor" do
    sign_in_as(@manager)
    get teams_positions_edit_team_document_path(@team)

    assert_response :success
    assert_select "lexxy-editor[name=?]", "document[body]"
    # Members read it from their Operational Summary and Agreements pages (Me::TeamDocumentsController).
    assert_match "members read what you write here, from their Operational Summary and Agreements pages.", response.body
    assert_match "renaming the team does not change them", response.body
  end

  test "the menu offers the page to a manager holding the role and to no other manager" do
    sign_in_as(@manager)
    get teams_positions_team_documents_path
    assert_select "#sidebar-drawer-content a[href=?]", teams_positions_team_documents_path

    # Bulk Membership History admits any team manager, so its sidebar is the
    # one a manager without the role can see.
    sign_in_as(@roleless_manager)
    get teams_positions_bulk_membership_history_path
    assert_response :success
    assert_select "#sidebar-drawer-content a[href=?]", teams_positions_team_documents_path, count: 0
  end

  # --- the list ------------------------------------------------------------

  test "each row says who last saved its document, or flags the exception" do
    write_document(@team, by: @manager)
    teams(:council_cadre).update_columns(resource_tag: "a-deleted-document")
    teams(:mentor_cadre).update_columns(resource_tag: Document::DEPT_NDA_TAG)

    sign_in_as(@admin)
    get teams_positions_team_documents_path

    assert_response :success
    assert_select "#team-#{@team.id}", text: /Updated .+ by #{@manager.callsign}/
    assert_select "#team-#{@other_team.id}", text: /No document yet/
    assert_select "#team-#{@other_team.id} .badge", count: 0
    assert_select "#team-#{teams(:council_cadre).id}", text: /Document missing/
    assert_select "#team-#{teams(:mentor_cadre).id}", text: /Tag cannot be used/
  end

  # Tags compare without regard to case or trailing spaces in the database, so
  # the list must find the document its own page shows.
  test "a pointer that differs from its document's tag only in case still finds it" do
    write_document(@team, by: @manager)
    @team.update_columns(resource_tag: "DIRT-Team-Info ")

    sign_in_as(@admin)
    get teams_positions_team_documents_path

    assert_select "#team-#{@team.id}", text: /Updated .+ by #{@manager.callsign}/
    assert_select "#team-#{@team.id} .badge", count: 0
  end

  # A team document can run to megabytes, and the list shows none of it.
  test "the list never loads a document's text" do
    write_document(@team, body: "<p>Never on the list.</p>")

    sign_in_as(@admin)
    assert_queries_match(/`document`\.`tag` (=|IN)/) do
      assert_no_queries_match(/`document`\.(\*|`body`)/) do
        get teams_positions_team_documents_path
      end
    end

    assert_response :success
    assert_no_match "Never on the list.", response.body
  end

  # --- reading -------------------------------------------------------------

  test "a team's document is shown as authored, with the way to edit it" do
    write_document(@team, body: "<h2>Before your first shift</h2><ul><li>Bring a radio</li></ul>", by: @manager)

    sign_in_as(@manager)
    get teams_positions_team_document_path(@team)

    assert_response :success
    assert_select "h1", /#{@team.title}/
    assert_select ".lexxy-content h2", text: "Before your first shift"
    assert_select ".lexxy-content li", text: "Bring a radio"
    assert_select "a[href=?]", teams_positions_edit_team_document_path(@team)
    assert_select "p.me-muted", text: /Last updated .+ by\s+#{@manager.callsign}\./m
  end

  # Documents written through Clubhouse 2 never passed this app's editor, which
  # is the only place the body was cleaned before.
  test "a document written elsewhere is cleaned before it is shown" do
    write_document(@team, body: %(<p>Read <strong>this</strong>.</p><img src="x" onerror="alert(1)"><script>alert(2)</script>))

    sign_in_as(@manager)
    get teams_positions_team_document_path(@team)

    assert_response :success
    assert_select ".lexxy-content strong", text: "this"
    assert_select ".lexxy-content script", count: 0
    assert_select ".lexxy-content [onerror]", count: 0
  end

  test "a team with no document offers to write one" do
    sign_in_as(@manager)
    get teams_positions_team_document_path(@team)

    assert_response :success
    assert_match "No team document has been written for #{@team.title} yet.", response.body
    assert_select "a[href=?]", teams_positions_edit_team_document_path(@team), text: /Write the Document/
  end

  # The callout sits right under the page's h1.
  test "a pointer left behind by a deleted document is called out" do
    @team.update_columns(resource_tag: "dirt-team-info")

    sign_in_as(@manager)
    get teams_positions_team_document_path(@team)

    assert_response :success
    assert_select "h2", text: "The Document Is Missing"
    assert_match "dirt-team-info", response.body
  end

  # With no pointer, a first save would use the derived tag; if a document is
  # already there, the save could only fail, so nothing is offered.
  test "a document already filed under the team's tag, unlinked, is called out instead of a doomed form" do
    write_document(@team)
    @team.update_columns(resource_tag: "")

    sign_in_as(@manager)
    get teams_positions_team_document_path(@team)

    assert_response :success
    assert_select "h2", text: "The Document Tag Is Taken"
    assert_select "a[href=?]", teams_positions_edit_team_document_path(@team), count: 0
  end

  # --- pointers that must not be followed ------------------------------------

  # A team pointed at a document the code reads by name -- here the Motorpool
  # Policy -- must not hand that document to the team's managers.
  test "a pointer at a system document is neither shown nor edited, and a save files the team's own" do
    policy = Document.create!(tag: Document::MOTORPOOL_POLICY_TAG, description: "Motorpool Policy",
                              body: "<p>Drive carefully.</p>",
                              person_create_id: @admin.id, person_update_id: @admin.id)
    @team.update_columns(resource_tag: Document::MOTORPOOL_POLICY_TAG)

    sign_in_as(@manager)
    get teams_positions_team_document_path(@team)

    assert_response :success
    assert_select "h2", text: "The Document Tag Cannot Be Used"
    assert_no_match "Drive carefully.", response.body

    assert_difference "Document.count", 1 do
      post teams_positions_team_document_path(@team), params: { document: { body: "<p>Ours.</p>" } }
    end

    assert_redirected_to teams_positions_team_document_path(@team)
    assert_equal "dirt-team-info", @team.reload.resource_tag
    assert_equal "<p>Drive carefully.</p>", policy.reload.body
  end

  # Writing under a dangling dept-nda pointer would create the NDA itself, which
  # RoleManager reads to withhold roles from every Event Manager who has not signed.
  test "a dangling pointer at a system tag never creates that document" do
    @team.update_columns(resource_tag: Document::DEPT_NDA_TAG)

    sign_in_as(@manager)
    post teams_positions_team_document_path(@team), params: { document: { body: "<p>Ours.</p>" } }

    assert_redirected_to teams_positions_team_document_path(@team)
    assert_not Document.exists?(tag: Document::DEPT_NDA_TAG)
    assert_equal "dirt-team-info", @team.reload.resource_tag
  end

  # Team Records accepts tags no document can have. The first save files the
  # document under the team's own tag instead of failing every time.
  test "a malformed pointer gives way to the team's own tag" do
    @team.update_columns(resource_tag: "dirt team info")

    sign_in_as(@manager)
    post teams_positions_team_document_path(@team), params: { document: { body: "<p>Ours.</p>" } }

    assert_redirected_to teams_positions_team_document_path(@team)
    assert Document.exists?(tag: "dirt-team-info")
    assert_equal "dirt-team-info", @team.reload.resource_tag
  end

  # --- writing -------------------------------------------------------------

  test "a first document is filed under the team's tag, and the team's new pointer is logged" do
    sign_in_as(@manager)

    assert_difference "Document.count", 1 do
      post teams_positions_team_document_path(@team), params: { document: { body: "<p>Read this first.</p>" } }
    end

    assert_redirected_to teams_positions_team_document_path(@team)
    assert_equal "Team document created.", flash[:success]

    document = Document.find_by(tag: "dirt-team-info")
    assert_equal "DIRT Team Document", document.description
    assert_equal "<p>Read this first.</p>", document.body
    assert_equal @manager.id, document.person_create_id
    assert_equal "dirt-team-info", @team.reload.resource_tag

    # Team is not an audited model here; upstream's was, so the row is written by hand.
    log = ActionLog.where(event: "team-update").order(:id).last
    assert_equal "Resource document creation", log.message
    assert_equal [nil, "dirt-team-info"], log.data["resource_tag"]
    assert_equal @team.id, log.data["id"]
  end

  # A form opened before the first save landed -- another manager's, or this
  # one's after Back -- edits the document now there instead of failing on its tag.
  test "a second first-save edits the document the first one created" do
    sign_in_as(@manager)
    post teams_positions_team_document_path(@team), params: { document: { body: "<p>First.</p>" } }

    assert_no_difference "Document.count" do
      post teams_positions_team_document_path(@team), params: { document: { body: "<p>Second.</p>" } }
    end

    assert_redirected_to teams_positions_team_document_path(@team)
    assert_equal "<p>Second.</p>", Document.find_by(tag: "dirt-team-info").body
  end

  test "deleting the document clears the team's pointer, and that is logged" do
    write_document(@team)

    sign_in_as(@manager)

    assert_difference "Document.count", -1 do
      delete teams_positions_team_document_path(@team)
    end

    assert_redirected_to teams_positions_team_document_path(@team)
    assert_equal "Team document deleted.", flash[:success]
    assert_nil @team.reload.resource_tag
    assert_equal ["dirt-team-info", nil], ActionLog.where(event: "team-update").order(:id).last.data["resource_tag"]
  end

  private

  def write_document(team, body: "<p>Read this first.</p>", by: @admin)
    tag = team.build_resource_tag
    document = Document.create!(tag:, description: team.build_resource_title, body:,
                                person_create_id: by.id, person_update_id: by.id)
    team.update_columns(resource_tag: tag)
    document
  end

  def revoke_event_management(person)
    PersonRole.where(person_id: person.id, role_id: Role::EVENT_MANAGEMENT).delete_all
    RoleManager.purge_person(person.id.to_s)
  end
end
