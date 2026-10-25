# frozen_string_literal: true

# HQ Window shift page — /hq/:person_id/shift-manage.
#
# Ported from the Ember hq/shift route tree (port/routes/hq/shift.js,
# port/controllers/hq/shift.js, port/templates/hq/shift.hbs) and its staged
# child components: hq-timesheet-verification.{js,hbs} (verify / correction /
# skip review), hq-pogs.{js,hbs} + hq-pog-guidelines.hbs (meal & shower pogs),
# and hq-asset-table.{js,hbs} (radios & gear).
#
# Shift check in/out comes from ShiftManageConcern and the barcode
# checkout/check-in/attachment flow from AssetManagementConcern — both reused
# untouched. This controller adds the HQ-only pieces: timesheet verification,
# correction + missing-request modals, pog issuance, and mark off site.
#
# The Ember page was a long-lived SPA screen; the Rails port re-derives the
# suggested-task (todo) seed server-side on every full render. The
# "just started/ended a shift" visit state upstream kept in the controller is
# carried across the concern's redirects with ctx_* query params, which the
# index action re-validates against the database before trusting.
class Hq::ShiftManageController < ApplicationController
  include HqConcern
  include ShiftManageConcern
  include AssetManagementConcern

  # One suggested-task checklist chip (upstream HqTodoTask instance).
  Todo = Struct.new(:task, :label, :completed, :ignore, :blink, keyword_init: true)

  def index
    load_shift_manage_state
    # ShiftManageConcern only loads upcoming slots while off duty; the todo
    # seed (ask-if-done + radio nag) needs them in either duty state.
    @upcoming_slots ||= Scheduling::Query.retrieve_starting_slots_for_person(@person.id)
    load_timesheets
    load_assets
    load_pogs
    resolve_shift_context
    build_desired_position_options(@open_correction_entry) if @open_correction_entry
    build_todos
    build_section_states
  end

  # --- Timesheet verification (hq-timesheet-verification) ------------------

  def verify_timesheet
    entry = locate_review_entry
    return unless entry

    # Model audit callbacks stamp verified_at/verified_person and write the
    # TimesheetLog VERIFY row — no audit code here.
    entry.review_status = Timesheet::STATUS_VERIFIED
    entry.save(validate: false)
    render_verification_update("Marked the timesheet entry as verified.")
  end

  def unverify_timesheet
    entry = locate_review_entry
    return unless entry

    entry.review_status = Timesheet::STATUS_UNVERIFIED
    entry.save(validate: false)
    render_verification_update("Un-verified the timesheet entry.")
  end

  def correction_form
    entry = locate_review_entry
    return unless entry

    build_desired_position_options(entry)
    render_hq_modal("correction_modal",
                    { entry:, desired_position_options: @desired_position_options })
  end

  def submit_correction
    entry = locate_review_entry
    return unless entry

    entry.review_status = Timesheet::STATUS_PENDING
    entry.assign_attributes(correction_params)

    if entry.save
      TimesheetManagement.unconfirm_timesheet(entry, "correction submitted")
      # additional_notes is a pseudo field consumed by the save's note
      # recording; it is not cleared by the save itself.
      entry.additional_notes = nil
      redirect_to shift_return_path, success: "Correction request submitted."
    else
      build_desired_position_options(entry)
      render_hq_modal("correction_modal",
                      { entry:, desired_position_options: @desired_position_options },
                      status: :unprocessable_entity)
    end
  end

  # --- Missing timesheet request -------------------------------------------

  def new_missing_request
    build_missing_position_options
    entry = TimesheetMissing.new(position_id: @missing_position_options.first&.last)
    render_hq_modal("missing_request_modal",
                    { entry:, position_options: @missing_position_options })
  end

  def create_missing_request
    entry = TimesheetMissing.new(missing_request_params)
    entry.person_id = @person.id
    entry.create_person_id = current_user.id
    entry.review_status = TimesheetMissing::STATUS_PENDING

    if entry.save
      redirect_to shift_return_path,
                  success: "Missing timesheet request submitted."
    else
      build_missing_position_options
      render_hq_modal("missing_request_modal",
                      { entry:, position_options: @missing_position_options },
                      status: :unprocessable_entity)
    end
  end

  # --- Meals & Showers (hq-pogs) -------------------------------------------

  def new_pog
    type = params[:pog].to_s
    unless PersonPog::POGS.include?(type) && pog_type_available?(type)
      return redirect_to shift_return_path,
                         error: "That pog type is not available right now. " \
                                "Reload the page and pick a pog button again."
    end

    render_hq_modal("pog_issue_modal",
                    { pog: PersonPog.new(pog: type),
                      warnings: pog_issue_warnings(type),
                      ended_entry: locate_ended_entry })
  end

  def create_pog
    type = scoped_params(:person_pog, :pog)[:pog].to_s
    unless PersonPog::POGS.include?(type) && pog_type_available?(type)
      return redirect_to shift_return_path,
                         error: "That pog type is not available right now. " \
                                "Reload the page and pick a pog button again."
    end

    pog = PersonPog.new(create_pog_params.merge(person_id: @person.id,
                                                issued_by_id: current_user.id,
                                                status: PersonPog::STATUS_ISSUED))
    if pog.save
      render_pog_update("Issued the pog.",
                        signal: { event: "pog-issued", pog: pog.pog })
    else
      render_hq_modal("pog_issue_modal",
                      { pog:, warnings: pog_issue_warnings(type),
                        ended_entry: locate_ended_entry },
                      status: :unprocessable_entity)
    end
  end

  def edit_pog
    pog = locate_pog
    return unless pog

    render_hq_modal("pog_edit_modal", { pog: })
  end

  def cancel_pog_form
    pog = locate_pog
    return unless pog

    render_hq_modal("pog_cancel_modal", { pog: })
  end

  # Handles the three mutations on an existing pog, selected by pog_op:
  # "note" (update the note), "redeem" (half-meal -> full meal), and
  # "cancel" (mark accidentally issued; reason required).
  def update_pog
    pog = locate_pog
    return unless pog

    case params[:pog_op]
    when "redeem"
      redeem_pog(pog)
    when "cancel"
      cancel_pog(pog)
    else
      update_pog_note(pog)
    end
  end

  # --- Mark off site --------------------------------------------------------

  # Explicit set (not a toggle) so a double submit can never flip the person
  # back on site. Same validate-free save as PersonController#toggle_onsite.
  def mark_off_site
    @person.on_site = false
    @person.save(validate: false)
    redirect_to hq_shift_manage_path(@person),
                success: "#{@person.callsign} is now marked off site."
  end

  private

  # --- ShiftManageConcern contract -----------------------------------------

  def shift_person = @person

  def shift_self_serve? = false

  # Only this page can honour it: shift_return_path below encodes ctx_correction
  # and resolve_shift_context re-opens the correction modal for the ended entry.
  def allow_correction_on_end? = true

  # Start/end redirects carry the "a shift was just handled" visit state the
  # Ember controller kept in memory (noShiftHandled/endedShiftEntry); index
  # re-validates the params against the current duty state before use.
  #
  # Keys off @shift_transition, which the concern sets only after the write
  # succeeds — not off action_name, which would also fire for a refused
  # check-in and (when the person was already on duty) show the shift as
  # freshly started behind the error.
  def shift_return_path
    case @shift_transition
    when :started
      hq_shift_manage_path(@person, ctx_shift: "started")
    when :ended
      hq_shift_manage_path(@person, { ctx_shift: "ended", ctx_entry: params[:entry_id],
                                      ctx_correction: params[:submit_correction].presence }.compact)
    else
      hq_shift_manage_path(@person, **shift_context)
    end
  end

  def shift_start_path(**query) = hq_shift_manage_shift_start_path(@person, **query)

  def shift_end_path(**query) = hq_shift_manage_shift_end_path(@person, **query)

  def shift_resignin_path(**query) = hq_shift_manage_shift_resignin_path(@person, **query)

  def shift_correct_position_path(**query) = hq_shift_manage_shift_position_path(@person, **query)

  def shift_delete_mistake_path(**query) = hq_shift_manage_shift_entry_path(@person, **query)

  # --- AssetManagementConcern contract -------------------------------------

  def assets_person = @person

  def assets_return_path = hq_shift_manage_path(@person, **shift_context)

  # Checkout POSTs to a URL carrying the ctx params so the concern's redirect
  # (assets_return_path above) preserves the visit state.
  def assets_checkout_path = hq_shift_manage_assets_path(@person, **shift_context)

  def assets_check_in_path(person_asset)
    hq_shift_manage_asset_check_in_path(@person, person_asset, **shift_context)
  end

  def assets_change_attachment_path(person_asset)
    hq_shift_manage_asset_change_attachment_path(@person, person_asset, **shift_context)
  end

  def assets_update_attachment_path(person_asset)
    hq_shift_manage_asset_update_attachment_path(@person, person_asset, **shift_context)
  end

  # Radios & Gear sits mid-page and the barcode field is scanned over and
  # over, so an asset action answers in place — the concern's default
  # redirect would throw the operator back to the top of the page and drop
  # the cursor out of the barcode field on every scan. Upstream never
  # reloaded here (port/controllers/hq/shift.js onAssetCheckOut/onAssetCheckIn
  # mutated the page directly); the signal carries the radio checklist
  # transitions those callbacks applied.
  def assets_outcome(flash_type, message, asset: nil)
    load_shift_manage_state
    load_assets
    render turbo_stream: [
      turbo_stream.replace("hq-assets-section", partial: "hq/shift_manage/assets_section",
                                                locals: assets_section_locals),
      turbo_stream.update("modal", ""),
      hq_signal_stream(event: "assets", complete: radio_todos_completed(asset).join(",")),
      # Collecting the last radio clears a Mark Off Site blocker, so that row
      # has to stop listing it.
      *section_summary_streams,
      ui_toast_stream(message, flash_type)
    ]
  end

  # state: :current is not a guess — an asset action can only come from the
  # barcode field inside this section, so the operator is demonstrably standing
  # here. Rendering it open also keeps that field in the DOM for the refocus
  # that every scan depends on; a collapsed re-render would break the scan loop.
  def assets_section_locals
    { person: @person, person_event: @person_event, event_info: @event_info,
      radio_accounting: @radio_accounting, on_duty_entry: @on_duty_entry,
      assets_checked_out: @assets_checked_out, attachments: @attachments,
      checkout_form: @checkout_form, state: :current }
  end

  # Checklist chips this action completed, mirroring upstream exactly:
  # onAssetCheckOut completed "Check Out Radio", and onAssetCheckIn completed
  # both collect tasks once nothing was left to collect. Both callbacks were
  # guarded on `asset.type === TYPE_RADIO` and ran only after the write
  # succeeded, so a pager, an attachment change, or a failed barcode scan must
  # leave the radio nags alone — otherwise "Collect Radio (if done rangering)"
  # self-completes while the person still holds an event radio and HQ never
  # asks for it back.
  def radio_todos_completed(asset)
    return [] unless asset&.type == Asset::TYPE_RADIO

    case action_name
    when "asset_checkout"
      [HqTodo::ISSUE_RADIO]
    when "asset_check_in"
      @radio_accounting.collect_count.zero? ? [HqTodo::COLLECT_RADIO, HqTodo::COLLECT_RADIO_IF_DONE] : []
    else
      []
    end
  end

  # --- Page data ------------------------------------------------------------

  # The started/ended visit context, carried through redirects.
  def shift_context
    { ctx_shift: params[:ctx_shift].presence, ctx_entry: params[:ctx_entry].presence }.compact
  end
  helper_method :shift_context

  def load_timesheets
    @timesheets = Timesheet.find_for_query(person_id: @person.id, year: Current.year,
                                           check_times: true)
    @timesheets_to_review = @timesheets.select { |t| reviewable_entry?(t) }
  end

  def load_assets
    @assets_checked_out = PersonAsset.find_for_query(person_id: @person.id, year: Current.year)
                                     .reject(&:checked_in)
    @attachments = AssetAttachment.find_all
    @checkout_form = AssetCheckoutForm.new
    @radio_accounting = RadioAccounting.accounting(@assets_checked_out,
                                                   @event_info&.radio_max.to_i)
  end

  def load_pogs
    @pogs = PersonPog.find_for_query(person_id: @person.id, year: Current.year).to_a
    @half_pog_enabled = half_pog_enabled?
  end

  def half_pog_enabled? = Setting.get_value(Setting::MEAL_HALF_POG_ENABLED)

  # Validate the ctx params against the database — a stale or hand-edited URL
  # must never claim a shift was handled when it wasn't.
  def resolve_shift_context
    @shift_started = params[:ctx_shift] == "started" && @on_duty_entry.present?
    @ended_entry = locate_ended_entry if params[:ctx_shift] == "ended"
    @open_correction_entry = @ended_entry if @ended_entry && params[:ctx_correction].present?
    @shift_handled = @shift_started || @ended_entry.present?
    @show_no_radios_modal = @ended_entry.present? &&
                            @ended_entry.position_id != Position::BURN_PERIMETER &&
                            @radio_accounting.radio_count.zero?
  end

  def locate_ended_entry
    entry_id = params[:ctx_entry].to_i
    return nil unless entry_id.positive?

    Timesheet.includes(:position).where(person_id: @person.id)
             .where.not(off_duty: nil).find_by(id: entry_id)
  end

  # Entries the review widget can operate on — completed shifts only.
  def reviewable_entry?(entry)
    entry.off_duty.present? && entry.verification_required?
  end

  # --- Todo checklist seed (upstream initializeTodos + notify transitions) --

  def build_todos
    @todos = []
    no_more_scheduled = @upcoming_slots.imminent.empty? && @upcoming_slots.upcoming.empty?

    add_todo(HqTodo::DELIVERY_MESSAGE) if @unread_message_count.to_i.positive?
    add_todo(HqTodo::VERIFY_TIMESHEET) if @timesheets_to_review.any?

    # "No More Upcoming Shifts — Ask If Finished Rangering" chip; ignored after a
    # shift start (upstream askIfDone.ignore = true in startShiftNotify).
    if no_more_scheduled
      @ask_if_done = Todo.new(task: HqTodo::OFF_SITE, label: HqTodo::LABELS[HqTodo::OFF_SITE],
                              completed: false, ignore: @shift_started, blink: true)
    end

    if @shift_started
      add_todo(HqTodo::START_SHIFT, completed: true)
    elsif @ended_entry
      add_todo(HqTodo::END_SHIFT, completed: true)
    else
      add_todo(@on_duty_entry ? HqTodo::END_SHIFT : HqTodo::START_SHIFT)
    end

    build_radio_todo(no_more_scheduled)
    build_meal_pog_todo if @ended_entry
  end

  # Upstream seeds the radio task from the duty state at page entry; the
  # started/ended contexts reproduce the pre-transition state so the nag
  # matches what the HQ operator saw upstream (e.g. "Check Out Radio" right
  # after a shift start).
  def build_radio_todo(no_more_scheduled)
    off_duty = @shift_started || (!@ended_entry && @on_duty_entry.nil?)
    task = RadioAccounting.radio_todo(off_duty:, no_more_scheduled:,
                                      accounting: @radio_accounting)

    if @shift_started && @on_duty_entry.position_id == Position::BURN_PERIMETER
      # Burn Perimeter may not need a radio: swap the checkout nag for an
      # ignored informational chip (upstream startShiftNotify).
      task = nil if task == HqTodo::ISSUE_RADIO
      add_todo(task) if task
      add_todo(HqTodo::NO_RADIO, ignore: true)
    elsif task
      add_todo(task)
    end
  end

  def build_meal_pog_todo
    if current_period_has_meal_pass?
      add_todo(HqTodo::MEAL_POG_NONE, ignore: true)
    else
      add_todo(HqTodo::MEAL_POG)
    end
  end

  def add_todo(task, completed: false, ignore: false)
    @todos << Todo.new(task:, label: HqTodo::LABELS[task], completed:, ignore:, blink: false)
  end

  # --- Guided flow section states ------------------------------------------

  # Exactly one section is open at a time, so the operator faces one decision
  # instead of four screens of stacked panels. The open ("current") section is
  # derived from the same duty state the checklist is seeded from, so the page
  # opens on whatever the checklist is nagging about first. Every other section
  # still reports what is outstanding through its collapsed summary row.
  #
  # Off site is deliberately dead-ended: nothing on this page can proceed until
  # On-Site Registration runs, so no section opens and the gate card is the only
  # thing to act on.
  def build_section_states
    @unreviewed_count = @timesheets_to_review.count(&:verification_required?)
    @off_site_pending = off_site_pending_items

    @section_states = {
      shift: shift_section_state,
      assets: @radio_accounting.collect_count.positive? ? :attention : :idle,
      pogs: pogs_section_state,
      offsite: @person.on_site && @off_site_pending.any? ? :attention : :idle
    }

    open_section = current_section
    @section_states[open_section] = :current if open_section
  end

  def shift_section_state
    return :attention if @unreviewed_count.positive?
    return :complete if @ended_entry

    :idle
  end

  # A just-ended shift with no BMID meal pass means a pog is probably owed, so
  # the row flags it. The controller's afterShiftReview choreography opens this
  # section alongside Radios & Gear, matching upstream.
  def pogs_section_state
    return :attention if @ended_entry && !current_period_has_meal_pass?
    return :complete if @pogs.any?

    :idle
  end

  # After a shift starts the flow moves to the radio handoff; after one ends,
  # the timesheet review comes first and Radios & Gear only takes over once
  # nothing is left to review (matching the controller's afterShiftReview
  # choreography). Everything else — on duty, off duty, mid-review — belongs to
  # the shift section.
  def current_section
    return nil unless @person.on_site

    if @shift_started || (@ended_entry && @unreviewed_count.zero?)
      :assets
    else
      :shift
    end
  end

  # Items an operator should clear before marking someone off site. Shared by
  # the Mark Off Site section's collapsed summary and its warning list so the
  # two can never disagree.
  def off_site_pending_items
    items = []
    items << "#{@person.callsign} is still on duty." if @on_duty_entry
    if @assets_checked_out.any?
      items << "#{helpers.pluralize(@assets_checked_out.size, "asset")} " \
               "(radios, gear, etc.) not collected."
    end
    if @unreviewed_count.positive?
      items << "#{helpers.pluralize(@unreviewed_count, "timesheet entry")} not reviewed."
    end
    items
  end

  def current_period_has_meal_pass?
    period = @event_periods[@event_info&.event_period&.to_sym]
    period.present? && period[:has_pass]
  end
  helper_method :current_period_has_meal_pass?

  # --- Verification plumbing ------------------------------------------------

  def locate_review_entry
    entry = Timesheet.includes(:position, :slot).where(person_id: @person.id)
                     .find_by(id: params[:timesheet_id])

    if entry.nil?
      redirect_to shift_return_path,
                  error: "That timesheet entry no longer exists. Reload the page and try again."
      return nil
    end

    if entry.off_duty.blank?
      redirect_to shift_return_path,
                  error: "You cannot review this shift yet. End the shift first, then review it."
      return nil
    end

    entry
  end

  def correction_params
    params.expect(timesheet: [:desired_position_id, :desired_on_duty, :desired_off_duty, :additional_notes])
  end

  # timesheet_missing.partner is NOT NULL with no database default, so a payload
  # without the field (the form always sends it, but nothing guarantees that)
  # would raise NotNullViolation instead of failing validation.
  def missing_request_params
    params.expect(timesheet_missing: [:position_id, :on_duty, :off_duty, :partner, :additional_notes])
          .with_defaults(partner: "")
  end

  # Entries shown by the verification list: everything still needing review
  # plus the already-reviewed entries the open page was showing (their ids
  # ride along on the action URLs), so a just-verified entry stays visible
  # with its green banner and Un-Verify button (upstream
  # _reconcileTimesheetsToReview).
  def verification_entries
    listed = IdList.parse(params[:listed].to_s.split(","))
    rows = Timesheet.find_for_query(person_id: @person.id, year: Current.year, check_times: true)
    rows.select { |t| reviewable_entry?(t) || (t.off_duty.present? && listed.include?(t.id)) }
  end

  def render_verification_update(message)
    entries = verification_entries
    render turbo_stream: [
      turbo_stream.update("hq-verification",
                          partial: "hq/shift_manage/verification",
                          locals: { entries:, person: @person }),
      hq_signal_stream(event: "verification",
                       unreviewed: entries.count { |t| t.verification_required? }),
      pogs_stream,
      pogs_summary_stream,
      *summary_streams,
      *section_summary_streams,
      ui_toast_stream(message, :success)
    ]
  end

  # --- Pog plumbing ---------------------------------------------------------

  def locate_pog
    pog = PersonPog.where(person_id: @person.id).find_by(id: params[:pog_id])

    if pog.nil?
      redirect_to shift_return_path,
                  error: "That pog record no longer exists. Reload the page and try again."
      return nil
    end

    if pog.status == PersonPog::STATUS_CANCELLED
      redirect_to shift_return_path, error: "This pog is already cancelled, so you cannot change it."
      return nil
    end

    pog
  end

  # Reads the setting directly rather than @half_pog_enabled: the pog actions
  # do not run load_pogs, so the ivar is nil there.
  def pog_type_available?(type)
    type != PersonPog::POG_HALF_MEAL || half_pog_enabled?
  end

  # Issue-modal warnings (upstream setupToIssue), computed from the shell's
  # event info; the warnings match port/components/hq-pogs.js in substance, with
  # the instruction sentences rewritten into this project's active-voice copy.
  def pog_issue_warnings(type)
    warnings = []
    callsign = @person.callsign

    case type
    when PersonPog::POG_MEAL, PersonPog::POG_HALF_MEAL
      if current_period_has_meal_pass?
        warnings << "#{callsign} has a BMID Meal Pass for the current event period. " \
                    "Do not issue a meal pog."
      end
    when PersonPog::POG_SHOWER
      if @event_info&.showers
        warnings << "#{callsign} already has a BMID with Wet Spot access. " \
                    "Do not issue a shower pog."
      end
    end

    if type == PersonPog::POG_HALF_MEAL
      warnings << "The Clubhouse tracks Half Meal Pogs digitally. Do not hand over a physical pog."
    end

    warnings
  end

  # timesheet_id links the pog to the just-ended shift entry (nullable);
  # PersonPog validates the entry belongs to the person.
  def create_pog_params
    params.expect(person_pog: [:pog, :notes, :timesheet_id])
  end

  def update_pog_note(pog)
    notes = scoped_params(:person_pog, :notes)[:notes].to_s
    if notes.blank?
      pog.errors.add(:notes, "Notes can't be blank. Add a note before saving.")
      return render_hq_modal("pog_edit_modal", { pog: }, status: :unprocessable_entity)
    end

    pog.update!(notes:)
    render_pog_update("Updated the pog note.")
  end

  def redeem_pog(pog)
    unless pog.pog == PersonPog::POG_HALF_MEAL && pog.status == PersonPog::STATUS_ISSUED
      return redirect_to shift_return_path,
                         error: "You can only redeem a 1/2 Meal Pog that is still issued. " \
                                "Reload the page to see this pog's current status."
    end

    pog.update!(status: PersonPog::STATUS_REDEEMED)
    render_pog_update("Redeemed the pog.")
  end

  # Cancellation REQUIRES a reason — marking a pog as accidentally issued
  # with no explanation is not allowed (upstream validatePresence).
  def cancel_pog(pog)
    notes = scoped_params(:person_pog, :notes)[:notes].to_s
    if notes.blank?
      pog.errors.add(:notes, "Notes can't be blank. Say why you are cancelling this pog.")
      return render_hq_modal("pog_cancel_modal", { pog: }, status: :unprocessable_entity)
    end

    pog.update!(status: PersonPog::STATUS_CANCELLED, notes:)
    render_pog_update("Cancelled the pog.")
  end

  def render_pog_update(message, signal: nil)
    streams = [
      pogs_stream,
      pogs_summary_stream,
      turbo_stream.update("modal", ""),
      *summary_streams,
      ui_toast_stream(message, :success)
    ]
    streams << hq_signal_stream(**signal) if signal
    render turbo_stream: streams
  end

  # The pogs panel's ended-shift banner shows the entry's review state, so
  # verification changes refresh it too (upstream reads live model state).
  def pogs_stream
    load_pogs
    @on_duty_entry = Timesheet.find_person_on_duty(@person.id)
    turbo_stream.update("hq-pogs",
                        partial: "hq/shift_manage/pogs",
                        locals: { pogs: @pogs, ended_entry: locate_ended_entry,
                                  on_duty_entry: @on_duty_entry,
                                  half_pog_enabled: @half_pog_enabled })
  end

  # The pog count also rides in the section's summary row, which sits outside
  # #hq-pogs — without this the row still claims "0 pogs recorded" after one is
  # issued and the section is folded away.
  def pogs_summary_stream
    turbo_stream.replace("hq-pogs-summary", helpers.hq_pogs_summary(@pogs))
  end

  # --- Shared stream helpers ------------------------------------------------

  # Replaces the signal element the hq-shift Stimulus controller watches;
  # its targetConnected callback applies the checklist transition.
  def hq_signal_stream(**data)
    render_data = data.transform_keys { |key| :"data-#{key.to_s.dasherize}" }
    turbo_stream.replace("hq-shift-signal",
                         partial: "hq/shift_manage/signal", locals: { data: render_data })
  end

  def summary_streams
    summary = build_timesheet_summary(Current.year)
    [
      turbo_stream.update("hq-earned-credits",
                          helpers.credit_format_short(summary.total_credits)),
      turbo_stream.update("hq-worked-hours",
                          helpers.hour_minute_words(summary.counted_duration))
    ]
  end

  # Guided flow folds a section down to its summary row, so that row is all the
  # operator can see of it — and every one of these counts is moved by the very
  # actions that stream. Reviewing the last entry or collecting the last radio
  # must not leave a folded row still demanding the thing that was just done.
  # Both rows are re-derived rather than patched so they cannot drift from the
  # section bodies they describe.
  def section_summary_streams
    load_timesheets
    load_assets
    @unreviewed_count = @timesheets_to_review.count(&:verification_required?)
    # replace, not update: each helper renders its own id'd span, so updating
    # would nest a second span inside the first.
    [
      turbo_stream.replace("hq-shift-summary",
                           helpers.hq_shift_summary(@on_duty_entry, @ended_entry,
                                                    @unreviewed_count)),
      turbo_stream.replace("hq-off-site-summary",
                           helpers.hq_off_site_summary(@person, off_site_pending_items))
    ]
  end

  # update (not append) so a re-opened dialog replaces the previous one
  # instead of stacking.
  def render_hq_modal(partial, locals = {}, status: :ok)
    render turbo_stream: turbo_stream.update("modal",
                                             partial: "hq/shift_manage/#{partial}",
                                             locals:),
           status:
  end

  def build_desired_position_options(entry)
    @desired_position_options = [["#{entry.position.title} is correct", nil]] +
                                person_position_options
  end

  def build_missing_position_options
    options = person_position_options
    dirt_positions = [Position::DIRT, Position::DIRT_POST_EVENT, Position::DIRT_GREEN_DOT]
    dirt_shifts, other_shifts = options.partition { |opt| dirt_positions.include?(opt[1]) }
    @missing_position_options = dirt_shifts + other_shifts
  end

  def person_position_options
    PersonPosition.retrieve_all_for_person(@person, include_eligibility: true,
                                                    include_past_grants: true)
                  .map { |position| [position.title, position.id] }
  end
end
