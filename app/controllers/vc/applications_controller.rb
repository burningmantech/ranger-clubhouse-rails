# frozen_string_literal: true

# Volunteer Coordinator management of prospective (volunteer) applications.
class Vc::ApplicationsController < ApplicationController
  include CsvExportConcern

  layout "vc"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to manage applications."

  DIALOGS = %w[
    assign adjust_status status_message approve_callsign edit_approved_handle
    edit_handles more_handles send_email problem_review note_form note_delete
  ].freeze

  EDIT_SECTIONS = %w[details personal_info].freeze

  before_action :set_application, except: %i[index search]

  def index
    setup_year
    @years = EventYearSpan.years(2015, current_year).reverse
    @applications = ProspectiveApplication.find_for_query(year: @year).to_a
    @vcs = volunteer_coordinators
    @filter = Vc::ApplicationFilterForm.from_params(params, user_id: current_user.id)
    @filtered_applications = @filter.apply(@applications)
    @status_counts = status_counts(@applications)
    @active_preset = @filter.active_preset(user_id: current_user.id)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-prospective-applications.csv") }
    end
  end

  def show
    @application.screen_handles
    @related_applications = @application.related_applications
    @vcs = volunteer_coordinators
  end

  def edit_details
  end

  def edit_personal_info
  end

  # Modal dialogs rendered into the "modal" turbo frame.
  def dialog
    raise ActionController::RoutingError, "Unknown dialog" unless DIALOGS.include?(params[:dialog])

    @vcs = volunteer_coordinators if params[:dialog] == "assign"
    if params[:dialog].in?(%w[note_form note_delete]) && params[:note_id].present?
      @note = ProspectiveApplicationNote.find_note_for_application!(@application.id, params[:note_id])
    end
    render "vc/applications/dialogs/#{params[:dialog]}", layout: false
  end

  def update
    # First, so a prospective_application that is not a set of fields is
    # refused (400) before apply_problem_handles and update_success_message
    # read it.
    attrs = application_params
    section = EDIT_SECTIONS.find { |name| name == params[:section] }

    @application.assign_attributes(attrs)
    apply_problem_handles
    if @application.save(context: section == "personal_info" ? :personal_info : nil)
      redirect_to vc_application_path(@application), success: update_success_message
    elsif section
      render "edit_#{section}", status: :unprocessable_entity
    else
      redirect_to vc_application_path(@application), error: @application.errors.full_messages.join(" ")
    end
  end

  def destroy
    year = @application.year
    @application.destroy
    redirect_to vc_applications_path(year:), success: "Application deleted."
  end

  # Change the status through the real workflow: record handle rejections /
  # the approved handle where applicable, then email the applicant.
  def status
    new_status = params.expect(:status)
    message = params[:message].presence

    case new_status
    when ProspectiveApplication::STATUS_MORE_HANDLES
      @application.record_rejections(message)
    when ProspectiveApplication::STATUS_APPROVED, ProspectiveApplication::STATUS_HOLD_PII_ISSUE
      @application.approved_handle = params[:approved_handle] if params[:approved_handle].present?
    end

    @application.status = new_status
    @application.save!
    ProspectiveApplicationStatusMail.execute(@application, new_status, message)

    redirect_to vc_application_path(@application), success: status_success_message(new_status)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to vc_application_path(@application), error: e.record.errors.full_messages.join(" ")
  end

  # Mark the "Why Ranger?" paragraph as problematic, recording the reason
  # as a VC comment.
  def problem_review
    message = params.expect(:message)
    @application.update!(why_volunteer_review: ProspectiveApplication::WHY_VOLUNTEER_REVIEW_PROBLEM)
    ProspectiveApplicationNote.create!(
      prospective_application: @application,
      person_id: current_user.id,
      type: ProspectiveApplicationNote::TYPE_VC_COMMENT,
      note: "Why Ranger Review: #{message}"
    )
    redirect_to vc_application_path(@application), success: "Paragraph marked as problematic."
  end

  # Render the email a status change (or a raw VC email) would send.
  # Displayed inside the dialogs' preview iframe.
  def preview_email
    html = if params[:is_raw_email].present?
             message = ProspectiveApplication::SendEmailMailer.send_message(
               application: @application,
               email_subject: params[:subject].presence || "",
               email_message: params[:message].presence || "").message
             (message.html_part || message).body.decoded
           else
             ProspectiveApplicationStatusMail.preview(@application, params.expect(:status), params[:message].presence)
           end

    render html: html.html_safe, layout: false
  rescue ArgumentError => e
    render html: e.message, layout: false
  end

  # Free-form email to the applicant from the VC address.
  def send_email
    delivery = ProspectiveApplication::SendEmailMailer.send_message(
      application: @application,
      email_subject: params.expect(:subject),
      email_message: params.expect(:message))
    ProspectiveApplicationStatusMail.deliver_and_log(@application, delivery)

    redirect_to vc_application_path(@application), success: "Email sent."
  end

  # Run the submitted handles through the AI extractor and show the results
  # for review before saving.
  def extract_handles
    extracted = AiHandlesExtract.execute(@application.handles)
    @extracted_handles = extracted.map(&:first).join("\n")
    @problem_handles = extracted.select { |_handle, problems| problems.present? }
    render :extract_handles, layout: false
  rescue ArgumentError => e
    redirect_to vc_application_path(@application), error: e.message
  end

  def search
    @query = params[:query].to_s.strip
    if @query.length < 3
      redirect_to vc_applications_path, warning: "Please enter at least 3 characters to search."
      return
    end

    @results = ProspectiveApplication.search_for_applications(@query)
  end

  private

  def set_application
    @application = ProspectiveApplication
                     .includes(*ProspectiveApplication::FULL_INCLUDES)
                     .find(params[:id].to_s.sub(/\A[Aa]-/, ""))
  rescue ActiveRecord::RecordNotFound
    redirect_to vc_applications_path, error: "Application not found."
  end

  # The details form submits event years as a checkbox array, stored as
  # events_attended.
  def application_params
    attrs = params.expect(prospective_application: [
      :status, :is_over_18, :why_volunteer, :why_volunteer_review, :regional_experience,
      :known_rangers, :known_applicants, :events_attended,
      :first_name, :last_name, :email, :street, :city, :state, :postal_code, :country,
      :phone, :emergency_contact,
      :assigned_person_id, :handles, :approved_handle, event_years: []
    ])
    years = attrs.delete(:event_years)
    attrs[:events_attended] = Array(years).compact_blank.join(";") if years
    attrs
  end

  # The extracted-handles form submits problem handles as a JSON string of
  # [handle, problems] pairs. Assigned directly — strong params would strip the
  # nested array. Anything else is ignored rather than stored: the application
  # page walks the stored value as a list, so a number there would break it.
  def apply_problem_handles
    raw = params[:prospective_application]&.[](:problem_handles)
    return unless raw.is_a?(String) && raw.present?

    handles = JSON.parse(raw)
    @application.problem_handles = handles if handles.is_a?(Array)
  rescue JSON::ParserError
    nil
  end

  def update_success_message
    if params.dig(:prospective_application, :assigned_person_id)
      if @application.assigned_person_id == current_user.id
        "Application assigned to you."
      elsif @application.assigned_person_id.nil?
        "Application is now unassigned."
      else
        "Application assigned."
      end
    else
      "Application saved."
    end
  end

  def status_success_message(new_status)
    case new_status
    when ProspectiveApplication::STATUS_APPROVED
      "Application approved, and the applicant emailed."
    when ProspectiveApplication::STATUS_MORE_HANDLES
      "More Handles request submitted."
    else
      "Status updated."
    end
  end

  # The applications the page is showing, in its order, so the file and the
  # screen say the same thing. The name is split and the event years spelled
  # out, which the table folds into one cell and a check mark.
  def csv_rows
    rows = [["Application", "Status", "First Name", "Last Name", "Email", "Assigned To",
             "18 or Older", "BRC Events", "BRC Qualified", "Last Updated"]]

    @filtered_applications.each do |application|
      rows << [application.application_id, application.status_label,
               application.first_name, application.last_name, application.email,
               application.assigned_person&.callsign || "Unassigned",
               csv_yes_no(application.is_over_18), application.all_events.join(", "),
               csv_yes_no(application.brc_experience_okay?), application.updated_by_person_at&.iso8601]
    end

    rows
  end

  def volunteer_coordinators
    PersonPosition.retrieve_grants(Position::VOLUNTEER_COORDINATOR)
  end

  def status_counts(applications)
    counts = Hash.new(0)
    applications.each do |application|
      case
      when application.status_pending? then counts[:pending] += 1
      when application.processing_callsign? then counts[:callsign] += 1
      when application.held_status? then counts[:held] += 1
      when application.status_approved? then counts[:approved] += 1
      when application.status_created? then counts[:created] += 1
      when application.stop_status? then counts[:rejected] += 1
      end
    end
    counts
  end
end
