# frozen_string_literal: true

require "test_helper"

class PersonOnSiteTest < ActiveSupport::TestCase
  include PersonTestFactory

  setup do
    Current.reset
    @subject = person(:active_ranger)
    @marker = person(:echelon_ranger)
    Current.person = @marker
  end

  teardown do
    Current.groundhog_day_time = nil
    Current.reset
  end

  test "marking someone on site records the change and who made it" do
    assert_difference -> { rows_for(@subject).count }, 1 do
      mark(@subject, true)
    end

    row = rows_for(@subject).last
    assert_equal PersonOnSite::ON_SITE, row.action
    assert_equal @marker.id, row.creator_person_id
  end

  test "marking someone off site records an off-site row" do
    @subject.update_columns(on_site: true)

    assert_difference -> { rows_for(@subject).count }, 1 do
      mark(@subject, false)
    end
    assert_equal PersonOnSite::OFF_SITE, rows_for(@subject).last.action
  end

  test "a save that leaves on_site alone records nothing" do
    assert_no_difference -> { PersonOnSite.count } do
      @subject.vintage = !@subject.vintage
      @subject.save!(validate: false)
    end
  end

  test "with no one signed in the creator is empty" do
    # Not Current.reset: person is a plain accessor, which reset leaves alone.
    Current.person = nil

    mark(@subject, true)

    assert_nil rows_for(@subject).last.creator_person_id
  end

  test "the change is stamped with the present instant, Groundhog Day included" do
    Current.groundhog_day_time = Time.zone.local(2025, 8, 28, 12, 0, 0)

    mark(@subject, true)

    assert_equal Current.groundhog_day_time, rows_for(@subject).last.created_at
  end

  # With no row, an account created on site would read as off site.
  test "an account created on site records it, and one created off site records nothing" do
    arrived = create_person("Brandnew", on_site: true)
    stayed = create_person("Stayedhome")

    rows = PersonOnSite.where(person: [arrived, stayed]).pluck(:person_id, :action, :creator_person_id)
    assert_equal [[arrived.id, PersonOnSite::ON_SITE, @marker.id]], rows
  end

  # For a bulk writer, whose update_all skips the hook: a person whose history
  # ends otherwise than their flag gets one row, and no history reads as off site.
  test "reconcile ends each history on its person's flag, naming who it is told" do
    at = Time.zone.local(2026, 1, 15, 12)
    left = person(:retired_ranger)
    PersonOnSite.create!(person: left, action: PersonOnSite::ON_SITE, created_at: at - 2.days)
    @subject.update_columns(on_site: true)
    settled = person(:inactive_ranger)

    PersonOnSite.reconcile(at:, creator: @marker)

    assert_equal [PersonOnSite::OFF_SITE, at, @marker.id], newest(left)
    assert_equal [PersonOnSite::ON_SITE, at, @marker.id], newest(@subject)
    assert_not PersonOnSite.exists?(person: settled)
  end

  # update_all and its kin skip Person's hook, so a file that changes on_site
  # that way has to call PersonOnSite.reconcile, or the site log misses every
  # change it makes.
  # An off-site mark closes the stay the on-site mark before it opened. One
  # before any on-site mark, or a second in a row, closes nothing; a second
  # on-site mark in a row changes nothing -- the stay began at the first.
  test "on_site_durations spans each stay from its on-site mark to the off-site mark that ended it" do
    start = Time.zone.local(2025, 8, 20, 12, 0)
    reset = row(PersonOnSite::OFF_SITE, start - 10.days)
    row(PersonOnSite::ON_SITE, start)
    row(PersonOnSite::ON_SITE, start + 1.hour)
    left = row(PersonOnSite::OFF_SITE, start + 2.days)
    again = row(PersonOnSite::OFF_SITE, start + 3.days)

    spans = PersonOnSite.on_site_durations(@subject)

    assert_equal({ left.id => 2.days.to_i }, spans)
    assert_nil spans[reset.id]
    assert_nil spans[again.id]
    assert_empty PersonOnSite.on_site_durations(@marker)
  end

  test "every file that bulk-writes on_site reconciles the log" do
    bulk_write = /\.(update_all|update_columns?|insert_all!?|upsert_all)\b.*\bon_site\b/
    offenders = Dir.glob(Rails.root.join("{app,lib}/**/*.{rb,rake}")).filter_map do |path|
      source = File.read(path)
      next unless source.match?(bulk_write) && !source.include?("PersonOnSite.reconcile")

      path.delete_prefix("#{Rails.root}/")
    end

    assert_empty offenders, "These change on_site without Person's hook and never reconcile the log"
  end

  private

  def newest(person)
    PersonOnSite.history_for(person).pick(:action, :created_at, :creator_person_id)
  end

  def mark(person, on_site)
    person.on_site = on_site
    person.save!(validate: false)
  end

  def rows_for(person) = PersonOnSite.where(person_id: person.id)

  def row(action, created_at)
    PersonOnSite.create!(person: @subject, action:, created_at:)
  end
end
