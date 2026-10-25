# frozen_string_literal: true

require "test_helper"

# RoleManager caches a person's role set indefinitely (config/cache.yml sets no
# max_age), and ApplicationController re-reads it on every request. Any grant or
# revoke that feeds that set must purge it, or a revoked permission survives
# until something else flushes the cache.
#
# These tests need a real store -- the test env is :null_store, which silently
# no-ops and hides exactly this class of bug.
class RoleCacheInvalidationTest < ActiveSupport::TestCase
  include CacheTestHelper
  include TrainingSlotTestHelper

  setup do
    Current.reset
    Current.person = person(:auditor_ranger)
    @person = person(:active_ranger)
    @team = teams(:mentor_cadre)
    @position = positions(:ood_position)
  end

  teardown { Current.reset }

  test "PersonRole.clear_cache purges the key RoleManager actually writes" do
    with_cache_store do |cache|
      key = RoleManager.cache_key(@person.id)
      cache.write(key, [[], [], []])

      PersonRole.clear_cache(@person.id)

      assert_not cache.exist?(key), "PersonRole.clear_cache left the cached role set behind"
    end
  end

  test "granting and revoking a position purges the cached role set" do
    with_cache_store do |cache|
      key = seed_role_cache

      PersonPosition.add_ids_to_person(@person.id, [@position.id], "test grant")
      assert_not cache.exist?(key), "granting a position left a stale role set cached"

      RoleManager.retrieve(@person)
      PersonPosition.remove_ids_from_person(@person.id, [@position.id], "test revoke")
      assert_not cache.exist?(key), "revoking a position left a stale role set cached"
    end
  end

  # An inactive position confers nothing, so deactivating one is a revoke.
  test "saving a position purges the cached role set" do
    with_cache_store do |cache|
      key = seed_role_cache

      @position.active = false
      assert PositionManagement.save(@position), @position.errors.full_messages.to_sentence

      assert_not cache.exist?(key), "deactivating a position left a stale role set cached"
    end
  end

  test "joining and leaving a team purges the cached role set" do
    with_cache_store do |cache|
      key = seed_role_cache

      PersonTeam.add_person(@team.id, @person.id, "test join")
      assert_not cache.exist?(key), "joining a team left a stale role set cached"

      RoleManager.retrieve(@person)
      PersonTeam.remove_person(@team.id, @person.id, "test leave")
      assert_not cache.exist?(key), "leaving a team left a stale role set cached"
    end
  end

  # Read from the tables themselves, not ROLE_SETTINGS, so a derivation that
  # drops a table fails here.
  test "saving any setting the role rule tables read purges the cached role set" do
    settings = RoleManager::CONFERRED_ROLES.values.map(&:last) | RoleManager::SETTING_GATED_ROLES.values

    with_cache_store do |cache|
      settings.each do |name|
        key = seed_role_cache

        Setting.find_or_initialize_by(name:).update!(value: "true")

        assert_not cache.exist?(key), "saving #{name} left a stale role set cached"
      end
    end
  end

  # Training.did_person_pass_for_year? reads trainee verdicts, trainer
  # attendance, and the position, year and active flag of the slots they sit on.
  test "training verdicts, trainer attendance and slot changes purge the cached role set" do
    session = create_slot(@position, begins: Time.zone.local(Current.year, 6, 14, 9))
    trainer_slot = create_slot(positions(:non_eligible_position), begins: Time.zone.local(Current.year, 6, 14, 9))

    with_cache_store do |cache|
      key = seed_role_cache
      verdict = TraineeStatus.create!(person_id: @person.id, slot_id: session.id, status: TraineeStatus::STATUS_PASSED)
      assert_not cache.exist?(key), "scoring a trainee left a stale role set cached"

      key = seed_role_cache
      verdict.update!(status: TraineeStatus::STATUS_NOT_PASSED)
      assert_not cache.exist?(key), "correcting a verdict left a stale role set cached"

      key = seed_role_cache
      attendance = TrainerStatus.create!(person_id: @person.id, slot_id: session.id, trainer_slot_id: trainer_slot.id,
                                         status: TrainerStatus::STATUS_ATTENDED)
      assert_not cache.exist?(key), "marking a trainer attended left a stale role set cached"

      key = seed_role_cache
      attendance.update!(status: TrainerStatus::STATUS_NO_SHOW)
      assert_not cache.exist?(key), "correcting a trainer to no-show left a stale role set cached"

      key = seed_role_cache
      trainer_slot.update!(active: false)
      assert_not cache.exist?(key), "deactivating a trainer's slot left a stale role set cached"

      key = seed_role_cache
      session.update!(begins: session.begins - 1.year, ends: session.ends - 1.year)
      assert_not cache.exist?(key), "moving a session to another year left a stale role set cached"

      key = seed_role_cache
      session.update!(position_id: positions(:non_eligible_position).id)
      assert_not cache.exist?(key), "moving a session to another position left a stale role set cached"

      key = seed_role_cache
      session.update!(description: "Renamed")
      assert cache.exist?(key), "an edit that changes no training result flushed the role cache"

      session.destroy!
      assert_not cache.exist?(key), "deleting a session left a stale role set cached"
    end
  end

  test "saving an unrelated setting leaves the cached role set alone" do
    with_cache_store do |cache|
      key = seed_role_cache

      Setting.find_or_initialize_by(name: Setting::RADIO_INFO_AVAILABLE).update!(value: "true")

      assert cache.exist?(key), "an unrelated setting flushed the role cache"
    end
  end

  test "creating and destroying the dept-nda document purges the cached role set" do
    with_cache_store do |cache|
      key = seed_role_cache

      document = create_document(Document::DEPT_NDA_TAG)
      assert_not cache.exist?(key), "adding the NDA document left a stale role set cached"

      RoleManager.retrieve(@person)
      document.destroy!
      assert_not cache.exist?(key), "removing the NDA document left a stale role set cached"
    end
  end

  test "renaming a tag away from dept-nda purges the cached role set" do
    document = create_document(Document::DEPT_NDA_TAG)

    with_cache_store do |cache|
      key = seed_role_cache

      document.update!(tag: "retired-nda")

      assert_not cache.exist?(key), "renaming the NDA tag left a stale role set cached"
    end
  end

  test "an unrelated document leaves the cached role set alone" do
    with_cache_store do |cache|
      key = seed_role_cache

      create_document(Document::MOTORPOOL_POLICY_TAG).update!(body: "revised")

      assert cache.exist?(key), "an unrelated document flushed the role cache"
    end
  end

  # ROLE_SETTINGS is derived from CONFERRED_ROLES and SETTING_GATED_ROLES, so a
  # setting read through those tables is listed by construction. A direct read
  # would bypass both, and saving that setting would leave stale role sets.
  test "RoleManager reads settings only through its rule tables" do
    source = File.read(Rails.root.join("app/lib/role_manager.rb"))

    assert_no_match(/Setting\.get_value\(Setting::/, source,
                    "read a Setting directly; add the rule to CONFERRED_ROLES or SETTING_GATED_ROLES so ROLE_SETTINGS purges on it")
  end

  private

  # person_create_id / person_update_id are NOT NULL in the schema even though
  # the associations are declared optional.
  def create_document(tag)
    Document.create!(tag: tag, description: "#{tag} test document", body: "body",
                     person_create_id: Current.person.id, person_update_id: Current.person.id)
  end

  # Populate the cache through the real reader, so the test breaks if the reader
  # and the purgers ever disagree about the key again.
  def seed_role_cache
    PersonPosition.where(person_id: @person.id, position_id: @position.id).delete_all
    PersonTeam.where(person_id: @person.id, team_id: @team.id).delete_all

    key = RoleManager.cache_key(@person.id)
    RoleManager.retrieve(@person)
    assert Rails.cache.exist?(key), "RoleManager did not cache the role set; test cannot prove invalidation"
    key
  end
end
