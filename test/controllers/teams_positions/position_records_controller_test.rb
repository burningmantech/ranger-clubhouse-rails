# frozen_string_literal: true

require "test_helper"

class TeamsPositions::PositionRecordsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    # The index INNER JOINs position_role to role, so every granted role must
    # exist or the permission column silently stays empty.
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)

    @position = positions(:ood_position)
    @team_position = positions(:council_manager)
    @training = positions(:training_lead)

    # Built here rather than in test/fixtures: a global position_role fixture
    # would point at roles that only exist once a test calls ensure_role.
    PositionRole.create!(position_id: @position.id, role_id: Role::MENTOR)
    PositionRole.create!(position_id: @position.id, role_id: Role::EDIT_SLOTS)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # Every type the model accepts must be offered by the filter, or a position
  # of that type is unreachable through it.
  test "every position type is offered by the type filter" do
    get teams_positions_position_records_path

    assert_response :success
    Position::TYPES.each do |type|
      assert_select "select[name=type] option[value=?]", type
    end
  end

  # The table lists an attribute and the filter narrows by it; a label without
  # a matching filter key is a fact the reader cannot act on.
  test "every listed attribute is offered by the attribute filter" do
    helper = TeamsPositions::PositionRecordsHelper

    get teams_positions_position_records_path

    assert_response :success
    helper::ATTRIBUTE_LABELS.each_key do |attribute|
      key = helper.attribute_filter_key(attribute)
      assert helper.attribute_filters.key?(key), "#{key} must be a known filter"
      assert_select "select[name=attribute] option[value=?]", key
    end
  end

  # A flat list, not two polarity groups: the same statements read as questions
  # about the position either way, and side by side they were hard to tell
  # apart.
  test "the attribute filter offers no option groups" do
    get teams_positions_position_records_path

    assert_response :success
    assert_select "select[name=attribute] optgroup", false, "the attribute select must be one flat list"
  end

  # ---------------------------------------------------------------- access

  test "denies access without the admin or tech ninja role" do
    sign_in_as(@outsider)

    get teams_positions_position_records_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Tech Ninja role required to manage position records.", flash[:error]
  end

  test "allows access with only the tech ninja role" do
    sign_in_as(@tech_ninja)

    get teams_positions_position_records_path

    assert_response :success
  end

  # ----------------------------------------------------------------- index

  test "index lists every position with an edit link" do
    get teams_positions_position_records_path

    assert_response :success
    Position.order(:title).each do |position|
      assert_select "tr#position-#{position.id}"
      assert_select "a[href=?]", teams_positions_edit_position_record_path(position)
    end
  end

  test "index renders permission grants for a position that has them" do
    get teams_positions_position_records_path

    assert_response :success
    assert_select "tr#position-#{@position.id}" do
      assert_select "*", text: "Mentor"
      assert_select "*", text: "Edit Slots"
    end
  end

  test "index counts every position in the showing line" do
    get teams_positions_position_records_path

    assert_response :success
    assert_select "*", text: /Showing #{Position.count} of #{Position.count} positions/
  end

  test "index filters by type" do
    @position.update!(type: Position::TYPE_COMMAND)
    @training.update!(type: Position::TYPE_TRAINING)

    get teams_positions_position_records_path(type: Position::TYPE_COMMAND)

    assert_response :success
    assert_select "tr#position-#{@position.id}"
    assert_select "tr#position-#{@training.id}", false, "a Training position must not survive the Command filter"
  end

  test "index filters by active status" do
    @position.update!(active: false)

    get teams_positions_position_records_path(active: "inactive")

    assert_response :success
    assert_select "tr#position-#{@position.id}"
    assert_select "tr#position-#{@training.id}", false, "an active position must not survive the inactive filter"
  end

  test "index filters by team and by having no team" do
    get teams_positions_position_records_path(team: @team_position.team_id.to_s)
    assert_select "tr#position-#{@team_position.id}"
    assert_select "tr#position-#{@position.id}", false, "a position on no team must not survive a team filter"

    get teams_positions_position_records_path(team: "none")
    assert_select "tr#position-#{@position.id}"
    assert_select "tr#position-#{@team_position.id}", false, "a team's position must not survive the no-team filter"
  end

  test "index filters by an attribute" do
    @position.update!(all_rangers: true)
    @training.update!(all_rangers: false)

    get teams_positions_position_records_path(attribute: "all-rangers")

    assert_response :success
    assert_select "tr#position-#{@position.id}"
    assert_select "tr#position-#{@training.id}", false, "a position without the flag must not survive"
  end

  # on_sl_report is the only nullable flag -- a third of the live table holds
  # NULL. `= TRUE` has to exclude those rows the way it excludes FALSE.
  test "a nullable attribute filter drops rows holding NULL" do
    @position.update_column(:on_sl_report, nil)
    @training.update!(on_sl_report: true)

    get teams_positions_position_records_path(attribute: "on-sl-report")

    assert_response :success
    assert_select "tr#position-#{@training.id}"
    assert_select "tr#position-#{@position.id}", false,
                  "a NULL flag means the position does not carry it"
  end

  test "index filters by having a paycode" do
    @position.update!(paycode: "RANGER1")
    @training.update!(paycode: nil)

    get teams_positions_position_records_path(attribute: "paycode")

    assert_response :success
    assert_select "tr#position-#{@position.id}"
    assert_select "tr#position-#{@training.id}", false
  end

  # An empty-string paycode is what a cleared form field writes when it is not
  # normalized, and it is not a paycode.
  test "the paycode filter ignores a blank paycode" do
    @position.update_column(:paycode, "")

    get teams_positions_position_records_path(attribute: "paycode")

    assert_response :success
    assert_select "tr#position-#{@position.id}", false, "a blank paycode is not a paycode"
  end

  test "index filters by a specific permission grant" do
    get teams_positions_position_records_path(role: Role::MENTOR.to_s)

    assert_response :success
    assert_select "tr#position-#{@position.id}"
    assert_select "tr#position-#{@training.id}", false, "a position without the role must not survive"
  end

  test "index filters by granting any or no permissions" do
    get teams_positions_position_records_path(role: "any")
    assert_select "tr#position-#{@position.id}"
    assert_select "tr#position-#{@training.id}", false

    get teams_positions_position_records_path(role: "none")
    assert_select "tr#position-#{@training.id}"
    assert_select "tr#position-#{@position.id}", false
  end

  # The subquery must not multiply rows: the fixture carries two grants.
  test "the any-permission filter lists a multi-grant position once" do
    get teams_positions_position_records_path(role: "any")

    assert_response :success
    assert_select "tr#position-#{@position.id}", count: 1
  end

  test "the permission select offers only roles some position actually grants" do
    ensure_role(Role::VIEW_PII, "View Personal Info")

    get teams_positions_position_records_path

    assert_response :success
    assert_select "select[name=role] option[value=?]", Role::MENTOR.to_s
    assert_select "select[name=role] option[value=?]", Role::VIEW_PII.to_s, false,
                  "an ungranted role must not be offered"
  end

  test "an unknown filter value narrows nothing" do
    get teams_positions_position_records_path(type: "Nonsense", attribute: "has-nothing", role: "bogus")

    assert_response :success
    assert_select "*", text: /Showing #{Position.count} of #{Position.count} positions/
  end

  test "an applied filter draws a chip naming its value" do
    get teams_positions_position_records_path(role: Role::MENTOR.to_s)

    assert_response :success
    assert_select "*", text: /Permission grant: Mentor/
  end

  test "index shows an empty state when the filters match nothing" do
    get teams_positions_position_records_path(type: Position::TYPE_HQ)

    assert_response :success
    assert_select "*", text: /No positions match the current filters/
  end

  # min is NOT NULL default 0 and max is left at 0 by every writer that does
  # not care -- 180 of the 221 live positions. Read literally, that renders
  # "1-0 per slot", a backwards range, on most of the table.
  test "a zero slot bound reads as unset rather than as a range" do
    @position.update!(min: 1, max: 0)
    @training.update!(min: 0, max: 0)
    @team_position.update!(min: 2, max: 2)

    get teams_positions_position_records_path

    assert_response :success
    assert_select "tr#position-#{@position.id}" do
      assert_select "*", text: /1 or more per slot/
    end
    assert_select "tr#position-#{@team_position.id}" do
      assert_select "*", text: /2 per slot/
    end
    assert_select "tr#position-#{@training.id}", html: /per slot/, count: 0
  end

  test "index lists a position's training and parent links by title" do
    @position.update!(training_position_id: @training.id, parent_position_id: @team_position.id)

    get teams_positions_position_records_path

    assert_response :success
    assert_select "tr#position-#{@position.id}" do
      assert_select "*", text: "Training: #{@training.title}"
      assert_select "*", text: "Parent: #{@team_position.title}"
    end
  end

  # ------------------------------------------------------------ new / create

  test "new renders the form" do
    get teams_positions_new_position_record_path

    assert_response :success
    assert_select "form"
    assert_select "input[name=?]", "position[title]"
  end

  test "create saves a position and returns to its row" do
    assert_difference "Position.count", 1 do
      post teams_positions_create_position_record_path,
           params: { position: { title: "Test Position", type: Position::TYPE_FRONTLINE } }
    end

    position = Position.find_by(title: "Test Position")
    assert_redirected_to teams_positions_position_records_path(anchor: "position-#{position.id}")
  end

  test "create re-renders with an error when the title is blank" do
    assert_no_difference "Position.count" do
      post teams_positions_create_position_record_path,
           params: { position: { title: "", type: Position::TYPE_FRONTLINE } }
    end

    assert_response :unprocessable_entity
  end

  # Posted to the action the FORM emits, not a hand-built URL: the filter only
  # survives if the rendered action carries it, and a test that appends the
  # query itself passes whether or not it does.
  test "the new form posts to an action carrying the reader's filters" do
    get teams_positions_new_position_record_path(active: "active")

    assert_response :success
    action = css_select("form[action*='position-records']").first["action"]

    assert_includes action, "active=active", "the form must carry the filter to the create action"

    post action, params: { position: { title: "Filtered Position", type: Position::TYPE_FRONTLINE } }

    position = Position.find_by(title: "Filtered Position")
    assert_redirected_to teams_positions_position_records_path(active: "active",
                                                               anchor: "position-#{position.id}")
  end

  test "the edit form posts to an action carrying the reader's filters" do
    position = positions(:ood_position)
    get teams_positions_edit_position_record_path(position, active: "inactive")

    assert_response :success
    action = css_select("form[action*='position-records']").first["action"]

    assert_includes action, "active=inactive"

    patch action, params: { position: { title: position.title, type: position.type } }
    assert_redirected_to teams_positions_position_records_path(active: "inactive",
                                                               anchor: "position-#{position.id}")
  end

  # ----------------------------------------------------------- edit / update

  test "edit renders the form for an existing position" do
    get teams_positions_edit_position_record_path(@position)

    assert_response :success
    assert_select "input[name=?][value=?]", "position[title]", @position.title
  end

  test "update saves both sign-up page headers" do
    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type,
                                ranger_scheduling_header: "<p>Bring water</p>",
                                applicant_scheduling_header: "<p>Welcome</p>" } }

    assert_redirected_to teams_positions_position_records_path(anchor: "position-#{@position.id}")
    assert_equal "<p>Bring water</p>", @position.reload.ranger_scheduling_header
    assert_equal "<p>Welcome</p>", @position.applicant_scheduling_header
  end

  test "update keeps an emoji in a header" do
    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type,
                                ranger_scheduling_header: "<p>Bring water 🚰</p>" } }

    assert_redirected_to teams_positions_position_records_path(anchor: "position-#{@position.id}")
    assert_equal "<p>Bring water 🚰</p>", @position.reload.ranger_scheduling_header
  end

  # The form always posts both editors, and an empty one posts "<p><br></p>":
  # that must read as the NULL it replaces, or every position's first save
  # logs two header changes nobody made.
  test "update with untouched empty editors stores no header and logs no change" do
    assert_no_difference -> { ActionLog.where(event: "position-update").count } do
      patch teams_positions_position_record_path(@position),
            params: { position: { title: @position.title, type: @position.type,
                                  ranger_scheduling_header: "<p><br></p>",
                                  applicant_scheduling_header: "<p><br></p>" } }
    end

    assert_redirected_to teams_positions_position_records_path(anchor: "position-#{@position.id}")
    assert_nil @position.reload.ranger_scheduling_header
    assert_nil @position.applicant_scheduling_header
  end

  test "update saves changes" do
    patch teams_positions_position_record_path(@position),
          params: { position: { title: "Renamed Position", type: @position.type } }

    assert_redirected_to teams_positions_position_records_path(anchor: "position-#{@position.id}")
    assert_equal "Renamed Position", @position.reload.title
  end

  test "update reports a cross-field conflict rather than saving" do
    patch teams_positions_position_record_path(@position),
          params: { position: { title: "Renamed In A Doomed Save", type: @position.type,
                                parent_position_id: @position.id.to_s } }

    assert_response :unprocessable_entity
    assert_nil @position.reload.parent_position_id
    assert_not_equal "Renamed In A Doomed Save", @position.title,
                     "nothing may persist from a rejected save"
  end

  # Reachable only by a Tech Ninja now that the flag is gated, but the rule
  # still has to fire for one: the position would demand a training pass with
  # no training to pass.
  test "update reports requiring training with no training position" do
    sign_in_as(@tech_ninja)

    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type,
                                require_training_for_roles: "1", training_position_id: "" } }

    assert_response :unprocessable_entity
    assert_not @position.reload.require_training_for_roles
  end

  # ------------------------------------------------- ART mentoring flags

  test "the form offers the ART mentoring flags" do
    get teams_positions_edit_position_record_path(@position)

    assert_response :success
    %w[has_art_mentoring is_art_mentor is_art_mentee].each do |flag|
      assert_select "input[type=checkbox][name=?]", "position[#{flag}]"
    end
  end

  test "update makes a position its team's ART mentee position" do
    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type,
                                team_id: teams(:green_dot_cadre).id.to_s, is_art_mentee: "1" } }

    assert_redirected_to teams_positions_position_records_path(anchor: "position-#{@position.id}")
    assert @position.reload.is_art_mentee
  end

  test "update refuses a second ART mentee position on one team, naming the first" do
    Position.create!(title: "Green Dot Mentee", type: Position::TYPE_FRONTLINE,
                     team: teams(:green_dot_cadre), is_art_mentee: true)

    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type,
                                team_id: teams(:green_dot_cadre).id.to_s, is_art_mentee: "1" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "Green Dot Mentee is already the ART mentee position for this team"
    assert_not @position.reload.is_art_mentee
  end

  # ---------------------------------------------------- permission grants

  test "a tech ninja sees the permission checkboxes and may change grants" do
    sign_in_as(@tech_ninja)

    get teams_positions_edit_position_record_path(@position)
    assert_response :success
    # The row is the label, so min-h-9 is what makes the 36px tap target: a
    # bare checkbox is roughly half that.
    assert_select "label.min-h-9 input[name=?]", "position[role_ids][]"

    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type,
                                role_ids: [Role::MENTOR.to_s] } }

    assert_equal [Role::MENTOR], PositionRole.where(position_id: @position.id).pluck(:role_id)
  end

  test "a plain admin sees an explainer instead of the checkboxes" do
    get teams_positions_edit_position_record_path(@position)

    assert_response :success
    assert_select "input[type=checkbox][name=?]", "position[role_ids][]", false,
                  "a non-tech-ninja must not be offered the permission checkboxes"
    assert_select "*", text: /Only the Tech Team can change permission grants/
  end

  # The form never offers these to a plain admin, so a submission carrying them
  # is a crafted one. Accepting it would widen how an existing grant behaves
  # without touching the grant list the page does gate.
  test "a plain admin cannot change how permission grants behave" do
    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type,
                                require_signin_for_roles: "1" } }

    assert_not @position.reload.require_signin_for_roles
  end

  test "a tech ninja can change how permission grants behave" do
    sign_in_as(@tech_ninja)

    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type,
                                require_signin_for_roles: "1" } }

    assert @position.reload.require_signin_for_roles
  end

  test "a plain admin posting permission grants changes nothing" do
    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type, role_ids: [] } }

    assert_equal [Role::MENTOR, Role::EDIT_SLOTS].sort,
                 PositionRole.where(position_id: @position.id).pluck(:role_id).sort
  end

  # Reading a malformed submission as "no grants" would silently revoke every
  # one of them; reading it as "field absent" would silently ignore the reader.
  test "a malformed permission submission is reported, not guessed at" do
    sign_in_as(@tech_ninja)

    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type,
                                role_ids: { "0" => "1" } } }

    assert_response :unprocessable_entity
    assert_equal 2, PositionRole.where(position_id: @position.id).count
  end

  test "role ids that are not ids are reported, not dropped" do
    sign_in_as(@tech_ninja)

    patch teams_positions_position_record_path(@position),
          params: { position: { title: @position.title, type: @position.type, role_ids: ["", "abc"] } }

    assert_response :unprocessable_entity
    assert_match "were not submitted correctly", response.body
    assert_equal 2, PositionRole.where(position_id: @position.id).count
  end

  # A plain admin cannot touch require_training_for_roles, so offering them a
  # "None" they are not allowed to pick dead-ends the page: the save fails on a
  # checkbox their form never renders, and nothing there can resolve it.
  test "a plain admin cannot clear a training position they are not allowed to unset" do
    @position.update_columns(require_training_for_roles: true,
                             training_position_id: positions(:training_lead).id)

    get teams_positions_edit_position_record_path(@position)

    assert_response :success
    assert_select "select[name=?] option[value='']", "position[training_position_id]", false,
                  "the option that cannot be saved must not be offered"
  end

  test "a tech ninja may still clear the training position" do
    sign_in_as(@tech_ninja)
    @position.update_columns(require_training_for_roles: true,
                             training_position_id: positions(:training_lead).id)

    get teams_positions_edit_position_record_path(@position)

    assert_response :success
    assert_select "select[name=?] option[value='']", "position[training_position_id]"
  end

  # --------------------------------------------------------------- destroy

  test "destroy deletes the position and returns to the index" do
    position = Position.create!(title: "ZZ Doomed", type: Position::TYPE_OTHER)

    delete teams_positions_position_record_path(position)

    assert_redirected_to teams_positions_position_records_path
    assert_not Position.exists?(position.id)
  end

  # timesheet.position_id is NOT NULL, so the rows cannot be released and
  # deleting them would erase service history.
  test "a position carrying service history is not deletable" do
    position = Position.create!(title: "ZZ Rangered", type: Position::TYPE_OTHER)
    Timesheet.create!(person_id: @admin.id, position_id: position.id,
                      on_duty: Time.current - 2.hours, additional_notes: "Probe entry")

    get teams_positions_edit_position_record_path(position)

    assert_response :success
    assert_select "a[href=?][data-turbo-confirm]", teams_positions_position_record_path(position), false,
                  "the delete must not be offered"
    assert_select "*", text: /erase service history/, message: "the reason must stand in its place"

    delete teams_positions_position_record_path(position)

    assert_response :unprocessable_entity
    assert Position.exists?(position.id)
  end

  test "the delete confirmation names the shifts and grants that go with it" do
    position = Position.create!(title: "ZZ Doomed", type: Position::TYPE_OTHER)
    begins = Time.zone.parse("2024-08-25 12:00:00")
    Slot.create!(position_id: position.id, begins:, ends: begins + 4.hours,
                 description: "Test shift", max: 5, timezone: "America/Los_Angeles",
                 timezone_abbr: "PDT")
    PersonPosition.create!(person_id: @admin.id, position_id: position.id)

    get teams_positions_edit_position_record_path(position)

    assert_response :success
    # The message lives in the delete link's data-turbo-confirm attribute, not
    # in the page text -- asserting against the body instead matches the hero's
    # own counts and passes whatever the dialog says.
    confirm = css_select("a[data-turbo-confirm]").map { |link| link["data-turbo-confirm"] }.join
    assert_includes confirm, "1 shift"
    assert_includes confirm, "the grants held by 1 person"
    assert_includes confirm, "cannot be undone"
  end

  test "the delete confirmation names the Shift Coverage lists the position is taken out of" do
    position = Position.create!(title: "ZZ Doomed", type: Position::TYPE_OTHER)
    shift_coverage_group(:command).update_columns(base_position_ids: [position.id])
    shift_coverage_position(:command_ts).update_columns(position_ids: [[position.id]])
    shift_coverage_position(:command_ood).update_columns(position_ids: [[position.id, "Probe"]])

    get teams_positions_edit_position_record_path(position)

    assert_response :success
    confirm = css_select("a[data-turbo-confirm]").map { |link| link["data-turbo-confirm"] }.join
    assert_includes confirm, "It is also taken out of 1 shift type and 2 posts in Shift Coverage."
  end
end
