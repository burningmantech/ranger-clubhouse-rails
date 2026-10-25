# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"
require "cgi"
require "json"
require "ostruct"
require "securerandom"

# Moodle LMS web-service client. Ported from the Laravel App\Lib\Moodle class.
#
# Every request is funnelled through {#request_web_service}, which is also the
# seam stubbed by unit tests. Decoded responses are returned as OpenStruct
# (objects) / Array (lists), mirroring PHP's json_decode(..., false) stdClass
# graph, so callers read fields with method access (e.g. user.idnumber).
class Moodle
  # Raised when Moodle responds with its maintenance page.
  class DownForMaintenanceError < StandardError; end

  # Raised when the Moodle host cannot be reached (DNS/TCP/TLS/timeout).
  class ConnectFailureError < StandardError; end

  LOGIN_URL = "/login/token.php"
  WEB_SERVICE_URL = "/webservice/rest/server.php"

  WS_COURSE_AVAILABLE = "core_course_get_courses"
  WS_COURSE_COMPLETION = "core_completion_get_course_completion_status"
  WS_SEARCH_USERS = "core_user_get_users"
  WS_CREATE_USERS = "core_user_create_users"
  WS_ENROLL_USERS = "enrol_manual_enrol_users"
  WS_ENROLLED_USERS = "core_enrol_get_enrolled_users"
  WS_UPDATE_USERS = "core_user_update_users"

  CONNECT_TIMEOUT = 10
  READ_TIMEOUT = 30

  attr_reader :domain, :token, :service_name, :student_role_id

  def initialize
    settings = Setting.get_value(
      [Setting::MOODLE_DOMAIN, Setting::MOODLE_TOKEN, Setting::MOODLE_SERVICE_NAME, Setting::MOODLE_STUDENT_ROLE_ID],
      throw_on_empty: true
    )

    @domain = settings[Setting::MOODLE_DOMAIN]
    @token = settings[Setting::MOODLE_TOKEN]
    @service_name = settings[Setting::MOODLE_SERVICE_NAME]
    @student_role_id = settings[Setting::MOODLE_STUDENT_ROLE_ID]
  end

  # Find all available courses (excluding the site "course").
  #
  # @return [Array<OpenStruct>]
  def retrieve_available_courses
    courses = request_web_service("GET", WS_COURSE_AVAILABLE)
    courses.reject { |r| r.format == "site" }
  end

  # Retrieve a single course.
  #
  # @param course_id [Integer]
  # @return [OpenStruct, nil]
  def retrieve_course_info(course_id)
    result = request_web_service("GET", WS_COURSE_AVAILABLE, { "options" => { "ids" => [course_id] } })
    result[0]
  end

  # Find user(s) by email address.
  #
  # @param query [String] email address
  # @return [Array<OpenStruct>]
  def find_person_by_email(query)
    result = request_web_service("GET", WS_SEARCH_USERS, {
      "criteria" => [{ "key" => "email", "value" => self.class.normalize_email(query) }]
    })
    result.is_a?(OpenStruct) ? (result.users || []) : []
  end

  # Find a user by the Moodle id.
  #
  # @param id [Integer]
  # @return [OpenStruct, nil]
  def find_person_by_moodle_id(id)
    result = request_web_service("GET", WS_SEARCH_USERS, {
      "criteria" => [{ "key" => "id", "value" => id }]
    })
    users = result.is_a?(OpenStruct) ? (result.users || []) : []
    users[0]
  end

  # Find everyone who is enrolled in a given course.
  #
  # @param course_id [Integer]
  # @return [Array<OpenStruct>]
  def retrieve_course_enrollment(course_id)
    request_web_service("GET", WS_ENROLLED_USERS, { "courseid" => course_id })
  end

  # Check to see if a person has completed a given course.
  #
  # @param course_id [Integer]
  # @param user_id [Integer]
  # @return [OpenStruct]
  def retrieve_course_completion(course_id, user_id)
    request_web_service("GET", WS_COURSE_COMPLETION, { "courseid" => course_id, "userid" => user_id })
  end

  # Retrieve everyone enrolled in a course and check whether they completed it.
  # NOTE: This is a *** SLOW *** lookup due to the number of API requests fired off.
  #
  # @param course_id [Integer]
  # @return [Array<OpenStruct>]
  def retrieve_course_enrollment_with_completion(course_id)
    students = retrieve_course_enrollment(course_id)
    people = find_clubhouse_users(students)
    students_by_id_number = {}

    students.each do |student|
      students_by_id_number[student.idnumber] = student if student.idnumber.present?

      unless student_role?(student)
        student.is_teacher = true
        next
      end

      completion = retrieve_course_completion(course_id, student.id)
      next unless completion.completionstatus.completed

      finished = self.class.latest_completion_timestamp(completion.completionstatus)
      if finished.positive?
        student.completed_at = Time.zone.at(finished).in_time_zone("America/Phoenix").to_s
      end
    end

    # NOTE: keyed lookup mirrors the source exactly (uses the Moodle id here).
    people.each do |row|
      student = students_by_id_number[row.id]
      next unless student

      person = row.person
      student.person = OpenStruct.new(id: person.id, callsign: person.callsign, status: person.status)
    end

    students.sort! do |a, b|
      if a.person && b.person
        a.person.callsign.casecmp(b.person.callsign)
      elsif a.person
        -1
      elsif b.person
        1
      else
        a.email.casecmp(b.email)
      end
    end

    students
  end

  # Update a user's profile.
  #
  # @param user [Hash] Moodle user attributes (must include "id")
  # @return [Object] decoded response
  def update_user(user)
    result = request_web_service("POST", WS_UPDATE_USERS, { "users" => [user] })
    self.class.check_for_warnings(result, WS_UPDATE_USERS)
    result
  end

  # Run through an enrollment roster, associate Moodle users with Clubhouse
  # accounts, and mark those found as completing the course.
  #
  # @param course [OnlineCourse]
  # @return [void]
  def process_course_completion(course)
    course_id = course.course_id
    year = course.year
    enrolled = retrieve_course_enrollment(course_id)
    students = find_clubhouse_users(enrolled)

    people_ids = students.map { |student| student.person.id }

    completed_already = {}
    if people_ids.any?
      PersonOnlineCourse.where(person_id: people_ids, position_id: course.position_id, year: year)
                        .where.not(completed_at: nil)
                        .pluck(:person_id)
                        .each { |person_id| completed_already[person_id] = true }
    end

    students.each do |student|
      person = student.person

      next if completed_already[person.id]

      # Not a student, teachers are not marked as completed.
      next unless student_role?(student)

      result = retrieve_course_completion(course_id, student.id)
      next unless result.completionstatus.completed

      finished = self.class.latest_completion_timestamp(result.completionstatus)
      if finished.positive?
        completed = Time.zone.at(finished).in_time_zone("America/Phoenix")
        # Not completed in the course year.
        next if completed.year != year
      else
        completed = Current.time
      end

      poc = PersonOnlineCourse.first_or_new_for_person_year(person.id, year, course.position_id)
      poc.online_course_id = course.id
      poc.completed_at = completed
      poc.audit_reason = "course completion"
      poc.save(validate: false)
    end
  end

  # Bulk look up Clubhouse accounts using the Moodle idnumber (Clubhouse id).
  #
  # @param users [Array<OpenStruct>] Moodle roster entries
  # @return [Array<OpenStruct>] entries with a #person Person attached
  def find_clubhouse_users(users)
    ids = users.filter_map { |user| user.idnumber.to_i if user.idnumber.present? }
    return [] if ids.empty?

    people_by_id = Person.where(id: ids)
                         .select(:id, :callsign, :status, :email, :lms_id)
                         .index_by(&:id)

    found = []
    users.each do |row|
      next if row.idnumber.blank?

      person = people_by_id[row.idnumber.to_i]
      if person
        row.person = person
        found << row
      end
    end

    found
  end

  # Try to link the Clubhouse account with Moodle by email lookup.
  #
  # @param person [Person] account to link
  # @return [Boolean] true if the Moodle user was found
  def find_person(person)
    result = find_person_by_email(person.email)
    return false if result.empty?

    user = result[0]
    person.lms_username = user.username
    person.lms_id = user.id
    person.audit_reason = "linked moodle account"
    person.save(validate: false)
    true
  end

  # Create a Moodle user for the given person.
  #
  # @param person [Person]
  # @return [String] the generated password
  def create_user(person)
    password = self.class.generate_password(person)
    username = self.class.build_moodle_username(person)

    result = request_web_service("POST", WS_CREATE_USERS, {
      "users" => [{
        "username" => username,
        "email" => self.class.normalize_email(person.email),
        "password" => password,
        "firstname" => person.desired_first_name,
        "lastname" => person.last_name,
        "idnumber" => person.id
      }]
    })

    if result[0].nil? || result[0].id.blank?
      ErrorLog.record("lms-request-failure", data: { service: WS_CREATE_USERS, result: result })
      raise "LMS create user response missing id"
    end

    person.lms_username = username
    person.lms_id = result[0].id
    person.audit_reason = "moodle account creation"
    person.save(validate: false)

    ActionLog.record(Current.person, "lms-user-create", "", {
      lms_id: person.lms_id,
      lms_username: username
    }, person.id)

    password
  end

  # Enroll a person in a Moodle course.
  #
  # @param person [Person] person to enroll
  # @param poc [PersonOnlineCourse]
  # @param course [OnlineCourse]
  # @return [void]
  def enroll_person(person, poc, course)
    # Person already enrolled
    return if poc.online_course_id == course.id

    result = request_web_service("POST", WS_ENROLL_USERS, {
      "enrolments" => [{
        "userid" => person.lms_id,
        "courseid" => course.course_id,
        "roleid" => student_role_id.to_i
      }]
    })
    self.class.check_for_warnings(result, WS_ENROLL_USERS)

    poc.online_course_id = course.id
    poc.enrolled_at = Current.time
    poc.save(validate: false)

    ActionLog.record(Current.person, "lms-enrollment", "", {
      lms_course_id: course.course_id,
      online_course_id: course.id
    }, person.id)
  end

  # Link the person's Moodle account by email, or create one, then enroll it
  # in the course unless it already is. An account that already existed has
  # its name and email brought up to date before a new enrollment.
  #
  # Upstream (setupPerson) meant to sync only on a new enrollment, but a typo
  # (course_id for online_course_id) made it sync on every call.
  #
  # @param person [Person]
  # @param course [OnlineCourse]
  # @return [void]
  def set_up_person(person, course)
    new_account = person.lms_id.blank? && !find_person(person)
    create_user(person) if new_account

    poc = PersonOnlineCourse.first_or_new_for_person_year(person.id, course.year, course.position_id)
    return if poc.online_course_id == course.id

    unless new_account
      sync_person_info(person)
      ActionLog.record(person, "lms-sync-user", "course enrollment sync")
    end

    enroll_person(person, poc, course)
  end

  # Scan a course enrollment and link/repair Clubhouse <-> Moodle associations.
  #
  # @param course_id [Integer]
  # @return [Array(Array<OpenStruct>, Array<OpenStruct>)] [updated, not_found]
  def link_users_in_course(course_id)
    students = retrieve_course_enrollment(course_id)

    ids = []
    emails = []
    students.each do |student|
      ids << student.idnumber.to_i if student.idnumber.present?
      emails << student.email
    end

    people_by_id = Person.where(id: ids).index_by(&:id)
    people_by_email = Person.where(email: emails).index_by(&:email)

    not_found = []
    updated = []

    students.each do |student|
      if student.idnumber.present?
        person = people_by_id[student.idnumber.to_i]
        # Looks good!
        next if person && person.lms_id == student.id && person.lms_username == student.username
      end

      person = people_by_email[student.email]
      if person.nil?
        not_found << student
        next
      end

      person.lms_id = student.id
      person.lms_username = student.username
      person.audit_reason = "moodle user id association"
      person.save(validate: false)

      clubhouse_id = person.id
      update_user({ "id" => student.id, "idnumber" => clubhouse_id })
      student.idnumber = clubhouse_id
      updated << student
    end

    [updated, not_found]
  end

  # Sync the user's Moodle info (including username) with the Clubhouse info,
  # and keep the username it sent, as find_person and create_user keep theirs.
  #
  # @param person [Person]
  # @return [void]
  def sync_person_info(person)
    username = self.class.build_moodle_username(person)
    person.lms_username = username

    update_user({
      "id" => person.lms_id,
      "username" => username,
      "email" => self.class.normalize_email(person.email),
      "firstname" => person.desired_first_name,
      "lastname" => person.last_name
    })

    person.audit_reason = "moodle user info sync"
    person.save(validate: false)
  end

  # Reset the person's Moodle password.
  #
  # @param person [Person]
  # @return [String] the generated password
  def reset_password(person)
    password = self.class.generate_password(person)
    update_user({ "id" => person.lms_id, "password" => password })
    password
  end

  # Make a Moodle API request. Single choke point for all web-service traffic
  # (and the seam stubbed by tests).
  #
  # @param method [String] HTTP verb ("GET" or "POST")
  # @param service [String] wsfunction name
  # @param data [Hash] extra request parameters
  # @return [Object] decoded response
  def request_web_service(method, service, data = {})
    query = {
      "wstoken" => token,
      "moodlewsrestformat" => "json",
      "wsfunction" => service
    }.merge(data)

    request_path = "https://#{domain}#{WEB_SERVICE_URL}"
    uri = URI.parse("#{request_path}?#{self.class.build_query(query)}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = CONNECT_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request =
      case method
      when "GET"
        Net::HTTP::Get.new(uri)
      when "POST"
        post = Net::HTTP::Post.new(uri)
        post.set_form_data({})
        post
      else
        raise "Unknown method [#{method}]"
      end

    begin
      response = http.request(request)
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError, OpenSSL::SSL::SSLError => e
      message = e.message
      ErrorLog.record("moodle-connect-failure", data: {
        message: message,
        url: request_path,
        query: self.class.redact_sensitive_data(query)
      })
      raise ConnectFailureError, message
    end

    self.class.decode_response(response, request_path)
  end

  class << self
    # Decode a Moodle response and return the parsed JSON graph.
    #
    # @param response [#code, #body] the HTTP response (or a test double)
    # @param request_path [String] domain + endpoint, without the querystring
    # @return [Object] OpenStruct / Array / scalar
    def decode_response(response, request_path)
      if response.code.to_i >= 400
        body = response.body.to_s
        if body.downcase.include?("undergoing maintenance")
          ErrorLog.record("lms-down-for-maintenance")
          raise DownForMaintenanceError
        end

        status = response.code.to_i
        ErrorLog.record("lms-request-failure", data: { status: status, body: body, url: request_path })
        raise "HTTP LMS request status error status=#{status}"
      end

      begin
        json = JSON.parse(response.body, object_class: OpenStruct)
      rescue JSON::ParserError => e
        ErrorLog.record_exception(e, "lms-decode-exception", extra: { body: response.body, url: request_path })
        raise "LMS JSON decode exception"
      end

      if json.is_a?(OpenStruct) && !json.exception.nil?
        ErrorLog.record("lms-request-failure", data: { json: json.to_h, url: request_path })
        raise "LMS request exception #{json.exception}"
      end

      json
    end

    # Check a decoded Moodle write response for a non-empty top-level "warnings"
    # array. Moodle write services can return HTTP 200 with no top-level
    # "exception" but a populated "warnings" array, meaning the operation was
    # actually skipped/rejected server-side.
    #
    # @param result [Object] the decoded Moodle response
    # @param service [String] the wsfunction name, for logging
    # @return [void]
    def check_for_warnings(result, service)
      warnings = result.is_a?(OpenStruct) ? (result.warnings || []) : []
      return if warnings.empty?

      ErrorLog.record("lms-request-warning", data: { service: service, warnings: warnings })
      raise "LMS request warning for #{service}"
    end

    # Redact sensitive keys (wstoken, password) from a request payload before it
    # is written to the error log. Only the top-level keys are redacted, matching
    # the source.
    #
    # @param data [Hash]
    # @return [Hash] a redacted copy
    def redact_sensitive_data(data)
      redacted = data.dup
      %w[wstoken password].each do |key|
        redacted[key] = "[REDACTED]" if redacted.key?(key)
      end
      redacted
    end

    # Strip any plus-alias out of an email address, e.g. convert
    # "account+alias@domain.com" to "account@domain.com". Moodle cannot deal
    # with such email addresses.
    #
    # @param email [String]
    # @return [String]
    def normalize_email(email)
      email.to_s.gsub(/(\+.*)(?=@)/, "")
    end

    # Build a username from the person's callsign: strip "(NR)", trim, downcase,
    # convert diacritics, and drop non-word characters.
    #
    # @param person [Person]
    # @return [String]
    def build_moodle_username(person)
      username = person.callsign.to_s.gsub(/\(NR\)/i, "")
      username = username.strip.downcase
      convert_diacritics(username).gsub(/[^\w]/, "")
    end

    # Generate a password based on the person's real name:
    # <LastName><First Initial>!<6 random digits>, padded to 10 characters with
    # random letters, and guaranteed at least one lowercase letter.
    #
    # The random portions use a cryptographically secure source
    # (SecureRandom.random_number) since this password is used for real Moodle
    # account creation and password resets.
    #
    # @param person [Person]
    # @return [String]
    def generate_password(person)
      letters = "abcdefghijk"
      last_name = ucfirst(convert_diacritics(person.last_name).downcase)
      first_name = convert_diacritics(person.desired_first_name)
      password = ucfirst(last_name.gsub(/[^\w]/, "") + ucfirst(first_name[0, 1].to_s)) + "!"

      6.times { password << SecureRandom.random_number(10).to_s }

      password << letters[SecureRandom.random_number(letters.length)] while password.length < 10

      # Ensure at least one lower case letter appears.
      password << letters[SecureRandom.random_number(letters.length)] unless password.match?(/[a-z]/)

      password
    end

    # Find the latest (max) timecompleted timestamp among a completion status's
    # completions.
    #
    # @param completion_status [OpenStruct]
    # @return [Integer]
    def latest_completion_timestamp(completion_status)
      Array(completion_status.completions).filter_map(&:timecompleted).max || 0
    end

    # Build a PHP http_build_query-compatible query string, using numeric
    # indices for arrays (users[0][username]=...) so Moodle reconstructs nested
    # structures correctly.
    #
    # @param data [Hash]
    # @return [String]
    def build_query(data)
      flatten_query(data).map { |key, value| "#{CGI.escape(key)}=#{CGI.escape(value.to_s)}" }.join("&")
    end

    private

    # Convert diacritics to ASCII. Stands in for Person::convertDiacritics
    # without touching the Person model.
    def convert_diacritics(value)
      ActiveSupport::Inflector.transliterate(value.to_s)
    end

    # Uppercase the first character only, leaving the rest untouched (PHP ucfirst).
    def ucfirst(value)
      value.upcase_first
    end

    # Recursively flatten a nested hash/array into [key, scalar] pairs using
    # PHP bracket notation with numeric array indices.
    def flatten_query(value, prefix = nil)
      pairs = []
      case value
      when Hash
        value.each do |k, v|
          key = prefix ? "#{prefix}[#{k}]" : k.to_s
          pairs.concat(flatten_query(v, key))
        end
      when Array
        value.each_with_index do |v, index|
          pairs.concat(flatten_query(v, "#{prefix}[#{index}]"))
        end
      else
        pairs << [prefix, value]
      end
      pairs
    end
  end

  private

  # Whether the Moodle roster entry holds the configured student role.
  def student_role?(student)
    Array(student.roles).any? { |role| role.roleid == student_role_id }
  end
end
