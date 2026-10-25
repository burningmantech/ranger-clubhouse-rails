# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  prepend_view_path Rails.root.join("app/views/mail")

  # Asked before the folder above, so a message whose wording is kept in the
  # Clubhouse wins over anything still left on disk.
  prepend_view_path MailTemplateResolver.new

  layout "mailer"

  # Whether this mailer's mail log rows go without the email's text. A mailer
  # whose email carries a live sign-in secret or someone's private message
  # sets it true: any VC can open any person's Mail Log. Its rows still say
  # who sent it, to whom, when, the subject and the outcome. No instance
  # reader or predicate, since Action Mailer takes any public method here for
  # an email it can send.
  class_attribute :withhold_body_from_mail_log, default: false, instance_accessor: false, instance_predicate: false

  before_action :set_sender_id
  after_action :hold_mail_on_training_server
  after_deliver :record_mail_log

  default from: -> { EmailAddresses::DO_NOT_REPLY }

  # Add default URL options for link generation in emails
  # Prefer Action Mailer config (set per-environment) over routes defaults
  def default_url_options
    Rails.application.config.action_mailer.default_url_options || Rails.application.routes.default_url_options
  end

  # Everything below builds a message rather than being one. Action Mailer takes
  # any public method here for something it can be asked to send, so these stay
  # out of reach; helper_method still hands liquid_assigns to the template.
  private

  # The values this message's template can read. A mailer fills this in instead
  # of setting instance variables: a template reads plain values only -- words,
  # numbers, lists, and groups of those -- so anything it needs to show has to be
  # worked out here first.
  #
  # Every message can name the Clubhouse's own address, clubhouse_url, so no
  # template writes a host.
  def liquid_assigns
    @liquid_assigns ||= { logo_url:, clubhouse_url: root_url }
  end
  helper_method :liquid_assigns

  # Text a person typed, laid out as paragraphs with any web addresses turned
  # into links. What comes back is ready to show as it is, so a template prints
  # it without escaping it again.
  def formatted_text(text)
    ActionController::Base.helpers.auto_link(ActionController::Base.helpers.simple_format(text))
  end

  # The subject kept with this message's template, filled in from the same values
  # as the body. Falls back to the wording passed in when the template carries no
  # subject of its own.
  def liquid_subject(fallback = nil)
    source = MailTemplate.find_by(tag: "#{mailer_name}/#{action_name}")&.subject
    return fallback if source.blank?

    MailTemplateRenderer.render(source, liquid_assigns, escape_html: false).strip
  end

  # Who sent this email, for its mail log rows. A queued email is built again
  # inside a job, where nobody is signed in, so its sender travels with it:
  # .with(sender_id:) at the deliver_later call. Otherwise it is whoever is
  # signed in now -- nobody for a password reset or a scheduled job.
  def set_sender_id
    @sender_id = params.fetch(:sender_id) { Current.person&.id }
  end

  # Writes this email's mail log rows, one per To address, once it has gone --
  # sent now or from a queued job -- or been held on the training server. A
  # delivery that raised never gets here, and a message with no To address,
  # such as one an action never built, writes nothing. The email has gone by
  # now, so rows that cannot be written go to the error log instead and never
  # fail it: not a password reset's page, not a mail job. A mailer writing to
  # an applicant sets @prospective_application_id, the application the rows
  # belong to.
  def record_mail_log
    MailLog.record_delivery(message, sender_id: @sender_id, withhold_body: self.class.withhold_body_from_mail_log,
                                     prospective_application_id: @prospective_application_id)
  rescue StandardError => e
    ErrorLog.record_exception(e, "mail-log-exception", extra: { mailer: self.class.name, action: action_name })
  end

  # The training server runs on a copy of real accounts, so anything it sends
  # reaches real people. Messages are still built and can be read in the log;
  # they simply never leave the building.
  def hold_mail_on_training_server
    message.perform_deliveries = false if Current.is_ghd_server?
  end

  # From address helpers - return email address strings
  def from_vc
    EmailAddresses::VOLUNTEER_COORDINATORS_TEAM
  end

  def from_do_not_reply
    EmailAddresses::DO_NOT_REPLY
  end

  def from_training_academy
    EmailAddresses::TRAINING_ACADEMY
  end

  # Addresses separated by commas or written one per line -- Setting stores its
  # email lists the second way.
  def build_addresses(addresses_string)
    addresses_string.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end

  # The Ranger logo, spelled out in full. A mail reader has no page to work a
  # short address out from, so the address has to carry the site with it --
  # root_url's, like every other link in a message.
  def logo_url
    ActionController::Base.helpers.asset_url("ranger-logo.png", host: root_url)
  end

  # Format sender name for email headers
  def format_from(email, name)
    "#{name} <#{email}>"
  end

  def vc_from
    format_from(from_vc, "Ranger Volunteer Coordinators")
  end

  def do_not_reply_from(name = "Ranger Clubhouse")
    format_from(from_do_not_reply, name)
  end

  def training_academy_from
    format_from(from_training_academy, "Ranger Training Academy")
  end
end
