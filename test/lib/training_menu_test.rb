# frozen_string_literal: true

require "test_helper"

# TrainingMenu: the per-position category titles, the position filter, and the
# TrainingPolicy-derived visibility roles.
class TrainingMenuTest < ActiveSupport::TestCase
  test "In-Person Training titles the dirt category" do
    dirt = Position.new(id: Position::TRAINING, title: "Training")

    assert_equal "In-Person Training", TrainingMenu.category_title(dirt)
  end

  test "ART categories strip the Training suffix" do
    green_dot = Position.new(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training")

    assert_equal "ART Green Dot", TrainingMenu.category_title(green_dot)
  end

  test "the Training token is stripped anywhere, along with dangling separators" do
    radio = Position.new(id: Position::TRAINING_RADIO_PRACTICE, title: "Training - Radio Practice")

    assert_equal "ART Radio Practice", TrainingMenu.category_title(radio)
  end

  test "definitions cover active training positions only, In-Person Training first" do
    Position.create!(id: Position::TRAINING, title: "Training",
                     type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                     type: Position::TYPE_TRAINING, active: true)
    # Trainer positions are also type Training and must never get a category.
    Position.create!(id: Position::GREEN_DOT_TRAINER, title: "Green Dot Trainer",
                     type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::SANDMAN_TRAINING, title: "Sandman Training",
                     type: Position::TYPE_TRAINING, active: false)

    titles = TrainingMenu.definitions.map { |category| category[:title] }

    assert_equal ["In-Person Training", "ART Green Dot"], titles
  end

  test "definitions carry the slug-based sessions landing path and prefix matching" do
    Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                     type: Position::TYPE_TRAINING, active: true)

    item = TrainingMenu.definitions.first[:sections].first[:items].first

    assert_equal "/training/green-dot", item[:path]
    assert item[:active_prefix]
  end

  # The document stands for the position, not for a year, so the item must not
  # carry the request's ?year= the way its neighbors do.
  test "definitions carry a yearless Trainer Resources item beside Sessions" do
    Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                     type: Position::TYPE_TRAINING, active: true)

    item = TrainingMenu.definitions.first[:sections].first[:items].second

    assert_equal "Trainer Resources", item[:title]
    assert_equal "/training/green-dot/resources", item[:path]
    assert item[:active_prefix]
    assert_nil item[:year_scoped]
  end

  test "Current Mentees appears only for ARTs that grant mentee positions" do
    green_dot = Position.new(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training")
    sandman = Position.new(id: Position::SANDMAN_TRAINING, title: "Sandman Training")
    dirt = Position.new(id: Position::TRAINING, title: "Training")

    item = report_items(green_dot).find { |i| i[:title] == "Current Mentees" }

    assert_equal "/training/green-dot/mentees", item[:path]
    # The report is current standing, not a year's activity.
    assert_nil item[:year_scoped]

    # Sandman graduates straight to Sandman; In-Person has no mentees at all.
    assert_nil report_items(sandman).find { |i| i[:title] == "Current Mentees" }
    assert_nil report_items(dirt).find { |i| i[:title] == "Current Mentees" }
  end

  test "dirt visibility takes Trainer, Mentor, or VC; ARTs need the composed interface role" do
    dirt = Position.new(id: Position::TRAINING, title: "Training")
    green_dot = Position.new(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training")

    assert_equal [Role::ADMIN, Role::TRAINER, Role::MENTOR, Role::VC],
                 TrainingMenu.definition(dirt)[:visible_if][:roles]
    assert_equal [Role::ADMIN, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING],
                 TrainingMenu.definition(green_dot)[:visible_if][:roles]
  end

  # The same flag the mentoring controllers check, so the menu never offers a
  # page that would turn the reader away.
  test "Mentoring follows Sessions only for an ART mentoring training" do
    green_dot = Position.new(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training", has_art_mentoring: true)
    sandman = Position.new(id: Position::SANDMAN_TRAINING, title: "Sandman Training")

    items = TrainingMenu.definition(green_dot)[:sections].first[:items]

    assert_equal ["Sessions", "Mentoring", "Trainer Resources"], items.map { |item| item[:title] }
    assert_equal "/training/green-dot/mentoring", items.second[:path]
    assert items.second[:year_scoped]
    assert_not_includes TrainingMenu.definition(sandman)[:sections].first[:items].map { |item| item[:title] }, "Mentoring"
  end

  private

  def report_items(position)
    TrainingMenu.definition(position)[:sections]
                .find { |section| section[:title] == TrainingMenu::REPORTS_TITLE }[:items]
  end
end
