# frozen_string_literal: true

class ErrorLog < ApplicationRecord
  PAGE_SIZE_DEFAULT = 50

  # Set on a request's env once its failure is accounted for -- a row written
  # here with the request, or an answer in the 500s given on purpose -- so
  # RequestLogger does not add a second, generic row for the same answer.
  HANDLED_ENV = "clubhouse.failure_handled"

  # Headers that are a session or a login in themselves. The parameter filter
  # catches the ones named for a token or a key; these it does not.
  SECRET_HEADER = /COOKIE|AUTHORIZATION/

  belongs_to :person, optional: true

  # JSON serialization for the data column
  serialize :data, coder: JSON

  truncates_to_column :user_agent, :ip, :url

  # A pre-Rails legacy row can hold data that was never valid JSON, and the
  # coder above raises on every read of such a row -- not just the first.
  # Callers that just want to display whatever is there use this instead of
  # the raw `data` accessor.
  def data_or_nil
    data
  rescue JSON::ParserError
    nil
  end

  class << self
    include Pagy::Method

    # Find error logs based on query criteria
    #
    # @param query [Hash] Query parameters
    #   - person_id: person to find
    #   - error_type: specific error type
    #   - start_at: error record on or after datetime
    #   - ends_at: error record on or before datetime
    #   - last_day: errors from the last 24 hours
    #   - sort: 'asc' or 'desc' (default: 'desc')
    #   - page: page number (1 to n)
    #   - page_size: size of page (default: PAGE_SIZE_DEFAULT)
    #
    # @return [Hash] { error_logs:, meta: { total:, total_pages:, page_size:, page: } }
    def find_for_query(query)
      scope = all

      # Specific person to find
      if query[:person_id].present?
        scope = scope.where(person_id: query[:person_id])
      end

      # Specific error type to find
      if query[:error_type].present?
        scope = scope.where(error_type: query[:error_type])
      end

      # Logged on or after a specific datetime
      if query[:start_at].present?
        scope = scope.where("created_at >= ?", query[:start_at])
      end

      # Logged on or before a specific datetime
      if query[:ends_at].present?
        scope = scope.where("created_at <= ?", query[:ends_at])
      end

      # Logged in the last day
      if query[:last_day]
        scope = scope.where("created_at >= ?", 1.day.ago)
      end

      # Results sort 'asc' or 'desc'
      sort_order = (query[:sort] == "asc") ? :asc : :desc
      scope = scope.order(created_at: sort_order)

      # Eager load person association (equivalent to Laravel with('person:id,callsign'))
      scope = scope.includes(:person)

      # Extract pagination parameters
      page = (query[:page] || 1).to_i
      page_size = (query[:page_size] || PAGE_SIZE_DEFAULT).to_i
      page_size = PAGE_SIZE_DEFAULT if page_size <= 0

      # Use Pagy for pagination
      # Provide minimal request hash since models don't have self.request
      pagy_instance, records = pagy(:offset, scope, page: page, limit: page_size, request: { params: {} })

      { error_logs: records, pagy: pagy_instance }
    end

    # Record an error
    #
    # @param error_type [String] The type of error to record
    # @param data [Hash] Additional data to log (default: {})
    # @param request [ActionDispatch::Request, nil] The request object (optional)
    def record(error_type, data: {}, request: nil)
      error = {
        error_type: error_type
      }

      if request
        data.merge!(request_data(request))

        error.merge!(request_columns(request))
      end

      error[:person_id] = Current.person.id if Current.person
      error[:data] = storable(data)

      create!(error)
    end

    # Record a Ruby exception
    #
    # @param exception [Exception] The exception which occurred
    # @param error_type [String] The type to record
    # @param extra [Hash] Any additional data to be logged (default: {})
    # @param request [ActionDispatch::Request, nil] The request object (optional)
    def record_exception(exception, error_type, extra: {}, request: nil)
      # Inspect the exception for message, source location, and backtrace
      data = {}

      # Parse the first line of backtrace to get file and line
      first_backtrace = exception.backtrace&.first
      file, line = if first_backtrace
                     parts = first_backtrace.split(":")
                     [parts[0], parts[1]&.to_i]
                   else
                     [nil, nil]
                   end

      data[:exception] = {
        message: exception.message,
        file: file,
        line: line,
        stacktrace: exception.backtrace
      }

      # Record the method and parameters from request
      if request
        data.merge!(request_data(request), url: stored_url(request))
      end

      data.merge!(extra)

      error = {
        error_type: error_type,
        data: storable(data)
      }

      # Include the IP, user_agent and URL location
      error.merge!(request_columns(request)) if request

      # Who is the user?
      if Current.person
        error[:person_id] = Current.person.id
      end

      begin
        create!(error)
      rescue ActiveRecord::StatementInvalid => e
        # Silently fail if database error occurs while logging
        # Could add emergency logging here if needed
      end
    end

    private

    # What a request carried, fit to store. Every crash lands here, the
    # sign-in form's included, so parameters and headers are masked the way
    # the Rails log masks parameters. The filter is built here: a request
    # carries one only once the application has put it there.
    def request_data(request)
      headers = request.headers.env.select { |k, _| k.start_with?("HTTP_") }.reject { |k, _| k.match?(SECRET_HEADER) }

      { method: request.method, parameters: stored_parameters(request), headers: parameter_filter.filter(headers) }
    end

    # The columns every row with a request fills in. Writing them also marks
    # the request, so its failure is not recorded a second time.
    def request_columns(request)
      request.env[HANDLED_ENV] = true

      { ip: request.remote_ip, user_agent: request.user_agent, url: stored_url(request) }
    end

    # Without the query string: its values are in the parameters, masked, and
    # in the address they would not be.
    def stored_url(request)
      "#{request.base_url}#{request.path}"
    end

    # Nothing is kept from a page a stranger fills in (RequestLogger says
    # which), and a request whose parameters cannot be read -- often the very
    # reason it failed -- still gets its row.
    def stored_parameters(request)
      return "[NOT STORED]" if RequestLogger::UNFILTERABLE_RESPONSE_PATHS.include?(request.path)

      parameter_filter.filter(request.parameters.to_hash)
    rescue ActionController::BadRequest
      "[UNREADABLE]"
    end

    def parameter_filter
      @parameter_filter ||= ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    end

    # Text the JSON column can take: bytes that are not UTF-8 would refuse the
    # whole row, and an uploaded file has no text form but its name.
    def storable(value)
      case value
      when String then value.dup.force_encoding(Encoding::UTF_8).scrub
      when ActionDispatch::Http::UploadedFile then value.original_filename
      when Hash then value.transform_values { |entry| storable(entry) }
      when Array then value.map { |entry| storable(entry) }
      else value
      end
    end

    public

    # Delete the entire error log and record who did it.
    #
    # @param actor [Person] who requested the purge
    # @return [Integer] number of rows deleted
    def purge!(actor)
      # The wipe and the record of it stand or fall together -- a purge with no
      # audit line leaves no trace that it happened.
      transaction do
        count = delete_all
        ActionLog.record(actor, "error-log-purge", "Deleted all error log entries", { count: count })
        count
      end
    end
  end
end
