# frozen_string_literal: true

# Stands in for Amazon SES. Every SES client in the test environment is a
# stand-in already (config/environments/test.rb), answering nothing; a test
# that sends email decides here what SES says back.
#
# Each answer is worked out from that entry's own address, never from where it
# sits in the call: an id of "ses-<address>" that lands on someone else's row
# is a result handed to the wrong person, and a test can see it.
module SesTestHelper
  # The id the stand-in SES gives every email sent through :ses_mail.
  SES_MAIL_ID = "0100018f2b6c1a2e-ses-mail-000000"

  # Every person in the call is taken.
  ACCEPT_ALL = lambda do |context|
    { bulk_email_entry_results: context.params[:bulk_email_entries].map do |entry|
      { status: "SUCCESS", message_id: "ses-#{SesTestHelper.address_of(entry)}" }
    end }
  end

  # Every person in the call is taken but those named, keyed by bare address.
  # Each of them is refused with the status given, or with the whole answer
  # when a test needs SES's own words too:
  #
  #   SesTestHelper.refusing(baker.email => { status: "MESSAGE_REJECTED", error: "Not verified." })
  def self.refusing(refusals)
    lambda do |context|
      { bulk_email_entry_results: context.params[:bulk_email_entries].map do |entry|
        address = address_of(entry)
        case (refusal = refusals[address])
        when nil then { status: "SUCCESS", message_id: "ses-#{address}" }
        when Hash then refusal
        else { status: refusal }
        end
      end }
    end
  end

  # The To line of one entry, name and all.
  def self.to_line_of(entry)
    entry[:destination][:to_addresses].first
  end

  # The bare address one entry was sent to, without the name in front of it.
  def self.address_of(entry)
    Mail::Address.new(to_line_of(entry)).address
  end

  # Records every SendBulkEmail call SES is asked to make, with the responder
  # answering it, and puts back whatever stood in for SES before.
  def with_ses(responder = ACCEPT_ALL)
    calls = []
    previous = Aws.config[:sesv2]
    Aws.config[:sesv2] = previous.merge(stub_responses: {
                                          send_bulk_email: lambda do |context|
                                            calls << context.params
                                            responder.call(context)
                                          end
                                        })
    yield calls
  ensure
    Aws.config[:sesv2] = previous
  end

  # Sends ActionMailer mail for one block through :ses_mail, as production does
  # once it opts in, to a stand-in SES that answers every SendEmail call with
  # the responder's answer. Yields the calls, and puts back the delivery method
  # and its settings.
  def with_ses_mail(responder = ->(_context) { { message_id: SES_MAIL_ID } })
    calls = []
    restoring_delivery do
      ActionMailer::Base.delivery_method = :ses_mail
      ActionMailer::Base.ses_mail_settings = {
        sesv2_client: Aws::SESV2::Client.new(stub_responses: {
                                               send_email: lambda do |context|
                                                 calls << context.params
                                                 responder.call(context)
                                               end
                                             })
      }
      yield calls
    end
  end

  # Puts back ActionMailer's delivery method and the :ses_mail settings after
  # one block, whatever it set them to.
  def restoring_delivery
    delivery_method = ActionMailer::Base.delivery_method
    settings = ActionMailer::Base.ses_mail_settings
    yield
  ensure
    ActionMailer::Base.delivery_method = delivery_method
    ActionMailer::Base.ses_mail_settings = settings
  end

  # Whether broadcast email may go to Rangers, for one block. Production reads
  # it from the server; the tests start with it on.
  def with_rangers_emailed(value)
    original = Rails.configuration.x.rbs_email_rangers
    Rails.configuration.x.rbs_email_rangers = value
    yield
  ensure
    Rails.configuration.x.rbs_email_rangers = original
  end

  # Turns broadcast sandboxes off. The fixtures start with every one on, so
  # nothing a test does leaves the building unless it asks.
  def sandbox_off(*settings)
    settings.each { |setting| Setting.find_by(name: setting).update!(value: "false") }
    Rails.cache.clear
  end

  # Turns one broadcast sandbox back on.
  def sandbox_on(setting)
    Setting.find_by(name: setting).update!(value: "true")
    Rails.cache.clear
  end

  # Sends broadcast email to a test address. Saved without validation so a
  # test can also store a pattern the settings page would refuse.
  def set_test_address(pattern)
    setting = Setting.find_or_initialize_by(name: Setting::BROADCAST_MAIL_TEST_ADDRESS)
    setting.value = pattern
    setting.save!(validate: false)
  end

  def ses_to_lines(call)
    call[:bulk_email_entries].map { |entry| SesTestHelper.to_line_of(entry) }
  end

  def ses_addresses(call)
    call[:bulk_email_entries].map { |entry| SesTestHelper.address_of(entry) }
  end

  def ses_template_data(call)
    JSON.parse(call[:default_content][:template][:template_data])
  end
end
