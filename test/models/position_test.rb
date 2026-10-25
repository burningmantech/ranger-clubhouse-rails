# frozen_string_literal: true

require "test_helper"

class PositionTest < ActiveSupport::TestCase
  setup do
    Current.reset
    Current.person = person(:auditor_ranger)
    TeamManager.create!(team: teams(:khaki_team), person: Current.person)
  end

  teardown do
    Current.reset
  end

  def can_manage_titles(is_admin:)
    Position.find_for_query({ can_manage: true }, is_admin: is_admin)
            .select(&:can_manage)
            .map(&:title)
  end

  test "can_manage is only true for positions on a team the person manages" do
    assert_equal [positions(:khaki_supervisor).title], can_manage_titles(is_admin: false)
  end

  test "can_manage is false rather than 0 for an unmanaged position" do
    by_title = Position.find_for_query({ can_manage: true }, is_admin: false).index_by(&:title)

    assert_equal true, by_title[positions(:khaki_supervisor).title].can_manage
    assert_equal false, by_title[positions(:council_manager).title].can_manage
    assert_equal false, by_title[positions(:training_lead).title].can_manage
  end

  test "can_manage is true for every position when the person is an admin" do
    assert_equal Position.count, can_manage_titles(is_admin: true).size
  end

  test "a resource document is named and filed after the position" do
    green_dot = Position.new(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training")

    assert_equal "green-dot-training-resource", green_dot.build_resource_tag
    assert_equal "Green Dot Training Position Document", green_dot.build_resource_title
  end

  # Deliberate divergence from Laravel's Str::kebab, which would split the
  # acronym into "h-q-full-training". Only tags minted here are affected --
  # reads follow the stored resource_tag.
  test "adjacent capitals stay together in a derived tag" do
    assert_equal "hq-full-training-resource",
                 Position.new(title: "HQ Full Training").build_resource_tag
  end

  # A trainer constant outside Position::TRAINERS is invisible to every report
  # that pairs a session with the people who taught it, and the roster grid
  # grades its holders as trainees who never trained. The omission has happened
  # twice already: TROUBLESHOOTER_TRAINER was declared and used by
  # SURVEY_MANAGEMENT_POSITIONS for years while absent from the table.
  #
  # Add to the exemptions only with the reason, never to quiet the failure.
  UNMAPPED_TRAINER_CONSTANTS = {
    MENTOR_RADIO_TRAINER: "a Mentoring position rather than a training one -- it teaches no session"
  }.freeze

  test "every trainer position constant is mapped in Position::TRAINERS" do
    mapped = Position::TRAINERS.values.flatten.to_set

    unmapped = Position.constants(false).grep(/TRAINER/).select { |name|
      id = Position.const_get(name)
      id.is_a?(Integer) && !mapped.include?(id) && !UNMAPPED_TRAINER_CONSTANTS.key?(name)
    }

    assert_empty unmapped,
                 "trainer positions missing from Position::TRAINERS: #{unmapped.join(", ")}. " \
                 "Map each to the training position it teaches, or record why it has none " \
                 "in UNMAPPED_TRAINER_CONSTANTS."
  end

  # ---------------------------------------------------- scheduling headers

  test "the sign-up page header follows the reader's status" do
    position = Position.new(ranger_scheduling_header: "<p>Rangers</p>", applicant_scheduling_header: "<p>Applicants</p>")

    assert_equal "<p>Rangers</p>", position.scheduling_header_for(person(:active_ranger))
    assert_equal "<p>Rangers</p>", position.scheduling_header_for(person(:echelon_ranger))
    assert_equal "<p>Applicants</p>", position.scheduling_header_for(person(:prospective_ranger))
    assert_equal "<p>Applicants</p>", position.scheduling_header_for(person(:alpha_ranger))
    assert_nil position.scheduling_header_for(person(:auditor_ranger))
  end

  test "an empty editor saves no header" do
    position = Position.new(title: "Blank Headers", type: Position::TYPE_FRONTLINE,
                            ranger_scheduling_header: "<p></p>", applicant_scheduling_header: "<p><br></p>")

    assert position.valid?
    assert_nil position.ranger_scheduling_header
    assert_nil position.applicant_scheduling_header
  end

  test "a header with no words, such as a lone divider, saves no header" do
    position = Position.new(title: "Divider Only", type: Position::TYPE_FRONTLINE,
                            ranger_scheduling_header: "<hr>", applicant_scheduling_header: "<p>Hi</p><hr>")

    assert position.valid?
    assert_nil position.ranger_scheduling_header
    assert_equal "<p>Hi</p><hr>", position.applicant_scheduling_header
  end

  test "a header longer than the column is rejected with a message" do
    position = Position.new(title: "Too Long", type: Position::TYPE_FRONTLINE,
                            ranger_scheduling_header: "<p>#{"a" * 65_536}</p>")

    assert_not position.valid?
    assert position.errors.key?(:ranger_scheduling_header)
  end

  # ---------------------------------------------------------- ART mentoring

  # A training pairs the mentor and mentee positions flagged on its own team
  # (Training.mentor_position_id), so a flag means nothing without one.
  test "an ART mentoring flag needs a team" do
    position = Position.new(title: "Mentee Without A Team", type: Position::TYPE_FRONTLINE, is_art_mentee: true)

    assert_not position.valid?
    assert position.errors.key?(:team_id)
  end

  test "a position cannot be both the ART mentor and the ART mentee position" do
    position = Position.new(title: "Both At Once", type: Position::TYPE_FRONTLINE, team: teams(:green_dot_cadre),
                            is_art_mentor: true, is_art_mentee: true)

    assert_not position.valid?
    assert position.errors.key?(:is_art_mentee)
  end

  # Not a frontline position, not a trainer position, and not In-Person
  # Training, which has no graduate role to grant a pass.
  test "only an ART training position can have ART mentoring" do
    team = teams(:green_dot_cadre)
    [Position.new(title: "Not A Training", type: Position::TYPE_FRONTLINE, team:, has_art_mentoring: true),
     Position.new(title: "Green Dot Trainer", type: Position::TYPE_TRAINING, team:, has_art_mentoring: true),
     Position.new(id: Position::TRAINING, title: "Training", type: Position::TYPE_TRAINING, team:,
                  has_art_mentoring: true)].each do |position|
      assert_not position.valid?, position.title
      assert position.errors.key?(:has_art_mentoring), position.title
    end
  end

  # With two on one team the training could not tell which to pair. The one
  # already flagged is named, so the reader knows which to clear.
  test "a team holds one ART mentor position, and another team holds its own" do
    mentor = Position.create!(title: "Green Dot Mentor", type: Position::TYPE_FRONTLINE,
                              team: teams(:green_dot_cadre), is_art_mentor: true)
    assert mentor.valid?, "the flagged position is not its own rival"

    second = Position.new(title: "Second Mentor", type: Position::TYPE_FRONTLINE,
                          team: teams(:green_dot_cadre), is_art_mentor: true)
    assert_not second.valid?
    assert_equal ["Green Dot Mentor is already the ART mentor position for this team"], second.errors[:is_art_mentor]

    second.team = teams(:khaki_team)
    assert second.valid?, second.errors.full_messages.to_sentence
  end
end
