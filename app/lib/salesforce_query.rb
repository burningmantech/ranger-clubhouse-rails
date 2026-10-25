# frozen_string_literal: true

# One run of what was typed on Administration › Salesforce Query: sign in, send
# it once -- a statement beginning FIND to the SOSL search, anything else to the
# SOQL query -- flatten the records into columns and rows, and note the run in
# the Action Log. Read-only: it never calls obj_update.
#
# A query shows only its first batch (up to 2,000 records). nextRecordsUrl is
# never followed, so total can exceed the rows; truncated? says so. A search is
# never paged, and its records can mix object types, so it leads with each
# record's attributes.type.
class SalesforceQuery
  # A child-relationship subquery's cell: how many records the child set holds.
  Children = Data.define(:total)

  attr_reader :soql, :columns, :rows, :total, :error

  # The connector default is evaluated per run, so tests can swap Salesforce.connector.
  def initialize(soql, connector: Salesforce.connector)
    @soql = soql
    @connector = connector
    @columns = []
    @rows = []
    @numeric = []
  end

  # @return [self]
  def run
    envelope = begin
      @signed_in = @connector.auth
      @signed_in && send_statement
    rescue StandardError => e
      # Salesforce turns only its NETWORK_ERRORS into a false return. Anything
      # else -- Net::HTTPBadResponse, Net::WriteTimeout, a malformed auth URL --
      # raises out of auth, soql_query or sosl_search.
      ErrorLog.record_exception(e, "salesforce-query-exception", extra: { query: soql })
      @error = "Salesforce query failed: #{e.class}"
      false
    end

    if envelope && search?
      @total = envelope.searchRecords.size
      flatten(envelope.searchRecords)
    elsif envelope
      @total = envelope.totalSize
      # The mock connector leaves done out; a missing done is a complete answer.
      @truncated = envelope.done == false
      flatten(envelope.records)
    else
      @error ||= @connector.error_message
    end
    self
  ensure
    # Every run leaves exactly one row, even one that raised. Never the records.
    ActionLog.record(Current.person, "salesforce-query", "", { soql:, total:, error: }.compact)
  end

  # SOSL opens with FIND; anything else is sent as SOQL, for Salesforce to refuse
  # if it is neither.
  def search? = soql.match?(/\A\s*find\b/i)
  def signed_in? = @signed_in == true
  def truncated? = @truncated == true
  def numeric?(index) = @numeric[index]

  private

  def send_statement
    if search?
      @connector.sosl_search(soql, log_rejections: false)
    else
      @connector.soql_query(soql, log_rejections: false)
    end
  end

  def flatten(records)
    records = records.map { |record| plain(record) }
    shape = {}
    records.each { |record| merge_shape(shape, record) }
    @columns = paths(shape)
    # The one part of "attributes" worth a column: which object each found
    # record is. cell walks the dotted path like any other.
    @columns.unshift("attributes.type") if search? && records.any?
    @rows = records.map { |record| @columns.map { |path| cell(record, path) } }
    # Once per column, never per cell: a column is numeric when it holds a value
    # and every value it holds is a number or a child count. Booleans are not.
    @numeric = @columns.each_index.map do |index|
      values = @rows.map { |row| row[index] }.compact
      values.any? && values.all? { |value| value.is_a?(Numeric) || value.is_a?(Children) }
    end
  end

  # OpenStruct answers a field named like one of its own methods (an aggregate
  # aliased to_h or each_pair) with the field's value; the bang alias always
  # reaches the method.
  def plain(value)
    case value
    when OpenStruct then value.to_h!.to_h { |key, entry| [key.to_s, plain(entry)] }
    when Array then value.map { |entry| plain(entry) }
    else value
    end
  end

  def branch?(value) = value.is_a?(Hash) && !children?(value)

  def children?(value) = value.is_a?(Hash) && value["records"].is_a?(Array)

  # One ordered tree of every key seen; first appearance wins its place.
  # "attributes" (type and url) rides on every record and relationship and is
  # dropped. A relationship that is null in one row and an object in another is
  # a leaf that later becomes a branch -- assigning to an existing Hash key keeps
  # its position, so the branch stays where the SELECT put it.
  def merge_shape(shape, record)
    record.each do |key, value|
      next if key == "attributes"

      if branch?(value)
        shape[key] = {} unless shape[key].is_a?(Hash)
        merge_shape(shape[key], value)
      else
        shape[key] = nil unless shape.key?(key)
      end
    end
  end

  # Depth-first, joined with dots: Ranger_Info__r.MailingCity. API names and
  # aliases cannot hold a dot, so the names are unambiguous.
  def paths(shape, prefix = nil)
    shape.flat_map do |key, sub|
      name = prefix ? "#{prefix}.#{key}" : key
      sub ? paths(sub, name) : [name]
    end
  end

  # A null or scalar along the way gives nil rather than raising.
  def cell(record, path)
    value = path.split(".").reduce(record) { |node, key| node.is_a?(Hash) ? node[key] : nil }
    children?(value) ? Children.new(total: value["totalSize"]) : value
  end
end
