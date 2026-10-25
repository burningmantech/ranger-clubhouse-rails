# frozen_string_literal: true

# Texts and emails a group thread's members about a message in it, the thread
# top or a reply, away from the request that saved it
# (PersonMessage#announce_to_recipient enqueues one per message): every member
# but the author and anyone whose status now bars messages (owner's ruling
# 2026-10-19) gets Rbs.message_notify, which their alert preferences turn into
# a text, an email or nothing, as a group message from the name the row was
# written under: a message sent as a team names the team, never its author
# (ruling R5 of .scratch/team-messaging/PRD.md), and its email's mail log row
# names no sender. Their pages were told in the request; the workers poll every
# 30 seconds, which a text can wait for.
#
# Only members whose rows were written by the time the message was
# (+through_member_id+, the newest member row id then): a later reply in a
# team thread can bring in someone who joined the team since, and they are
# told of that reply, not this one. A job enqueued by the release before this
# argument (one argument) tells every member, as it did. One enqueued with it
# fails on a worker of that release (ArgumentError) while a rolling deploy
# overlaps them, rather than naming an anonymous author: retry it from Admin ›
# Background Jobs once the rollout is done.
#
# Safe to retry without telling anyone twice: a continuation. Members go in
# person id order, and the cursor moves past each as they are done, so a
# worker that stops mid-loop (a deploy) re-enqueues the job from the next
# member, as does an error once the first is done. Each member's notify is
# rescued and logged (PersonMessage#announcing), so one member's failure never
# stops the rest. A worker killed outright leaves its job failed (Solid
# Queue's pruning), never run again.
class GroupMessageAnnounceJob < ApplicationJob
  include ActiveJob::Continuable

  def perform(message_id, through_member_id = nil)
    message = PersonMessage.includes(:sender_person, :sender_team, members: :person, reply_to: { members: :person }).find(message_id)
    from = message.sender_name

    step :members, start: 0 do |step|
      message.other_members(message.sender_person_id, through: through_member_id).sort_by(&:id).each do |member|
        next if member.id < step.cursor || member.messages_barred?

        message.announcing(member) do
          Rbs.message_notify(member, message.sender_person_id, from, message.subject, message.body_text,
                             group: true, anonymous: message.from_team?)
        end
        step.advance!(from: member.id)
      end
    end
  end
end
