# frozen_string_literal: true

require "test_helper"

class PersonPasskeyTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    Current.reset
    @person = person(:active_ranger)
    @admin = person(:auditor_ranger)
  end

  teardown do
    Current.reset
  end

  # --- validations ---

  test "a passkey with an owner, an id, a key and a nickname is valid" do
    assert_predicate build_passkey, :valid?
  end

  test "a nickname is required, and the message stands on its own" do
    passkey = build_passkey(nickname: "  ")

    assert_not passkey.valid?
    assert_equal ["Give the passkey a nickname."], passkey.errors[:nickname]
  end

  test "space around and inside a nickname is tidied before it is stored" do
    assert_equal "My iPhone", build_passkey(nickname: "  My   iPhone ").nickname
  end

  test "a nickname longer than its column is refused rather than cut" do
    assert_predicate build_passkey(nickname: "a" * PersonPasskey::NICKNAME_LIMIT), :valid?

    passkey = build_passkey(nickname: "a" * (PersonPasskey::NICKNAME_LIMIT + 1))
    assert_not passkey.valid?
    assert_equal ["The nickname must be 50 characters or fewer."], passkey.errors[:nickname]
  end

  test "an id longer than the standard allows is refused rather than cut" do
    assert_predicate build_passkey(external_id: "a" * PersonPasskey::EXTERNAL_ID_LIMIT), :valid?
    assert_not build_passkey(external_id: "a" * (PersonPasskey::EXTERNAL_ID_LIMIT + 1)).valid?
  end

  test "an id and a public key are required" do
    passkey = build_passkey(external_id: "", public_key: "")

    assert_not passkey.valid?
    assert_predicate passkey.errors[:external_id], :any?
    assert_predicate passkey.errors[:public_key], :any?
  end

  test "who added it is optional, and is an Admin when it is set" do
    assert_nil build_passkey.tap(&:save!).added_by
    assert_equal @admin, build_passkey(added_by: @admin).tap(&:save!).reload.added_by
  end

  # The Admin's account can be deleted later. The passkey they put on someone
  # else's account must go on saying so.
  test "a passkey an Admin enrolled says so even after that Admin's account is gone" do
    own = build_passkey.tap(&:save!)
    enrolled = build_passkey(added_by: @admin).tap(&:save!)
    orphaned = build_passkey(added_by_person_id: Person.maximum(:id) + 1).tap(&:save!)

    assert_not own.added_by_admin?
    assert_predicate enrolled, :added_by_admin?
    assert_nil orphaned.reload.added_by
    assert_predicate orphaned, :added_by_admin?
  end

  # --- the id column ---

  # base64url ids differ by capitals alone, and the database's usual collation
  # ignores capitals. If the column ever loses its byte-for-byte collation,
  # the second save here collides and the lookups answer with the wrong row.
  test "ids that differ only by capitals are different passkeys" do
    upper = build_passkey(external_id: "AbCdEf").tap(&:save!)
    lower = build_passkey(external_id: "aBcDeF").tap(&:save!)

    assert_equal upper, PersonPasskey.find_by(external_id: "AbCdEf")
    assert_equal lower, PersonPasskey.find_by(external_id: "aBcDeF")
    assert_nil PersonPasskey.find_by(external_id: "abcdef")
  end

  test "no two accounts can hold the same passkey" do
    build_passkey(external_id: "only-once").save!

    assert_raises(ActiveRecord::RecordNotUnique) do
      build_passkey(person: @admin, external_id: "only-once").save!
    end
  end

  # --- the limit ---

  test "an account holds ten passkeys and no more" do
    PersonPasskey::MAX_PER_PERSON.times { build_passkey.save! }

    passkey = build_passkey
    assert_not passkey.valid?
    assert_equal ["An account can hold 10 passkeys. Remove one before adding another."], passkey.errors[:base]

    assert_predicate build_passkey(person: @admin), :valid?, "the limit is per account"
  end

  test "the limit stops new passkeys, not changes to the ones already there" do
    passkeys = Array.new(PersonPasskey::MAX_PER_PERSON) { build_passkey.tap(&:save!) }

    assert passkeys.first.update(nickname: "Renamed")
  end

  # --- user_handle ---

  test "the user handle is the person's id as unpadded base64url" do
    handle = PersonPasskey.user_handle(@person)

    assert_equal @person.id.to_s, Base64.urlsafe_decode64(handle)
    assert_no_match(/[=+\/]/, handle)
    assert_operator Base64.urlsafe_decode64(handle).bytesize, :<=, 64, "the standard allows 64 bytes"
  end

  # --- used! ---

  test "a sign-in records the counter and the time without an audit line" do
    passkey = build_passkey.tap(&:save!)
    ActionLog.delete_all

    freeze_time do
      passkey.used!(7)

      passkey.reload
      assert_equal 7, passkey.sign_count
      assert_equal Time.current, passkey.last_used_at
    end
    assert_equal 0, ActionLog.count, "a sign-in is not an edit"
  end

  # --- audit log ---

  test "adding a passkey is recorded against the account, without the public key" do
    ActionLog.delete_all
    Current.person = @admin

    passkey = build_passkey(added_by: @admin).tap(&:save!)

    entry = ActionLog.where(event: "person-passkey-create").last
    assert_not_nil entry
    assert_equal @admin.id, entry.person_id
    assert_equal @person.id, entry.target_person_id
    assert_equal passkey.nickname, entry.data["nickname"]
    assert_equal @admin.id, entry.data["added_by_person_id"]
    # Name the column outright. Reading the list the guard is built from would
    # make this pass by doing nothing the moment that list went empty.
    assert_includes PersonPasskey.audit_exclude, "public_key"
    assert_not entry.data.key?("public_key")
  end

  test "removing a passkey is recorded against the account it was on" do
    passkey = build_passkey.tap(&:save!)
    ActionLog.delete_all
    Current.person = @admin

    passkey.destroy

    entry = ActionLog.where(event: "person-passkey-delete").last
    assert_not_nil entry
    assert_equal @admin.id, entry.person_id
    assert_equal @person.id, entry.target_person_id
    assert_equal passkey.nickname, entry.data["nickname"]
  end

  # --- the notice is the controllers' to send ---

  # Deleting an account takes its passkeys with it. Were the model to send the
  # notice, that account would be written to once for every passkey it had.
  test "saving or destroying a passkey emails no one" do
    assert_no_enqueued_emails do
      build_passkey.tap(&:save!).destroy
    end
  end

  # --- Person#passkeys ---

  test "an account's passkeys go when the account goes" do
    association = Person.reflect_on_association(:passkeys)

    assert_equal "PersonPasskey", association.class_name
    assert_equal :destroy, association.options[:dependent]
    assert_equal [build_passkey.tap(&:save!)], @person.passkeys.to_a
  end

  private

  def build_passkey(**attributes)
    PersonPasskey.new({
      person: @person,
      external_id: SecureRandom.urlsafe_base64(16),
      public_key: SecureRandom.urlsafe_base64(77),
      nickname: "iPhone"
    }.merge(attributes))
  end
end
