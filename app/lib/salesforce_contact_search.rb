# frozen_string_literal: true

# One search on VC › BPGUID Lookup: sign in, send the owner's SOSL statement
# over Salesforce Accounts once, and note the search in the Action Log against
# the person being linked, when one is shown. Read-only: it never calls
# obj_update. It also mints and checks the signed link each row's button carries.
#
# A FIND naming one object with neither WHERE nor ORDER BY stops at 250 records
# and says nothing about the rest (SOQL and SOSL Reference, "SOSL Limits on
# Search Results"), so capped? reports a full answer.
class SalesforceContactSearch
  # The owner's RETURNING list, in his column order.
  FIELDS = %w[FirstName LastName Email Burner_Profile_Email__c HomePhone Phone BPGUID__c npe01__Home_Address__c].freeze
  ROW_CAP = 250
  MAX_LENGTH = 80     # D16
  WILDCARD_STEM = 3   # D16: characters a word with * needs besides the *
  LINK_PURPOSE = :vc_bpguid_link
  LINK_LIFETIME = 2.hours

  Contact = Data.define(:name, :email, :burner_profile_email, :home_phone, :phone, :bpguid, :home_address) do
    # Both email fields, each address once whatever its case.
    def emails = [email, burner_profile_email].compact_blank.uniq(&:downcase)
    # Both phone fields, each number once whatever its punctuation.
    def phones = [home_phone, phone].compact_blank.uniq { |number| number.gsub(/\D/, "") }
  end

  attr_reader :text, :contacts, :error

  # A signed token for one row's button: the person, the contact's BPGUID, and
  # the BPGUID the person had when the row rendered (D8). Signed, not
  # encrypted -- it carries nothing the page does not show. Keys are strings,
  # so they read back the same whichever serializer the verifier uses.
  def self.link_token(person, bpguid)
    link_verifier.generate({ "person_id" => person.id, "bpguid" => bpguid, "was" => person.bpguid.to_s },
                           purpose: LINK_PURPOSE, expires_in: LINK_LIFETIME)
  end

  # @return [Hash, nil] nil when the token is forged, altered, expired or for another purpose
  def self.verified_link(token) = link_verifier.verified(token, purpose: LINK_PURPOSE)

  def self.link_verifier = Rails.application.message_verifier("vc-bpguid-link")

  # The connector default is evaluated per search, so tests can swap Salesforce.connector.
  # person is nil for a search run before anyone was looked up: no row is linkable.
  def initialize(text, person: nil, connector: Salesforce.connector)
    @text = text
    @person = person
    @connector = connector
    @contacts = []
  end

  def statement = "FIND {#{Salesforce.sosl_escape(text)}} RETURNING Contact (#{FIELDS.join(',')})"

  # D16: why the text is too broad to send, or nil. Checked before signing in,
  # so a refused text never reaches Salesforce. The stem counts the characters
  # around a * in each word, not where the * sits, so *tone passes.
  def refusal
    words = text.split
    if text.length > MAX_LENGTH
      "That search is longer than #{MAX_LENGTH} characters. Shorten it, then search again."
    elsif words.any? { |word| word.include?("*") && word.delete("*").length < WILDCARD_STEM }
      "A search with * needs at least #{WILDCARD_STEM} other characters, as in smi*. " \
        "Add more of the name or email, then search again."
    elsif words.any? { |word| word.casecmp?("OR") }
      "Search for one name or email at a time. Remove OR, then search again."
    end
  end

  # @return [self]
  def run
    if (@error = refusal)
      @refused = true
      return self # ensure still logs the attempt
    end

    envelope = begin
      @signed_in = @connector.auth
      @signed_in && @connector.sosl_search(statement, log_rejections: false)
    rescue StandardError => e
      # Salesforce turns only its NETWORK_ERRORS into false; anything else
      # (Net::HTTPBadResponse, Net::WriteTimeout, a malformed auth URL) raises.
      ErrorLog.record_exception(e, "salesforce-query-exception", extra: { query: statement })
      @error = "Salesforce query failed: #{e.class}"
      false
    end

    if envelope
      @contacts = envelope.searchRecords.map { |record| contact_from(record) }
    else
      @error ||= @connector.error_message
    end
    self
  ensure
    # D9: every search leaves one row, even one that raised or was refused. Never the contacts.
    ActionLog.record(Current.person, "salesforce-contact-search", "",
                     { search: text, total: (contacts.size unless error), error: }.compact, @person&.id)
  end

  def refused? = @refused == true
  def signed_in? = @signed_in == true
  def capped? = contacts.size >= ROW_CAP

  # D6: the contact is the person's current link (no button), or can become it (a button).
  # With no person shown, neither: there is no one to link to.
  def linked?(contact) = @person.present? && contact.bpguid.present? && contact.bpguid.casecmp?(@person.bpguid.to_s)
  def linkable?(contact) = @person.present? && contact.bpguid.present? && !linked?(contact)

  # Only a linkable row gets one, so a BPGUID no search returned cannot be written.
  def link_token(contact) = self.class.link_token(@person, contact.bpguid)

  # The count line, and the sentence the live region reads. Plain text; the
  # caller escapes it. A capped answer says so here too: the warning callout
  # arrives already holding its words, so a screen reader never hears it.
  def summary
    if refused?
      "The search was not sent."
    elsif error
      "The search did not run."
    elsif capped?
      "#{contacts.size} contacts. Salesforce stops at #{ROW_CAP}, so there may be more."
    elsif contacts.any?
      "#{contacts.size} #{"contact".pluralize(contacts.size)}."
    else
      "Salesforce found no contacts for this search. Try the Burner Profile email the member sent, " \
        "check the spelling, or end the name or email with * to match the start of it."
    end
  end

  private

  # Salesforce sends a field the integration user can read as null when empty;
  # a field missing from the record (the mock, the fake) reads nil from OpenStruct.
  def contact_from(record)
    Contact.new(
      name: [record.FirstName, record.LastName].compact_blank.join(" "),
      email: record.Email,
      burner_profile_email: record.Burner_Profile_Email__c,
      home_phone: record.HomePhone,
      phone: record.Phone,
      bpguid: record.BPGUID__c.to_s.strip.presence,
      home_address: record.npe01__Home_Address__c
    )
  end
end
