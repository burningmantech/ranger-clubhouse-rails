# frozen_string_literal: true

module ErrorLogTestHelper
  # Temporarily replace ErrorLog.record / record_exception with no-op
  # recorders so failure paths never write to the database. Yields the
  # captured calls (each a hash with :method, :type, :args, :kwargs) and
  # restores the originals. Extracted from moodle_test.rb.
  def silence_error_log
    calls = []
    originals = {}
    %i[record record_exception].each do |name|
      originals[name] = ErrorLog.method(name)
      ErrorLog.define_singleton_method(name) do |*args, **kwargs|
        calls << { method: name, type: args.first, args: args, kwargs: kwargs }
        nil
      end
    end
    yield calls
  ensure
    originals.each { |name, meth| ErrorLog.define_singleton_method(name, meth) }
  end
end
