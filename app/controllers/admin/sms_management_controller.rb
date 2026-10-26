# frozen_string_literal: true

# Administration › SMS Management: the texts Twilio sent and received on the
# Clubhouse's account, what Twilio reports about the account, and the settings
# the Clubhouse texts with. The Clubhouse's own record of the texts it sent is
# RBS › Message log. Tech Team only, as Background Jobs is: the log holds
# members' numbers and texts, and the account panel its balance.
class Admin::SmsManagementController < ApplicationController
  include CsvExportConcern

  layout "admin"

  authorize_role [Role::TECH_NINJA], message: "Tech Ninja role required to manage SMS."

  # The two panels are frames inside a page that has already built the menus.
  skip_before_action :build_menu_items, only: [:twilio, :messages, :update_incoming]
  before_action :set_form, only: [:index, :messages]
  # The training server holds the same live credentials as the real one.
  before_action -> { prevent_if_ghd_server("Changing where Twilio sends incoming texts") }, only: :update_incoming

  CSV_HEADERS = ["Sent", "Direction", "Status", "Error Code", "Callsign", "Number", "Text"].freeze

  def index
    respond_to do |format|
      format.html { @settings = SmsManagement.settings }
      format.csv { export }
    end
  end

  # The Twilio Account panel, loaded into its frame on its own so the page
  # never waits on Twilio. Refresh asks Twilio again instead of reading the
  # cached answer.
  def twilio
    @status = TwilioStatus.fetch(refresh: params[:refresh].present?)
    render layout: false
  end

  # One page of Twilio's message log, loaded into its frame the same way.
  def messages
    @log = TwilioMessageLog.page(@form.criteria, page: @form.page, token: @form.page_token)
    render layout: false
  end

  # Points every incoming text at another address, starting with the next
  # one: this server's at the cutover from Clubhouse 2, or back again. Only a
  # server set up for it may (SmsManagement.incoming_changes_allowed?). The
  # account panel's frame then reloads past its cache to show the change.
  def update_incoming
    url = params.expect(twilio_incoming: [:url])[:url].to_s.strip
    problem = SmsManagement.incoming_url_problem(url)
    if problem
      redirect_to admin_sms_management_twilio_path, error: "Twilio was not changed: #{problem}."
      return
    end

    result = SmsManagement.point_incoming_texts(url)
    if result.nil?
      flash[:error] = "Twilio was not changed: the Account SID and Auth Token are not set."
    else
      record_incoming_change(url, result)
      flash[:success] = incoming_changed_message(url, result[:changed]) if result[:changed].any?
      flash[:error] = incoming_problem_message(result) if result[:error]
    end
    redirect_to admin_sms_management_twilio_path(refresh: 1)
  end

  private

  # The action log keeps how each service handled incoming texts until now, so
  # the change can be put back, ids masked and addresses as the page shows
  # them. A change that went out with no answer back is kept too, marked: it
  # may have been made.
  def record_incoming_change(url, result)
    services = result[:changed].map { |change| logged_change(change) }
    services << logged_change(result[:unsure]).merge(unanswered: true) if result[:unsure]
    return if services.empty?

    ActionLog.record(Current.person, "twilio-incoming-update",
                     "Pointed Twilio's incoming texts at #{helpers.sms_url_shown(url)}", { url:, services: })
  end

  def logged_change(change)
    before = change[:before]
    { service: helpers.sms_masked_id(change[:service]),
      before: before.merge(url: shown_url(before[:url]), fallback_url: shown_url(before[:fallback_url])) }
  end

  def shown_url(url) = (helpers.sms_url_shown(url) if url.present?)

  def incoming_changed_message(url, changed)
    before = changed.map { |change| helpers.sms_url_shown(change[:before][:url]) }.uniq.to_sentence
    message = "Twilio now sends incoming texts to #{helpers.sms_url_shown(url)}. It sent them to #{before} until now."
    fallbacks = changed.filter_map { |change| shown_url(change[:before][:fallback_url]) }.uniq
    fallbacks.empty? ? message : "#{message} The fallback address #{fallbacks.to_sentence} is cleared."
  end

  def incoming_problem_message(result)
    error = helpers.sms_mask_sids(result[:error])
    if result[:unsure]
      "Twilio did not confirm the change, so it may or may not have been made (#{error}). " \
        "The address below shows where Twilio sends incoming texts now."
    elsif result[:changed].any?
      "Twilio stopped partway, and the rest was not changed: #{error}."
    else
      "Twilio was not changed: #{error}."
    end
  end

  def set_form
    @form = SmsFilterForm.new(scoped_params(SmsFilterForm::PARAM_SCOPE, *SmsFilterForm.attribute_names))
  end

  def export
    export = TwilioMessageLog.export(@form.criteria)
    problem = if export.nil?
                "the Account SID and Auth Token are not set"
              elsif export[:error]
                helpers.sms_mask_sids(export[:error])
              end

    if problem
      redirect_to admin_sms_management_path(@form.query_params), error: "The texts could not be exported: #{problem}."
    else
      send_csv(csv_rows(export), filename: "twilio-texts-#{Date.current.iso8601}.csv")
    end
  end

  # The newest texts the filters match, as Twilio lists them, newest first.
  def csv_rows(export)
    rows = export[:texts].map do |text|
      [text.sent_at.in_time_zone.strftime(DateTimeHelper::CSV_TIME), helpers.rbs_direction_word(text.direction),
       text.status, text.error_code, export[:people][text.number]&.callsign, csv_phone(text.number), text.body]
    end
    [CSV_HEADERS, *rows]
  end

  # A number as the page shows it, kept as text: one PhoneFormatter leaves
  # bare (+447700900123) is marked as a formula lead is, or a spreadsheet
  # would read it as a number and drop its "+".
  def csv_phone(number)
    shown = PhoneFormatter.format(number)
    shown.match?(CsvExportConcern::PLAIN_NUMBER) ? "'#{shown}" : shown
  end
end
