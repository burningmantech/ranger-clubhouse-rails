# frozen_string_literal: true

require "test_helper"

class Scheduling::PositionCreditsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 7, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:echelon_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")
    grant_role(@admin, Role::ADMIN)
    grant_role(@outsider, Role::EDIT_SLOTS)

    @position = positions(:training_lead)
    @other_position = positions(:ood_position)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  def create_credit(position: @position, start_time: "2026-08-25 00:00", end_time: "2026-08-25 23:59", **attrs)
    PositionCredit.create!({ position_id: position.id, start_time:, end_time:,
                             credits_per_hour: 2.5, description: "Morning" }.merge(attrs))
  end

  test "denies access without the admin role" do
    sign_in_as(@outsider)

    get scheduling_position_credits_path

    assert_redirected_to me_root_path
    assert_equal "Admin role required to manage position credits.", flash[:error]
  end

  test "index groups credits by position with counts" do
    create_credit
    create_credit(start_time: "2026-08-26 00:00", end_time: "2026-08-26 23:59")
    create_credit(position: @other_position)

    get scheduling_position_credits_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(@position.title)}/
    assert_select "body", text: /2 credits/
    assert_select "body", text: /#{Regexp.escape(@other_position.title)}/
    assert_select "body", text: /Showing 2 positions with 3 position credits/
  end

  test "index shows an empty state for a year without credits" do
    get scheduling_position_credits_path(year: 2019)

    assert_response :success
    assert_select "body", text: /No position credits were found for 2019/
  end

  test "index exports every credit for the year as csv" do
    create_credit(description: "Burn, baby")
    create_credit(position: @other_position, credits_per_hour: 1.0)
    create_credit(start_time: "2025-08-25 00:00", end_time: "2025-08-25 23:59", description: "Prior year")

    get scheduling_position_credits_path(format: :csv)

    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=" + response.charset
    lines = response.body.split("\n")
    assert_equal "Position,Start,End,Credits,Description", lines.first
    assert_equal 3, lines.size # header + the two 2026 credits
    assert_match(/"Burn, baby"/, response.body) # the comma forces quoting
    assert_match(/2.50/, response.body)
    assert_no_match(/Prior year/, response.body)
  end

  test "position page lists the position's credits" do
    credit = create_credit
    other = create_credit(position: @other_position)

    get scheduling_position_credits_position_path(@position.id, year: 2026)

    assert_response :success
    assert_select "tr#credit-#{credit.id}"
    assert_select "tr#credit-#{other.id}", count: 0
    assert_select "input[name='credit_ids[]'][value=?]", credit.id.to_s
  end

  test "position page filters by day" do
    early = create_credit
    late = create_credit(start_time: "2026-08-27 00:00", end_time: "2026-08-27 23:59")

    get scheduling_position_credits_position_path(@position.id, year: 2026, day: "2026-08-27")

    assert_response :success
    assert_select "tr#credit-#{late.id}"
    assert_select "tr#credit-#{early.id}", count: 0
    assert_select "body", text: /Showing 1 of 2 credits/
    assert_select "body", text: /Day: Thu Aug 27/
  end

  test "position page redirects when the position has no credits at all" do
    get scheduling_position_credits_position_path(0, year: 2026)

    assert_redirected_to scheduling_position_credits_path(year: 2026)
    assert_equal "The position could not be found.", flash[:error]
  end

  test "position page exports the position's credits as csv" do
    create_credit
    create_credit(position: @other_position, description: "Elsewhere")

    get scheduling_position_credits_position_path(@position.id, year: 2026, format: :csv)

    assert_response :success
    assert_equal 2, response.body.split("\n").size
    assert_no_match(/Elsewhere/, response.body)
  end

  test "timeline charts the position's credits only" do
    create_credit(description: "Grave")
    create_credit(position: @other_position, description: "Elsewhere")

    get scheduling_position_credits_position_timeline_path(@position.id, year: 2026)

    assert_response :success
    assert_select ".ct", count: 1
    assert_select ".ct .ct-swatch", minimum: 1 # the legend sits inside the chart, where the palette is declared
    assert_select ".ct", text: /Grave/
    assert_select "[data-tip*='Elsewhere']", count: 0
    assert_select "table tbody tr", minimum: 1
    assert_select "a[href=?]", scheduling_position_credits_position_timeline_path(@position.id, year: 2026, format: :csv)
  end

  test "timeline exports the rate table as csv" do
    create_credit(description: "Grave", start_time: "2026-08-25 00:00", end_time: "2026-08-26 00:00")
    create_credit(position: @other_position, description: "Elsewhere")

    get scheduling_position_credits_position_timeline_path(@position.id, year: 2026, format: :csv)

    assert_response :success
    assert_equal ["From,To,Hours,Credits Per Hour,Made Up Of",
                  "2026-08-25 00:00,2026-08-26 00:00,24.00,2.50,Grave 2.50"], response.body.split("\n")
  end

  test "timeline shows an empty state when the position has no credits that year" do
    create_credit(start_time: "2025-08-25 00:00", end_time: "2025-08-25 23:59")

    get scheduling_position_credits_position_timeline_path(@position.id, year: 2026)

    assert_response :success
    assert_select "body", text: /credits were found for 2026/
    assert_select ".ct", count: 0
  end

  test "new preselects the position it was opened from" do
    get scheduling_new_position_credit_path(position_id: @position.id, year: 2026)

    assert_response :success
    assert_select "select[name='position_credit[position_id][]'][multiple]" do
      assert_select "option[selected][value=?]", @position.id.to_s
    end
  end

  test "creates a credit for a single position" do
    assert_difference "PositionCredit.count", 1 do
      post scheduling_create_position_credit_path(year: 2026), params: {
        position_credit: {
          position_id: ["", @position.id.to_s],
          start_time: "2026-08-25 00:00",
          end_time: "2026-08-25 23:59",
          credits_per_hour: "3.25",
          description: "Event week"
        }
      }
    end

    credit = PositionCredit.order(:id).last
    assert_equal @position.id, credit.position_id
    assert_equal 3.25, credit.credits_per_hour
    assert_equal 2026, credit.reload.start_year
    assert_redirected_to scheduling_position_credits_position_path(@position.id, year: 2026,
                                                              anchor: "credit-#{credit.id}")
    assert_equal "1 position credit created.", flash[:success]
  end

  test "creates one credit per selected position" do
    assert_difference "PositionCredit.count", 2 do
      post scheduling_create_position_credit_path(year: 2026), params: {
        position_credit: {
          position_id: ["", @position.id.to_s, @other_position.id.to_s],
          start_time: "2026-08-25 00:00",
          end_time: "2026-08-25 23:59",
          credits_per_hour: "2",
          description: "Event week"
        }
      }
    end

    assert_equal [@position.id, @other_position.id].sort,
                 PositionCredit.order(:id).last(2).map(&:position_id).sort
    assert_redirected_to scheduling_position_credits_path(year: 2026)
    assert_equal "2 position credits created.", flash[:success]
  end

  test "create with no position selected is rejected" do
    assert_no_difference "PositionCredit.count" do
      post scheduling_create_position_credit_path(year: 2026), params: {
        position_credit: {
          position_id: [""],
          start_time: "2026-08-25 00:00",
          end_time: "2026-08-25 23:59",
          credits_per_hour: "2",
          description: "Event week"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /Select at least one position for this credit/
  end

  # to_i read "abc" as position 0, which then failed as "must exist", and
  # "#{id}x" as the position itself.
  test "create with position ids that are not ids is rejected as none selected" do
    assert_no_difference "PositionCredit.count" do
      post scheduling_create_position_credit_path(year: 2026), params: {
        position_credit: {
          position_id: ["", "abc", "#{@position.id}x"],
          start_time: "2026-08-25 00:00",
          end_time: "2026-08-25 23:59",
          credits_per_hour: "2",
          description: "Event week"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /Select at least one position for this credit/
  end

  test "create with an ending time before the beginning time is rejected" do
    assert_no_difference "PositionCredit.count" do
      post scheduling_create_position_credit_path(year: 2026), params: {
        position_credit: {
          position_id: [@position.id.to_s],
          start_time: "2026-08-25 12:00",
          end_time: "2026-08-25 06:00",
          credits_per_hour: "2",
          description: "Backwards"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "body", text: /The end time must be after the start time\./
  end

  test "create without a description is rejected" do
    assert_no_difference "PositionCredit.count" do
      post scheduling_create_position_credit_path(year: 2026), params: {
        position_credit: {
          position_id: [@position.id.to_s],
          start_time: "2026-08-25 00:00",
          end_time: "2026-08-25 23:59",
          credits_per_hour: "2",
          description: ""
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "a non-hash position_credit param is refused rather than raising" do
    assert_no_difference "PositionCredit.count" do
      post scheduling_create_position_credit_path(year: 2026), params: { position_credit: "x" }
    end
    assert_response :bad_request

    credit = create_credit

    patch scheduling_position_credit_path(credit, year: 2026), params: { position_credit: "x" }
    assert_response :bad_request
    assert_equal "Morning", credit.reload.description
  end

  test "updates a credit" do
    credit = create_credit

    patch scheduling_position_credit_path(credit, year: 2026), params: {
      position_credit: {
        position_id: @position.id,
        start_time: "2026-08-25 00:00",
        end_time: "2026-08-25 23:59",
        credits_per_hour: "4.5",
        description: "Updated"
      }
    }

    assert_redirected_to scheduling_position_credits_position_path(@position.id, year: 2026,
                                                              anchor: "credit-#{credit.id}")
    assert_equal "Position credit updated.", flash[:success]
    credit.reload
    assert_equal 4.5, credit.credits_per_hour
    assert_equal "Updated", credit.description
  end

  test "update failure re-renders the form" do
    credit = create_credit

    patch scheduling_position_credit_path(credit, year: 2026), params: {
      position_credit: {
        position_id: @position.id,
        start_time: "2026-08-25 12:00",
        end_time: "2026-08-25 06:00",
        credits_per_hour: "4.5",
        description: "Updated"
      }
    }

    assert_response :unprocessable_entity
    assert_equal "Morning", credit.reload.description
  end

  test "moving a credit's beginning time to another year lands on that year's page" do
    credit = create_credit

    patch scheduling_position_credit_path(credit, year: 2026), params: {
      position_credit: {
        position_id: @position.id,
        start_time: "2027-08-25 00:00",
        end_time: "2027-08-25 23:59",
        credits_per_hour: "2.5",
        description: "Morning"
      }
    }

    assert_redirected_to scheduling_position_credits_position_path(@position.id, year: 2027,
                                                              anchor: "credit-#{credit.id}")
  end

  test "destroys a credit" do
    credit = create_credit

    assert_difference "PositionCredit.count", -1 do
      delete scheduling_position_credit_path(credit, year: 2026)
    end

    assert_redirected_to scheduling_position_credits_position_path(@position.id, year: 2026)
    assert_equal "Position credit deleted.", flash[:success]
  end

  test "bulk delete removes only the selected credits for the position and year" do
    doomed = create_credit
    keep = create_credit(start_time: "2026-08-26 00:00", end_time: "2026-08-26 23:59")
    other_position = create_credit(position: @other_position)
    prior_year = create_credit(start_time: "2025-08-25 00:00", end_time: "2025-08-25 23:59")

    assert_difference "PositionCredit.count", -1 do
      delete scheduling_position_credits_position_bulk_delete_path(@position.id, year: 2026),
             params: { credit_ids: [doomed.id, other_position.id, prior_year.id] }
    end

    assert_redirected_to scheduling_position_credits_position_path(@position.id, year: 2026)
    assert_equal "1 position credit deleted.", flash[:success]
    assert_not PositionCredit.exists?(doomed.id)
    assert PositionCredit.exists?(keep.id)
    assert PositionCredit.exists?(other_position.id)
    assert PositionCredit.exists?(prior_year.id)
  end

  test "bulk delete with nothing selected reports an error" do
    create_credit

    assert_no_difference "PositionCredit.count" do
      delete scheduling_position_credits_position_bulk_delete_path(@position.id, year: 2026)
    end

    assert_redirected_to scheduling_position_credits_position_path(@position.id, year: 2026)
    assert_equal "Select at least one position credit to delete.", flash[:error]
  end

  # ActiveRecord reads "#{id}x" as the id, which deleted that credit.
  test "bulk delete with credit ids that are not ids deletes nothing" do
    credit = create_credit

    assert_no_difference "PositionCredit.count" do
      delete scheduling_position_credits_position_bulk_delete_path(@position.id, year: 2026),
             params: { credit_ids: ["", "abc", "#{credit.id}x"] }
    end

    assert_equal "Select at least one position credit to delete.", flash[:error]
  end
end
