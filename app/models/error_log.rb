# frozen_string_literal: true

class ErrorLog < ApplicationRecord
  PAGE_SIZE_DEFAULT = 50

  belongs_to :person, optional: true

  # JSON serialization for the data column
  serialize :data, coder: JSON

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

      {
        error_logs: records,
        meta: {
          total: pagy_instance.count,
          total_pages: pagy_instance.pages,
          page_size: pagy_instance.limit,
          page: pagy_instance.page
        }
      }
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
        data[:method] = request.method
        # The filtered copy: request.params is a plain hash with no
        # to_unsafe_h, and the filter keeps passwords and secrets out of a log
        # more people can read than should hold them.
        data[:parameters] = request.parameters.to_hash
        data[:headers] = request.headers.env.select { |k, _| k =~ /^HTTP_/ }

        error[:ip] = request.remote_ip
        error[:user_agent] = request.user_agent
        error[:url] = request.original_url
      end

      error[:data] = data

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
        data[:method] = request.method
        data[:url] = request.original_url
        data[:parameters] = request.parameters.to_hash
        data[:headers] = request.headers.env.select { |k, _| k =~ /^HTTP_/ }
      end

      data.merge!(extra)

      error = {
        error_type: error_type,
        data: data
      }

      # Include the IP, user_agent and URL location
      if request
        error[:ip] = request.remote_ip
        error[:user_agent] = request.user_agent
        error[:url] = request.original_url
      end

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
