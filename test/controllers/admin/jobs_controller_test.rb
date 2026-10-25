# frozen_string_literal: true

require "test_helper"

class Admin::JobsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @tech_ninja = person(:echelon_ranger)
    @admin = person(:auditor_ranger)
    @outsider = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)
    # Tech Ninja and nothing else: this page is one the Admin role does not
    # open, so the tests have to prove the role on its own works.
    grant_role(@tech_ninja, Role::TECH_NINJA)

    # No fixtures hold queue rows; this only clears what a crashed run left.
    [SolidQueue::FailedExecution, SolidQueue::ReadyExecution, SolidQueue::ClaimedExecution,
     SolidQueue::ScheduledExecution, SolidQueue::BlockedExecution, SolidQueue::Process, SolidQueue::Job].each(&:delete_all)
    ActionLog.delete_all
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- gate

  test "denies access without the tech ninja role" do
    sign_in_as(@outsider)

    get admin_jobs_path

    assert_redirected_to me_root_path
  end

  test "an admin without the tech ninja role is turned away" do
    sign_in_as(@admin)

    get admin_jobs_path

    assert_redirected_to me_root_path
    assert_equal "Tech Ninja role required to manage background jobs.", flash[:error]
  end

  # ---------------------------------------------------------------- index

  test "shows a row per job with its state, the counts, and the workers" do
    ready = enqueue("GroupMessageAnnounceJob", args: [1])
    scheduled = enqueue("DailyReportJob", scheduled_at: 1.hour.from_now)
    failed = fail_job(enqueue("ActionMailer::MailDeliveryJob"), "Missing template")
    claimed = claim_job(enqueue("PhotoPendingJob"))
    finished = finish_job(enqueue("CleanupMailLogJob"))

    sign_in_as(@tech_ninja)

    get admin_jobs_path

    assert_response :success
    assert_select "tr.table-detail-row", count: 5
    assert_select "#job-detail-#{failed.id}", text: /StandardError.*Missing template/m
    assert_select "#job-detail-#{failed.id}", text: /app\/jobs\/action_mailer\/mail_delivery_job\.rb/
    assert_select "#job-detail-#{failed.id}", text: /#{failed.active_job_id}/
    assert_select "#job-detail-#{claimed.id}", text: /Running since.*worker-test/m
    assert_select "#job-detail-#{scheduled.id}", text: /Due/
    assert_select "#job-detail-#{finished.id}", text: /Finished/
    assert_select "#job-detail-#{ready.id}", text: /Waiting since/
    # One Retry, on the failed row; Delete on every row but the running one.
    assert_select "a[href=?]", retry_admin_job_path(failed), count: 1
    assert_select "a[href=?]", admin_job_path(claimed), count: 0
    assert_select "a[href=?]", admin_job_path(failed), count: 1
    assert_select "a[href=?]", retry_all_admin_jobs_path, count: 1
    # The tiles carry the counts.
    assert_select "a[href=?]", admin_jobs_path(filter: { status: "failed" }), text: /1\s*Failed/
    assert_select "a[href=?]", admin_jobs_path(filter: { status: "ready" }), text: /1\s*Queued/
    # The worker table.
    assert_select "td", text: /worker-test/
    assert_select "td", text: /queues: \*.*3 threads/
    assert_unique_dom_ids
  end

  test "the page's queries do not grow with the jobs it lists" do
    seed_one_of_each
    sign_in_as(@tech_ninja)
    get admin_jobs_path

    queries = count_queries { get admin_jobs_path }
    2.times { seed_one_of_each }

    assert_equal queries, count_queries { get admin_jobs_path }
  end

  test "the arguments are shown with the app's filtered parameters hidden" do
    job = enqueue("ActionMailer::MailDeliveryJob",
                  args: ["SomeMailer", "notify", "deliver_now", { "password" => "hunter2", "to" => "someone" }])

    sign_in_as(@tech_ninja)

    get admin_jobs_path

    assert_response :success
    assert_select "#job-detail-#{job.id}", text: /"to": "someone"/
    assert_select "#job-detail-#{job.id}", text: /hunter2/, count: 0
  end

  test "filters by state, queue and class" do
    failed = fail_job(enqueue("ActionMailer::MailDeliveryJob"))
    ready = enqueue("GroupMessageAnnounceJob", queue: "announcements", args: [1])

    sign_in_as(@tech_ninja)

    get admin_jobs_path(filter: { status: "failed" })
    assert_response :success
    assert_select "#job-detail-#{failed.id}"
    assert_select "#job-detail-#{ready.id}", count: 0
    assert_select "a", text: /Status: Failed/
    assert_select "a[href=?]", destroy_failed_admin_jobs_path, count: 1

    get admin_jobs_path(filter: { queue_name: "announcements" })
    assert_select "#job-detail-#{ready.id}"
    assert_select "#job-detail-#{failed.id}", count: 0

    get admin_jobs_path(filter: { class_name: "mailDELIVERY" })
    assert_select "#job-detail-#{failed.id}"
    assert_select "#job-detail-#{ready.id}", count: 0

    get admin_jobs_path(filter: { status: "bogus" })
    assert_select "tr.table-detail-row", count: 2
    assert_select "a", text: /Status:/, count: 0
  end

  test "an empty queue and a filter that matches nothing read differently" do
    sign_in_as(@tech_ninja)

    get admin_jobs_path
    assert_response :success
    assert_select "h1", text: /Background Jobs/
    assert_select ".empty-state", text: /No jobs are queued/
    assert_select "a[href=?]", retry_all_admin_jobs_path, count: 0

    enqueue("DailyReportJob")
    get admin_jobs_path(filter: { class_name: "Nothing" })
    assert_select ".empty-state", text: /No jobs match the current filters/
  end

  test "pages the list fifty at a time and holds a stale page to the last one" do
    51.times { enqueue("DailyReportJob") }

    sign_in_as(@tech_ninja)

    get admin_jobs_path(filter: { page: 2 })
    assert_response :success
    assert_select "tr.table-detail-row", count: 1
    assert_select "p", text: /Page 2 of 2 · 51 jobs/

    get admin_jobs_path(filter: { page: 9 })
    assert_select "tr.table-detail-row", count: 1
    assert_select "p", text: /Page 2 of 2 · 51 jobs/
  end

  # ---------------------------------------------------------------- retry

  test "retry puts a failed job back on its queue with its attempts reset" do
    job = fail_job(enqueue("ActionMailer::MailDeliveryJob"))

    sign_in_as(@tech_ninja)

    post retry_admin_job_path(job)

    assert_redirected_to admin_jobs_path
    assert_equal "Job #{job.id} (ActionMailer::MailDeliveryJob) is back on the default queue.", flash[:success]
    job.reload
    assert job.ready?
    assert_nil job.failed_execution
    assert_equal 0, job.arguments["executions"]
    log = ActionLog.find_by!(event: "background-job-retry")
    assert_equal @tech_ninja.id, log.person_id
    assert_equal job.id, log.data["job_id"]
  end

  test "retry refuses a job that is not failed" do
    job = enqueue("DailyReportJob")

    sign_in_as(@tech_ninja)

    post retry_admin_job_path(job)

    assert_redirected_to admin_jobs_path
    assert_equal "Job #{job.id} is not failed, so there is nothing to retry.", flash[:error]
    assert job.reload.ready?
    assert_equal 0, ActionLog.count
  end

  test "retry all puts every failed job back, attempts reset, and leaves the rest alone" do
    first = fail_job(enqueue("ActionMailer::MailDeliveryJob"))
    second = fail_job(enqueue("GroupMessageAnnounceJob", args: [1]))
    scheduled = enqueue("DailyReportJob", scheduled_at: 1.hour.from_now)

    sign_in_as(@tech_ninja)

    post retry_all_admin_jobs_path

    assert_redirected_to admin_jobs_path
    assert_equal "2 failed jobs put back on the queue.", flash[:success]
    assert first.reload.ready?
    assert second.reload.ready?
    assert_equal 0, first.arguments["executions"]
    assert scheduled.reload.scheduled?
    assert_equal 0, SolidQueue::FailedExecution.count
    assert_equal 2, ActionLog.find_by!(event: "background-job-retry-all").data["count"]
  end

  test "retry all with nothing failed changes nothing" do
    enqueue("DailyReportJob")

    sign_in_as(@tech_ninja)

    post retry_all_admin_jobs_path

    assert_redirected_to admin_jobs_path
    assert_equal "0 failed jobs put back on the queue.", flash[:success]
  end

  # ---------------------------------------------------------------- delete

  test "delete removes a failed job and its failure record" do
    job = fail_job(enqueue("ActionMailer::MailDeliveryJob"))

    sign_in_as(@tech_ninja)

    delete admin_job_path(job)

    assert_redirected_to admin_jobs_path
    assert_equal "Job #{job.id} (ActionMailer::MailDeliveryJob) deleted.", flash[:success]
    assert_not SolidQueue::Job.exists?(job.id)
    assert_equal 0, SolidQueue::FailedExecution.count
    assert_equal job.id, ActionLog.find_by!(event: "background-job-delete").data["job_id"]
  end

  test "delete removes a finished job" do
    job = finish_job(enqueue("CleanupMailLogJob"))

    sign_in_as(@tech_ninja)

    delete admin_job_path(job)

    assert_redirected_to admin_jobs_path
    assert_not SolidQueue::Job.exists?(job.id)
  end

  test "delete refuses a running job" do
    job = claim_job(enqueue("PhotoPendingJob"))

    sign_in_as(@tech_ninja)

    delete admin_job_path(job)

    assert_redirected_to admin_jobs_path
    assert_equal "Job #{job.id} is running and cannot be deleted. Wait for it to finish or fail.", flash[:error]
    assert job.reload.claimed?
    assert_equal 0, ActionLog.count
  end

  test "delete all failed removes the failed jobs and nothing else" do
    failed = fail_job(enqueue("ActionMailer::MailDeliveryJob"))
    ready = enqueue("DailyReportJob")

    sign_in_as(@tech_ninja)

    delete destroy_failed_admin_jobs_path

    assert_redirected_to admin_jobs_path
    assert_equal "1 failed job deleted.", flash[:success]
    assert_not SolidQueue::Job.exists?(failed.id)
    assert ready.reload.ready?
    assert_equal 1, ActionLog.find_by!(event: "background-job-delete-failed").data["count"]
  end

  test "an unknown job is not found" do
    sign_in_as(@tech_ninja)

    delete admin_job_path(999_999)

    assert_response :not_found
  end

  private

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name] == "SCHEMA"
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # A job as Active Job enqueues it, through the gem: the real payload in
  # arguments, and the ready (or scheduled) execution Solid Queue makes.
  def enqueue(class_name, queue: "default", scheduled_at: Time.current, args: [])
    active_job = class_name.constantize.new(*args)
    active_job.queue_name = queue
    SolidQueue::Job.enqueue(active_job, scheduled_at:)
  end

  # Solid Queue makes a ReadyExecution for every due job on create, and
  # Job#status reads it before the failure, so it has to go first.
  def fail_job(job, message = "boom")
    job.ready_execution&.destroy!
    job.arguments["executions"] = 1
    job.save!
    error = StandardError.new(message)
    error.set_backtrace(["app/jobs/#{job.class_name.underscore}.rb:7:in 'perform'"])
    job.failed_with(error)
    job.reload
  end

  def claim_job(job)
    job.ready_execution&.destroy!
    process = SolidQueue::Process.find_by(name: "worker-test") ||
              SolidQueue::Process.register(kind: "Worker", name: "worker-test", pid: 42, hostname: "test-host",
                                           metadata: { queues: "*", pool_size: 3, polling_interval: 30 })
    SolidQueue::ClaimedExecution.create!(job:, process:)
    job.reload
  end

  def finish_job(job)
    job.ready_execution&.destroy!
    job.finished!
    job.reload
  end

  def seed_one_of_each
    enqueue("GroupMessageAnnounceJob", args: [1])
    enqueue("DailyReportJob", scheduled_at: 1.hour.from_now)
    fail_job(enqueue("ActionMailer::MailDeliveryJob"))
    claim_job(enqueue("PhotoPendingJob"))
    finish_job(enqueue("CleanupMailLogJob"))
  end
end
