# frozen_string_literal: true

module Admin::JobsHelper
  # How each state reads on the page: its label, badge and tile colours, its
  # icon, and the sentence "How This Page Works" gives it. Keyed as
  # BackgroundJobs::STATES.
  JOB_STATES = {
    "failed" => { label: "Failed", badge: :error, stat: :error, icon: "triangle-exclamation",
                  about: "Raised an error on its last attempt and will not run again until it is retried." },
    "ready" => { label: "Queued", badge: :secondary, stat: :secondary, icon: "inbox",
                 about: "Waiting for a worker to pick it up." },
    "claimed" => { label: "In Progress", badge: :warning, stat: :secondary, icon: "hourglass-half",
                   about: "A worker has claimed it and is running it now." },
    "scheduled" => { label: "Scheduled", badge: :secondary, stat: :secondary, icon: "clock",
                     about: "Enqueued with a delay; the dispatcher moves it to its queue when it is due." },
    "blocked" => { label: "Blocked", badge: :secondary, stat: :secondary, icon: "lock",
                   about: "Waiting for another job with the same concurrency key to finish." },
    "finished" => { label: "Finished", badge: :success, stat: :success, icon: "circle-check",
                    about: "Ran to completion. Kept for %{retention}, then cleared by the hourly cleanup task." }
  }.freeze

  JOB_FILTER_CHIP_LABELS = { status: "Status", queue_name: "Queue", class_name: "Job Class" }.freeze

  def job_state(status)
    JOB_STATES.fetch(status.to_s)
  end

  # The finished sentence reads the retention from the gem's setting, as the
  # stale-worker sentence reads its threshold.
  def job_state_about(state)
    job_state(state)[:about] % { retention: distance_of_time_in_words(SolidQueue.clear_finished_jobs_after) }
  end

  def job_label(job)
    "#{job.id} (#{job.class_name})"
  end

  # One chip per active filter; each URL drops that one filter and keeps the rest.
  def job_filter_chips(form)
    display = ->(key, value) { key == :status ? job_state(value)[:label] : value }
    filter_chips(form.active_filters, JOB_FILTER_CHIP_LABELS, value_label: display) do |remaining, _key|
      admin_jobs_path(JobFilterForm::PARAM_SCOPE => remaining)
    end
  end

  def job_status_options(counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      counts.map { |state, count| ["#{job_state(state)[:label]} (#{count})", state] }
  end

  def job_queue_options(names)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION, *names]
  end

  # One tile per state, a link that filters the list by it; grey at zero.
  def job_stat_tile(state, count, active:)
    meta = job_state(state)
    ui_stat_link admin_jobs_path(JobFilterForm::PARAM_SCOPE => { status: state }), active:,
                 aria_label: "#{count} #{meta[:label].downcase} — show them" do
      ui_stat_box count.to_s, meta[:label], variant: (count.positive? ? meta[:stat] : :secondary),
                  icon: meta[:icon], icon_type: :solid
    end
  end

  # The two bulk buttons, for the filter bar's actions; nothing while no job is failed.
  def job_bulk_actions(failed_count)
    return if failed_count.zero?

    jobs = pluralize(failed_count, "failed job")
    [
      button_link("Retry All Failed", :primary, retry_all_admin_jobs_path,
                  icon: "rotate-right", icon_type: :solid,
                  data: confirm_modal(title: "Retry All Failed Jobs", method: :post,
                                      message: "Put all #{jobs} back on the queue? Each one runs again from the start.")),
      delete_button(destroy_failed_admin_jobs_path, "Delete All Failed",
                    confirm_modal: { title: "Delete All Failed Jobs",
                                     message: "Delete all #{jobs} and their error records? This cannot be undone." })
    ]
  end

  # A row with no execution and no finished stamp is nothing Solid Queue
  # makes, but a row somebody deleted around by hand must not take the page
  # down with it.
  def job_status_badge(job)
    state = JOB_STATES[job.status.to_s]
    return ui_badge("Unknown", :secondary, icon: "circle-question", icon_type: :solid) unless state

    ui_badge state[:label], state[:badge], icon: state[:icon], icon_type: :solid
  end

  # What last happened to the job and when, read by the Last Event column and
  # the detail row: { label:, at:, note: }.
  def job_event(job)
    case job.status
    when :failed
      attempts = job_attempts(job)
      { label: "Failed", at: job.failed_execution.created_at, note: ("attempt #{attempts}" if attempts > 1) }
    when :claimed
      { label: "Running since", at: job.claimed_execution.created_at,
        note: "on #{job.claimed_execution.process&.name || 'a pruned process'}" }
    when :scheduled then { label: "Due", at: job.scheduled_at }
    when :blocked then { label: "Blocked until", at: job.blocked_execution.expires_at }
    when :finished then { label: "Finished", at: job.finished_at }
    else { label: "Waiting since", at: job.ready_execution&.created_at || job.created_at }
    end
  end

  # The event's time and note as markup: datetime_format answers a <span>.
  def job_event_value(event, year: false)
    safe_join([datetime_format(event[:at], year:), event[:note]].compact, " ")
  end

  def job_last_event(event)
    safe_join([event[:label], job_event_value(event)], " ")
  end

  # Active Job counts attempts in the payload it stores with the job.
  def job_attempts(job)
    job.arguments.to_h["executions"].to_i
  end

  # The class name with a zero-width space after each "::", so a folded card
  # on a phone wraps "ActionMailer::" / "MailDeliveryJob" rather than mid-word.
  # A zero-width space, not <wbr>: Chrome breaks at <wbr> even under
  # white-space: nowrap, which the desktop table relies on (measured 2026-10-19).
  def job_class_label(job)
    job.class_name.gsub("::", "::​")
  end

  def job_row_actions(job)
    return tag.span("Running", class: log_text_class) if job.claimed?

    retry_button = if job.failed?
                     button_link("Retry", :secondary, retry_admin_job_path(job), method: :post,
                                 icon: "rotate-right", icon_type: :solid,
                                 aria: { label: "Retry job #{job_label(job)}" })
                   end
    delete = delete_button(admin_job_path(job), "Delete",
                           aria: { label: "Delete job #{job_label(job)}" },
                           confirm_modal: { title: "Delete Job",
                                            message: "Delete job #{job_label(job)}? This cannot be undone." })
    # An inline box rather than button_row, which stacks its buttons on a
    # phone: the folded card wants the pair side by side.
    tag.div(safe_join([retry_button, delete]), class: "inline-flex-center-gap-2")
  end

  def job_error_summary(failed)
    failed.message.to_s.lines.first.to_s.strip
  end

  def job_error_text(failed)
    [failed.message, *failed.backtrace].compact.join("\n")
  end

  # The payload as stored, less whatever the app hides from its logs: a mail
  # job's arguments carry the address it was sent to.
  def job_arguments_json(job)
    JSON.pretty_generate(request.parameter_filter.filter(job.arguments.to_h))
  end

  def worker_stale?(process)
    process.last_heartbeat_at < SolidQueue.process_alive_threshold.ago
  end

  def workers_badge_color(workers)
    workers.empty? || workers.any? { |worker| worker_stale?(worker) } ? :warning : :success
  end

  def worker_heartbeat_badge(process)
    ago = "#{time_ago_in_words(process.last_heartbeat_at, include_seconds: true)} ago"
    if worker_stale?(process)
      ui_badge ago, :warning, icon: "triangle-exclamation", icon_type: :solid
    else
      ui_badge ago, :success, icon: "circle-check", icon_type: :solid
    end
  end

  # What the process registered about itself, in a line: a worker's queues
  # and threads, a dispatcher's batch, a scheduler's task count, a
  # supervisor's children.
  def worker_configuration(process)
    meta = process.metadata.to_h
    parts = []
    parts << "queues: #{meta['queues']}" if meta["queues"].present?
    parts << pluralize(meta["pool_size"], "thread") if meta["pool_size"]
    parts << "polls every #{meta['polling_interval']}s" if meta["polling_interval"]
    parts << "batches of #{meta['batch_size']}" if meta["batch_size"]
    parts << pluralize(Array(meta["recurring_schedule"]).size, "recurring task") if meta.key?("recurring_schedule")
    parts << pluralize(process.supervisees.size, "supervised process") if process.supervisees.any?
    value_or_dash(parts.join(" · "))
  end
end
