# frozen_string_literal: true

# One person in a message thread, the sender included: who the thread is
# between, and their own read and archive state. person_message_id is the
# thread top. Every thread has them (the member model,
# .scratch/messaging-rework/member-model-plan.md): a one-to-one thread its
# recipient and sender, a broadcast, walk-up or import its recipient, a group
# thread everyone in it.
#
# A thread is unread for a member who never read it (no last read) or when a
# row someone else wrote is newer than the newest one they read:
# last_read_message_id (ruling D2). Ids run in date order and never tie, so a
# row written in the same second, or on the training server's frozen clock,
# still reads unread.
class PersonMessageMember < ApplicationRecord
  self.table_name = "person_message_member"

  belongs_to :person_message
  belongs_to :person

  # The members a thread names, as its row in the list does
  # (PersonMessage#group_party_names): not one a team brought in (team_id,
  # PersonMessage#sync_team_members!), whom the thread shows as the team.
  scope :named, -> { where(team_id: nil) }

  # Read through every row given (the thread as it was shown): the newest
  # row's id, so a row written after the thread was shown stays New. Never
  # back: a page drawn before a live reply was marked read
  # (thread_live_controller) still shows the older newest row.
  def mark_read!(rows)
    update!(last_read_message_id: [last_read_message_id, *rows.map(&:id)].compact.max)
  end

  # Unread from +row+ on (the newest row someone else wrote), or never read
  # when there is none.
  def mark_unread_from!(row)
    update!(last_read_message_id: row && (row.id - 1))
  end
end
