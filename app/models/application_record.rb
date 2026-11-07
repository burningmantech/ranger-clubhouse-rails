# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  include AttachmentKey

  # What an empty rich text editor submits: empty blocks, never an empty string.
  # Lexxy sends "<p><br></p>", or an empty list, heading, quote, code block or
  # table if a tool was clicked with nothing typed, or "<p><strong> </strong></p>"
  # for a space typed in bold; the editor before it sent "<div><br></div>". A
  # column that holds rich text normalizes these to "", so a presence validation
  # and `.present?` mean what they say.
  #
  # Empty is decided the way the editor decides it for a required field: no words.
  # The elements listed here are content without any, so a document that is one
  # divider or one image is kept.
  BLANK_WHEN_EMPTY_RICH_TEXT = lambda do |html|
    fragment = Nokogiri::HTML5.fragment(html)
    fragment.text.present? || fragment.at_css("hr, img, iframe, video, audio, object, embed") ? html : ""
  end

  class_attribute :audit_model, instance_accessor: false, default: false
  class_attribute :audit_exclude, instance_accessor: false, default: [].freeze

  attr_accessor :audit_user_id, :audit_reason, :audit_is_new, :audit_changes

  # A varchar or text column holds only so much, and under strict SQL mode a
  # longer value is not cut short: MariaDB raises ActiveRecord::ValueTooLong,
  # which reaches the reader as an error page. So every model refuses one first,
  # as a message beside the field, measured as the column measures it:
  # varchar(N) holds N characters; TEXT, MEDIUMTEXT and LONGTEXT hold that many
  # bytes.
  #
  # It runs after the model's own validations and passes over a field they
  # already refused, so the field gets one message rather than two; a rule that
  # did not measure the value (allow_blank, if:) leaves it to the column.
  # ActiveRecord counts an error added here, since valid? answers errors.empty?
  # once the callbacks have run. Only a value being written is measured, since
  # one read from the table already fits; a value composed later, in a
  # before_save, is its model's to measure (AccessDocument#additional_comments_fit).
  after_validation :values_fit_their_columns

  # A value nobody typed, such as a browser's user agent or address, is cut to
  # fit its column rather than refused: no one can shorten it, and the refusal
  # would fail whatever save wrote it. Request headers arrive as binary, so the
  # cut is made on the UTF-8 text and never splits a character; a text column is
  # cut to its bytes.
  def self.truncates_to_column(*names)
    names.each do |name|
      normalizes name, with: lambda { |value|
        column = columns_hash[name.to_s]
        text = value.dup.force_encoding(Encoding::UTF_8).scrub
        column.type == :string ? text.first(column.limit) : text.truncate_bytes(column.limit, omission: "")
      }
    end
  end

  # The most characters a form field for the attribute should take: its own
  # length rule's maximum, else a varchar column's width. nil for a text column,
  # whose limit is in bytes, which no maxlength can express (AppFormBuilder).
  def self.length_limit(name)
    own_length_limit(name) || columns_hash[name.to_s].then { |column| column.limit if column&.type == :string }
  end

  # The whole-number maximum the attribute's own length rules set, or nil.
  def self.own_length_limit(name)
    validators_on(name).filter_map { |rule| rule.options.values_at(:maximum, :is).grep(Integer).first if rule.kind == :length }.min
  end

  after_create :audit_create
  after_update :audit_update
  before_destroy :capture_audit_destroy_state
  after_destroy :audit_destroy

  def changed_values
    normalize_audit_hash(audit_source_changes.slice(*self.class.column_names))
  end

  def audited_values
    data = normalize_audit_hash((audit_changes || changed_values).deep_dup)
    filter_audit_excluded!(data)
    data
  end

  def filter_audit_excluded!(data)
    self.class.audit_exclude.each { |column| data.delete(column.to_s) }
  end

  private

  def values_fit_their_columns
    self.class.columns_hash.each do |name, column|
      next unless column.limit && column.type.in?(%i[string text]) && attribute_changed?(name)
      next if errors.include?(name)

      # As it will be written: a serialized column's text, not its Hash.
      value = read_attribute_for_database(name)
      next unless value.is_a?(String)

      # MariaDB trims spaces past the end of a column with only a note, so a
      # value too long by trailing spaces alone still saves.
      value = value.sub(/ +\z/, "") if value.end_with?(" ")
      if column.type == :string
        errors.add(name, :too_long, count: column.limit) if value.length > column.limit
      elsif value.bytesize > column.limit
        errors.add(name, :too_long_to_save)
      end
    end
  end

  # ActiveRecord's save answers false to any RecordInvalid raised inside it,
  # including one from another record written in this one's callbacks (an
  # audit row, a log entry, a note), and the form would come back with nothing
  # on it to fix. So that record's complaint becomes this one's.
  def create_or_update(...)
    super
  rescue ActiveRecord::RecordInvalid => e
    raise if e.record.equal?(self)

    e.record.errors.each { |error| errors.add(:base, error.full_message) }
    raise ActiveRecord::RecordInvalid, self
  end

  def audit_create
    return unless self.class.audit_model

    self.audit_is_new = true
    self.audit_changes = changed_values

    record_audit("create", persisted_audit_attributes)
  end

  def audit_update
    return unless self.class.audit_model

    self.audit_is_new = false
    self.audit_changes = changed_values

    record_audit("update", audited_values)
  end

  def capture_audit_destroy_state
    return unless self.class.audit_model

    @audit_destroy_attributes = persisted_audit_attributes
    self.audit_is_new = false
    self.audit_changes = normalize_audit_hash(@audit_destroy_attributes.transform_values { |value| [value, nil] })
  end

  def audit_destroy
    return unless self.class.audit_model

    record_audit("delete", @audit_destroy_attributes || persisted_audit_attributes)
  end

  def record_audit(operation, data)
    payload = normalize_audit_hash(data.deep_dup)
    filter_audit_excluded!(payload)
    return if payload.empty?

    if operation == "update"
      payload[self.class.primary_key] = normalize_audit_value(self[self.class.primary_key])
    end

    ActionLog.record(
      audit_actor_id,
      "#{self.class.table_name.tr("_", "-")}-#{operation}",
      audit_reason,
      payload,
      audit_target_person_id
    )
  end

  # Who made the change: whoever the caller named, else whoever is signed in.
  # Person's on-site log names the same person as the audit row.
  def audit_actor_id = audit_user_id || Current.person_id

  def persisted_audit_attributes
    normalize_audit_hash(attributes.slice(*self.class.column_names))
  end

  def audit_source_changes
    if has_changes_to_save?
      changes_to_save
    elsif previous_changes.present?
      previous_changes
    else
      {}
    end
  end

  def audit_target_person_id
    return self[self.class.primary_key] if is_a?(Person)
    return self["person_id"] if has_attribute?("person_id")

    @audit_destroy_attributes&.dig("person_id")
  end

  def normalize_audit_hash(hash)
    hash.transform_values { |value| normalize_audit_value(value) }
  end

  def normalize_audit_value(value)
    case value
    when Time, Date, DateTime, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone
      value.to_s
    when Array
      value.map { |item| normalize_audit_value(item) }
    when Hash
      value.transform_values { |item| normalize_audit_value(item) }
    else
      value
    end
  end
end
