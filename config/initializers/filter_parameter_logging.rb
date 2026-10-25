# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # A single sign-on code, exactly that name: a refused return is logged with
  # its parameters, and the code stays redeemable for two minutes.
  /\Acode\z/,
  # What a passkey presents, exactly that name. Nothing in it can be replayed,
  # but it is a kilobyte or two of base64 in the log at every sign-in.
  /\Acredential\z/,
  # A SOQL query typed on the Salesforce Query page, exactly that name: its
  # WHERE clause can name a person.
  /\Asoql\z/
]
