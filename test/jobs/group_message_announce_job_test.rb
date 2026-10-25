# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"
require "active_job/continuation/test_helper"

# A group message texts and emails its members from a job, one per message,
# safe to run again. Rbs.message_notify is stubbed in every test
# (GroupMessageTestHelper), so nothing here texts or emails anyone.
class GroupMessageAnnounceJobTest < ActiveSupport::TestCase
  include GroupMessageTestHelper
  include ActiveJob::Continuation::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @author, *@others = %i[active_ranger ranger_with_custom_gender plate_collision_ranger retired_ranger]
                        .map { |name| person(name) }
  end

  # Owner's ruling 2026-10-18, "Pages live, texts queued".
  test "a group message updates its members' pages as it is saved and leaves their texts to its job" do
    top = nil
    assert_empty(capture_message_notifies { top = create_group_thread(@author, *@others) })
    assert_enqueued_with job: GroupMessageAnnounceJob, args: [top.id, top.members.maximum(:id)]
    @others.each { |member| assert_turbo_stream_broadcasts member, count: 2 } # the envelope and the live-region line

    notified = nil
    assert_empty(capture_turbo_stream_broadcasts(@others.first) { notified = capture_message_notifies { perform_enqueued_jobs } })
    assert_equal @others.map(&:id).sort, notified.sort
  end

  test "a reply as the team is announced as a group message from the team, never its author" do
    cadre = teams(:green_dot_cadre)
    top = create_team_thread(@author, cadre, *@others)
    perform_enqueued_jobs
    create_group_reply(top, @author, as_team: cadre)

    details = capture_message_notify_details { perform_enqueued_jobs }
    assert_equal @others.map(&:id).sort, details.map { |call| call[:person_id] }.sort
    assert_equal [["Green Dot Cadre", true, true]], details.map { |call| call.values_at(:from, :group, :anonymous) }.uniq

    create_group_reply(top, @author, body: "As myself.")
    details = capture_message_notify_details { perform_enqueued_jobs }
    assert_equal [[@author.callsign, true, false]], details.map { |call| call.values_at(:from, :group, :anonymous) }.uniq
  end

  # Review finding: the job read the members when it ran, so a newcomer a later
  # reply brought in was told of the earlier one too.
  test "a reply's job tells only who was a member when the reply was written" do
    cadre = teams(:green_dot_cadre)
    newcomer = person(:echelon_ranger)
    top = create_team_thread(@author, cadre, *@others)
    perform_enqueued_jobs
    create_group_reply(top, @author, body: "R1")
    first_job = enqueued_jobs.find { |job| job[:job] == GroupMessageAnnounceJob }

    join_team(newcomer, cadre)
    create_group_reply(top, @others.first, body: "R2")
    notified = capture_message_notify_details { GroupMessageAnnounceJob.perform_now(*first_job[:args]) }

    assert_equal @others.map(&:id).sort, notified.map { |call| call[:person_id] }.sort
    assert_includes top.reload.members.map(&:person_id), newcomer.id
  end

  test "a job enqueued by the release before the member watermark tells every member" do
    top = create_group_thread(@author, *@others)
    clear_enqueued_jobs
    notified = capture_message_notifies { GroupMessageAnnounceJob.perform_now(top.id) }
    assert_equal @others.map(&:id).sort, notified.sort
  end

  test "a worker stopping mid-loop resumes from the next member, telling nobody twice" do
    first = @others.min_by(&:id)
    create_group_thread(@author, *@others)

    before_stop = capture_message_notifies do
      interrupt_job_during_step(GroupMessageAnnounceJob, :members, cursor: first.id.succ) { perform_enqueued_jobs }
    end
    assert_equal [first.id], before_stop
    assert_enqueued_jobs 1, only: GroupMessageAnnounceJob # resumed from the next member

    assert_equal (@others - [first]).map(&:id).sort, capture_message_notifies { perform_enqueued_jobs }.sort
  end

  test "one member's failure is logged and stops neither the rest nor the job" do
    failing = @others.min_by(&:id)
    create_group_thread(@author, *@others)
    notified = []
    original = Rbs.method(:message_notify)
    Rbs.define_singleton_method(:message_notify) do |person, *|
      raise "SMS gateway down" if person == failing

      notified << person.id
    end

    assert_difference -> { ErrorLog.where(error_type: "message-announce-exception").count } => 1 do
      perform_enqueued_jobs
    end
    assert_equal (@others - [failing]).map(&:id).sort, notified.sort
    assert_no_enqueued_jobs
  ensure
    Rbs.define_singleton_method(:message_notify, original)
  end
end
