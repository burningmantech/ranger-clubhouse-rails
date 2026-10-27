# frozen_string_literal: true

require "test_helper"

class ActionLogTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 9, 9, 0, 0)
    ActionLog.delete_all
  end

  teardown do
    travel_back
  end

  test "find_for_query filters by target person id" do
    actor = person(:active_ranger)
    target = person(:prospective_ranger)
    other_target = person(:echelon_ranger)

    expected = ActionLog.create!(
      event: "auth-login",
      person: actor,
      target_person: target,
      message: "matching target",
      data: {},
      created_at: Time.zone.local(2026, 4, 9, 8, 0, 0)
    )
    ActionLog.create!(
      event: "auth-login",
      person: actor,
      target_person: other_target,
      message: "other target",
      data: {},
      created_at: Time.zone.local(2026, 4, 9, 8, 1, 0)
    )

    result = ActionLog.find_for_query(target_person_id: target.id)

    assert_equal [expected.id], result[:action_logs].map(&:id)
  end

  test "find_for_query reports previous and next page metadata" do
    actor = person(:active_ranger)

    52.times do |idx|
      ActionLog.create!(
        event: "auth-login",
        person: actor,
        message: "row #{idx}",
        data: {},
        created_at: Time.zone.local(2026, 4, 9, 8, 0, idx)
      )
    end

    first_page = ActionLog.find_for_query({})
    second_page = ActionLog.find_for_query(page: 2)

    assert_nil first_page[:pagy].previous
    assert_equal 2, first_page[:pagy].next
    assert_equal 50, first_page[:action_logs].size

    assert_equal 1, second_page[:pagy].previous
    assert_nil second_page[:pagy].next
    assert_equal 2, second_page[:action_logs].size
  end

  test "find_for_query marks approximate_total only for unfiltered queries" do
    actor = person(:active_ranger)
    ActionLog.create!(
      event: "auth-login",
      person: actor,
      message: "single row",
      data: {},
      created_at: Time.zone.local(2026, 4, 9, 8, 0, 0)
    )

    unfiltered = ActionLog.find_for_query({})
    filtered = ActionLog.find_for_query(person_id: actor.id)

    assert_equal true, unfiltered[:approximate_total]
    assert_equal false, filtered[:approximate_total]
  end

  test "find_for_query normalizes plural role and team enrichment data" do
    actor = person(:active_ranger)
    role = Role.create!(id: 44_444, title: "Action Log Role", new_user_eligible: false)
    team = teams(:mentor_cadre)

    ActionLog.create!(
      event: "team-role-add",
      person: actor,
      target_person: person(:prospective_ranger),
      message: "grant role",
      data: {
        "role_ids" => { "primary" => role.id },
        "team_ids" => [team.id],
        "role_id" => role.id,
        "team_id" => team.id
      },
      created_at: Time.zone.local(2026, 4, 9, 8, 0, 0)
    )

    result = ActionLog.find_for_query(person_id: actor.id)
    row = result[:action_logs].first

    assert_equal [role.id], row.roles.map(&:id)
    assert_equal role.id, row.role.id
    assert_equal [team.id], row.teams.map(&:id)
    assert_equal team.id, row.team.id
    assert_equal team.type, row.team.type
  end
end
