# frozen_string_literal: true

# Acts on a webhook only when Twilio signed it. Twilio signs each request it
# posts with the account's auth token, over the address it was given and every
# parameter it posts, and sends the result as X-Twilio-Signature
# (https://www.twilio.com/docs/usage/security). Every parameter, not a list of
# the ones read: Twilio adds new ones without notice.
#
# The address is this server's public one, from configuration, never the
# request's: Rails builds request.url from Host and X-Forwarded-Host, which
# anyone can set, so a request Twilio signed for another server -- Clubhouse 2,
# say -- would pass here too, replayed under that server's name.
module TwilioSignatureConcern
  extend ActiveSupport::Concern

  included do
    before_action :refuse_unsigned_twilio_request
  end

  # This server's address for path, as Twilio is given it: https, on the name
  # mail links to (RANGER_CLUBHOUSE_HOST in production).
  def self.address(path)
    "https://#{Rails.application.config.action_mailer.default_url_options[:host]}#{path}"
  end

  private

  # Anything else is answered 403 and changes nothing, and so is everything
  # while the auth token is not set: there is nothing to check against. The
  # error log keeps the address checked, never the parameters, which hold the
  # text.
  def refuse_unsigned_twilio_request
    token = Setting.get_value(Setting::TWILIO_AUTH_TOKEN).presence
    signature = request.headers["X-Twilio-Signature"].to_s
    return if token && signed_by_twilio?(token, signature)

    ErrorLog.record(token ? "twilio-signature-invalid" : "twilio-auth-token-not-configured",
                    data: { url: TwilioSignatureConcern.address(request.path), signed: signature.present? })
    head :forbidden
  end

  # An address URI cannot read -- raw non-ASCII in the query, say -- is none
  # Twilio was given, so none it signed.
  def signed_by_twilio?(token, signature)
    url = TwilioSignatureConcern.address(request.original_fullpath)
    Twilio::Security::RequestValidator.new(token).validate(url, request.request_parameters, signature)
  rescue URI::InvalidURIError
    false
  end
end
