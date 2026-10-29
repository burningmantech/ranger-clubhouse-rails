# frozen_string_literal: true

# A short-lived code handed out while someone signs in to another website.
# Modelled here so a client's codes go with it when the client is deleted.
class OauthCode < ApplicationRecord
  self.table_name = "oauth_code"

  # How long a code may be redeemed for after it is handed out.
  EXPIRE_IN_SECONDS = 120

  belongs_to :oauth_client
  belongs_to :person

  # The code as handed out. Only the object that issued it knows it: the table
  # keeps a digest, so reading the table redeems nothing.
  attr_reader :code

  def code=(plain)
    @code = plain
    self.code_digest = plain && self.class.digest(plain)
  end

  # Hand out a code for the website to redeem within EXPIRE_IN_SECONDS.
  #
  # @return [OauthCode] with #code holding the plain code
  def self.issue(client, person, scope)
    create!(oauth_client: client, person: person, scope: scope, code: SecureRandom.urlsafe_base64(48))
  end

  # A fast hash is the right one here: the code is 64 random characters, so
  # there is nothing to guess, and a slow hash would only slow the sign-in.
  def self.digest(plain)
    Digest::SHA256.hexdigest(plain)
  end

  # Take back the code a website presents. A code is good once: the row is
  # removed, and whichever of two redeemers removes it is the one that gets
  # it back -- and only when it was this website's and still in date.
  #
  # @return [OauthCode, nil]
  def self.redeem(client, code)
    return nil if code.blank?

    row = find_by(oauth_client_id: client.id, code_digest: digest(code))
    return nil unless row && where(id: row.id).delete_all == 1
    return nil if row.created_at <= EXPIRE_IN_SECONDS.seconds.ago

    row
  end

  # Housekeeping for codes handed out and never presented. The time limit is
  # enforced when a code is redeemed; this keeps the table from filling with
  # rows no one will ever present.
  #
  # @return [Integer] how many codes were removed
  def self.delete_expired
    where(created_at: ..EXPIRE_IN_SECONDS.seconds.ago).delete_all
  end
end
