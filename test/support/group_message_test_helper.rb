# frozen_string_literal: true

# Group threads built as MessagesConcern builds them (PersonMessage.new_group_thread).
# A minute old by default: rows and last reads are kept to the second, and a
# reply in the same second as a last read counts as read.
module GroupMessageTestHelper
  include ActiveJob::TestHelper

  def create_group_thread(author, *others, subject: "Burn night crew", body: "Who has the radios?",
                          created_at: 1.minute.ago, **attributes)
    PersonMessage.new_group_thread(author, others, creator_person: author, subject:, body:, created_at:,
                                                   message_type: PersonMessage::MESSAGE_TYPE_CONTACT, **attributes)
                 .tap(&:save!)
  end

  # A thread sent to a team, and to anyone named beside it; the team's
  # eligible members join it as it is saved (PersonMessage#sync_team_members!).
  def create_team_thread(author, team, *named, **)
    create_group_thread(author, *named, recipient_team: team, **)
  end

  # Who the thread's teams put in it: each member's person id, with the team
  # that marked them or nil (person_message_member.team_id).
  def team_marks(top)
    top.members.to_h { |member| [member.person_id, member.team_id] }
  end

  def create_group_reply(top, author, body: "On my way.", created_at: Time.current, **attributes)
    PersonMessage.new_group_reply(top, author, body:, created_at:, creator_person: author,
                                               message_type: PersonMessage::MESSAGE_TYPE_CONTACT, **attributes)
                 .tap(&:save!)
  end

  # On the team, and eligible for its roster: a login on record
  # (Person.messageable), which the fixtures leave out.
  def join_team(person, team)
    person.update!(last_seen_at: 1.day.ago)
    PersonTeam.find_or_create_by!(person:, team:)
  end

  # Whom a group message's job (GroupMessageAnnounceJob) notifies, as person
  # ids. The block, a request or a save, notifies nobody itself, which this
  # asserts; the job it enqueued is performed after it.
  def capture_group_notifies(&)
    clear_enqueued_jobs
    assert_empty capture_message_notifies(&), "a group message's job notifies its members, not the request"
    capture_message_notifies { perform_enqueued_jobs(only: GroupMessageAnnounceJob) }
  end

  # Every Rbs.message_notify the block makes, as the person ids notified.
  def capture_message_notifies(&)
    capture_message_notify_calls(&).map(&:first)
  end

  # Every Rbs.message_notify the block makes, as [person id, subject, message].
  def capture_message_notify_calls(&)
    capture_message_notify_details(&).map { |call| call.values_at(:person_id, :subject, :message) }
  end

  # Every Rbs.message_notify the block makes, each call's arguments by name.
  def capture_message_notify_details
    calls = []
    original = Rbs.method(:message_notify)
    Rbs.define_singleton_method(:message_notify) do |person, sender_id, from, subject, message, group: false, anonymous: false|
      calls << { person_id: person.id, sender_id:, from:, subject:, message:, group:, anonymous: }
    end
    yield
    calls
  ensure
    Rbs.define_singleton_method(:message_notify, original)
  end
end
