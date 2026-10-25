# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"
require "json"
require "ostruct"

# Salesforce REST client: OAuth2 password grant plus the SOQL query and SOSL
# search endpoints.
# Ported from the Laravel App\Lib\SalesforceConnector class.
#
# Unlike Moodle, failures are soft: methods return false and leave the reason
# in #error_message. The application import renders partial results plus an
# error banner when Salesforce dies mid-run, and that contract depends on
# "false, keep going" rather than an exception unwinding the whole run.
#
# Every request is funnelled through {#execute_request}, the seam stubbed by
# unit tests. Decoded responses are OpenStruct graphs, mirroring PHP's
# json_decode stdClass access (row.Ranger_Info__r.MailingCity).
class Salesforce
  # The REST API version every data call rides on. The source pinned updates to
  # v51.0 while querying v57.0; both are unified here so the version is one knob.
  API_VERSION = "v57.0"

  TOKEN_PATH = "/services/oauth2/token"
  QUERY_PATH = "/services/data/#{API_VERSION}/query"
  SEARCH_PATH = "/services/data/#{API_VERSION}/search/"
  SOBJECT_PATH = "/services/data/#{API_VERSION}/sobjects"

  CONNECT_TIMEOUT = 10
  READ_TIMEOUT = 60

  NETWORK_ERRORS = [
    SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError, OpenSSL::SSL::SSLError
  ].freeze

  # Reserved inside FIND {...} (SOQL and SOSL Reference, "Reserved Characters"):
  # "An error occurs if you do not precede reserved characters with a backslash.
  # This is true even if the SearchQuery is enclosed in double quotes."
  SOSL_RESERVED = /[?&|!{}\[\]()^~*:\\"'+\-]/

  AUTH_SETTINGS = [
    Setting::SF_PRD_AUTH_URL,
    Setting::SF_PRD_CLIENT_ID,
    Setting::SF_PRD_CLIENT_SECRET,
    Setting::SF_PRD_USERNAME,
    Setting::SF_PRD_PASSWORD
  ].freeze

  attr_reader :error_message, :instance_url

  # The connector the import should talk to. SF_MOCK_DATA short-circuits to
  # canned data so the page can be exercised without Salesforce credentials;
  # the guard keeps the mock strictly out of production.
  #
  # @return [Salesforce, Salesforce::MockConnector]
  def self.connector
    if Rails.env.development? && ENV["SF_MOCK_DATA"].present?
      MockConnector.new
    else
      new
    end
  end

  # Authenticate using the OAuth2 password grant (login password + security
  # token). On success the token response's instance_url becomes the base for
  # all query traffic. No token caching, matching the source: every import
  # run re-authenticates.
  #
  # @return [Boolean]
  def auth
    settings = Setting.get_value(AUTH_SETTINGS)
    blank = AUTH_SETTINGS.select { |name| settings[name].blank? }
    if blank.any?
      @error_message = "Salesforce settings are blank: #{blank.join(', ')}. " \
                       "Set them on the Admin > Settings page."
      return false
    end

    uri = URI.parse("#{settings[Setting::SF_PRD_AUTH_URL].chomp('/')}#{TOKEN_PATH}")
    request = Net::HTTP::Post.new(uri)
    request.set_form_data(
      "grant_type" => "password",
      "client_id" => settings[Setting::SF_PRD_CLIENT_ID],
      "client_secret" => settings[Setting::SF_PRD_CLIENT_SECRET],
      "username" => settings[Setting::SF_PRD_USERNAME],
      "password" => settings[Setting::SF_PRD_PASSWORD]
    )

    begin
      response = execute_request(uri, request)
    rescue *NETWORK_ERRORS => e
      @error_message = "Failed to retrieve the authentication token: #{e.message}"
      # Only the URL is logged, never the credentials.
      ErrorLog.record_exception(e, "salesforce-auth-exception", extra: { auth_url: uri.to_s })
      return false
    end

    result = decode_body(response, auth_url: uri.to_s)
    return false unless result

    if response.code.to_i >= 400 || result.access_token.blank?
      @error_message = "Salesforce authentication failed: #{result.error}: #{result.error_description}"
      ErrorLog.record("salesforce-request-exception", data: { auth_url: uri.to_s, result: result.to_h })
      return false
    end

    @access_token = result.access_token
    @instance_url = result.instance_url
    true
  end

  # Run a SOQL query.
  #
  # @param soql [String]
  # @param log_rejections [Boolean] false keeps a query Salesforce refused as
  #   malformed (HTTP 400) out of the Error Log -- the Salesforce Query page
  #   shows that error to the person who typed it. Every other failure is logged.
  # @return [OpenStruct, false] the response envelope (.records, .totalSize), or false
  def soql_query(soql, log_rejections: true)
    result = get_statement(QUERY_PATH, soql, log_rejections:)
    return false unless result

    unless result.is_a?(OpenStruct) && result.records.is_a?(Array)
      @error_message = "Salesforce query returned an unexpected response"
      ErrorLog.record("salesforce-query-failed", data: { query: soql, result: result })
      return false
    end

    result
  end

  # Run a SOSL search (FIND {...}). The answer is one list of records that can
  # mix object types, each naming its own in attributes.type. It carries no
  # totalSize and is never paged: SOSL stops at 2,000 records.
  #
  # @param sosl [String]
  # @param log_rejections [Boolean] as for soql_query
  # @return [OpenStruct, false] the response envelope (.searchRecords), or false
  def sosl_search(sosl, log_rejections: true)
    result = get_statement(SEARCH_PATH, sosl, log_rejections:)
    return false unless result

    unless result.is_a?(OpenStruct) && result.searchRecords.is_a?(Array)
      @error_message = "Salesforce search returned an unexpected response"
      ErrorLog.record("salesforce-query-failed", data: { query: sosl, result: })
      return false
    end

    result
  end

  # Write fields back to a Salesforce object. A success is 204 No Content with
  # an empty body, so nothing is decoded.
  #
  # @param objname [String] the object type, e.g. "Ranger__c"
  # @param objid [String] the record id
  # @param fields [Hash] field name => new value
  # @return [Boolean]
  def obj_update(objname, objid, fields)
    uri = URI.parse("#{instance_url.chomp('/')}#{SOBJECT_PATH}/#{objname}/#{objid}")
    request = Net::HTTP::Patch.new(uri)
    request["Authorization"] = "Bearer #{@access_token}"
    request["Content-Type"] = "application/json"
    request.body = fields.to_json

    begin
      response = execute_request(uri, request)
    rescue *NETWORK_ERRORS => e
      @error_message = "Salesforce update failed: #{e.message}"
      # The fields carry applicant data, so only the record is identified.
      ErrorLog.record_exception(e, "salesforce-update-exception", extra: { objname:, objid: })
      return false
    end

    if response.code.to_i >= 400
      @error_message = "Salesforce update failed: #{query_error_from(response)}"
      ErrorLog.record("salesforce-update-exception",
                      data: { objname:, objid:, status: response.code.to_i,
                              body: response.body.to_s.first(2000) })
      return false
    end

    true
  end

  class << self
    # Quote a value for a single-quoted SOQL literal, backslash-escaping
    # backslash and quote (port of the source's addslashes defense). The ids
    # fed through this come from Salesforce itself, but quote anyway.
    #
    # @param value [String]
    # @return [String] the quoted literal, e.g. "'a01'"
    def soql_quote(value)
      "'#{value.to_s.gsub(/['\\]/) { |c| "\\#{c}" }}'"
    end

    # Escape text for the inside of FIND {...}, keeping * as the wildcard. Every
    # other reserved character -- ? and the backslash included -- is escaped in
    # one pass, so typed text can never close the braces or add a clause: IN,
    # RETURNING and LIMIT become plain search words.
    #
    # @param text [String]
    # @return [String]
    def sosl_escape(text)
      text.to_s.gsub(SOSL_RESERVED) { |c| c == "*" ? c : "\\#{c}" }
    end
  end

  private

  # Make an HTTPS request. Single choke point for all Salesforce traffic (and
  # the seam stubbed by tests). Network failures raise; callers convert them
  # to the soft false-plus-error_message contract.
  #
  # @param uri [URI]
  # @param request [Net::HTTPRequest]
  # @return [Net::HTTPResponse]
  def execute_request(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = CONNECT_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.request(request)
  end

  # GET a data resource that takes its statement as ?q= -- the query and the
  # search -- and decode the answer. A network failure, an HTTP error or a body
  # that is not JSON returns false with error_message set and an Error Log row
  # written, except an HTTP 400 when log_rejections is false.
  def get_statement(path, statement, log_rejections:)
    uri = URI.parse("#{instance_url.chomp('/')}#{path}")
    uri.query = URI.encode_www_form(q: statement)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@access_token}"

    begin
      response = execute_request(uri, request)
    rescue *NETWORK_ERRORS => e
      @error_message = "Salesforce query failed: #{e.message}"
      ErrorLog.record_exception(e, "salesforce-query-exception", extra: { query: statement })
      return false
    end

    if response.code.to_i >= 400
      @error_message = "Salesforce query failed: #{query_error_from(response)}"
      if log_rejections || response.code.to_i != 400
        ErrorLog.record("salesforce-query-exception",
                        data: { query: statement, status: response.code.to_i, body: response.body.to_s.first(2000) })
      end
      return false
    end

    decode_body(response, query: statement) || false
  end

  # Decode a response body into an OpenStruct graph, or record the parse
  # failure and return nil with error_message set.
  def decode_body(response, context)
    JSON.parse(response.body, object_class: OpenStruct)
  rescue JSON::ParserError => e
    @error_message = "Failed to decode the Salesforce response: #{e.message}"
    ErrorLog.record_exception(e, "salesforce-json-exception",
                              extra: context.merge(body: response.body.to_s.first(2000)))
    nil
  end

  # Salesforce reports query errors as a JSON array of {errorCode, message};
  # fall back to the HTTP status when the body is something else.
  def query_error_from(response)
    error = JSON.parse(response.body).first
    "#{error['errorCode']}: #{error['message']}"
  rescue StandardError
    "status #{response.code}"
  end
end
