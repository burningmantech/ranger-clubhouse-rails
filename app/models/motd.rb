# frozen_string_literal: true

class Motd < ApplicationRecord
  self.table_name = "motd"

  # Who an announcement can be addressed to: the filter value each group is
  # known by, the column that records it, and what it is called on screen. One
  # entry per group, so adding a fourth means adding a row here rather than a
  # branch in every method that dispatches on it.
  AUDIENCES = {
    "rangers" => { column: :for_rangers, label: "Rangers" },
    "pnvs" => { column: :for_pnvs, label: "Prospectives & Alphas" },
    "auditors" => { column: :for_auditors, label: "Auditors" }
  }.freeze

  belongs_to :person
  has_many :person_motd, dependent: :delete_all

  validates :subject, presence: true
  validate :message_says_something
  validate :at_least_one_audience

  # Three checks, so each bad expiration gets the one message that fits it: an
  # empty box, something typed that is not a date, and a date already gone by.
  # "can't be blank" alone would be wrong for the last two -- an unreadable date
  # lands in the column as nil, the same as an empty one.
  validates :expires_at, presence: true, if: -> { expires_at_before_type_cast.blank? }
  validate :expires_at_is_readable
  validates_datetime :expires_at, after: -> { Current.time },
                     after_message: "The end date must be in the future.",
                     if: -> { expires_at.present? && expires_at_changed? }

  scope :active, -> { where(expires_at: Current.time..) }
  scope :expired, -> { where(expires_at: ...Current.time) }
  scope :for_auditors, -> { where(for_auditors: true) }
  scope :for_pnvs, -> { where(for_pnvs: true) }
  scope :for_rangers, -> { where(for_rangers: true) }

  def expired?
    expires_at.present? && expires_at < Current.time
  end

  def expires_at=(value)
    super(value.presence)
  end

  # The names of every group this announcement is addressed to.
  def audience_labels
    AUDIENCES.each_value.filter_map { |audience| audience[:label] if self[audience[:column]] }
  end

  class << self
    # Filters for the management page. Returns a relation so the caller can
    # count it, load it, or narrow it further.
    def find_for_query(params = {})
      query = for_audience(params[:audience])

      query = case params[:status]
              when "active" then query.active
              when "expired" then query.expired
              else query
              end

      # Announcements routinely share an expiration date, and MariaDB is free to
      # order ties however it likes. The id settles them so the list keeps the
      # same order between loads, and the anchor after a save lands where the
      # reader last saw the row.
      direction = params[:sort] == "asc" ? :asc : :desc
      query.includes(:person).order(expires_at: direction, id: direction)
    end

    # The scope for one audience key, or everything when the key names no
    # audience.
    def for_audience(key)
      audience = AUDIENCES[key]
      audience ? where(audience[:column] => true) : all
    end

    # Deletes everything past its expiration date and reports how many went.
    # destroy_all rather than delete_all so the person_motd read-tracking rows
    # go with each announcement.
    def expire!
      expired.destroy_all.size
    end

    def retrieve_announcements_for_person(person_id, status)
      audience = audience_for_status(status)
      # Checked against the known keys, not merely against nil: for_audience
      # falls back to every announcement, which is right for an unset filter and
      # would be a leak here.
      return [] unless AUDIENCES.key?(audience)

      rows = for_audience(audience)
           .select("motd.*, COALESCE(person_motd.read_at IS NOT NULL, FALSE) AS has_read")
           .joins(sanitize_sql_array(["left join person_motd ON motd.id = person_motd.motd_id AND person_motd.person_id=?", person_id]))
           .order(:created_at)
                  .load

      rows.sort_by { |row| row.has_read ? 1 : 0 }
    end

    private

    # Which audience a person falls into, as an AUDIENCES key.
    def audience_for_status(status)
      return nil if Person::NO_MESSAGES_STATUSES.include?(status)

      case status
      when Person::AUDITOR
        "auditors"
      when Person::PROSPECTIVE, Person::ALPHA
        "pnvs"
      else
        "rangers"
      end
    end
  end

  def has_read
    if has_attribute?(:has_read)
      read_attribute(:has_read) != 0
    else
      nil
    end
  end

  def has_read=(value)
    write_attribute(:has_read, value ? 1 : 0)
  end

  private

  # An announcement no one can see is never what the author meant.
  def at_least_one_audience
    return if audience_labels.any?

    errors.add(:base, "Choose at least one audience for this announcement.")
  end

  # An emptied rich-text editor still submits its block markup, so checking the
  # column for presence would let a blank announcement through. Strip the tags
  # and see whether any words are left. Entities are decoded first because a
  # typed space arrives as &nbsp;, which is neither blank nor a space until it
  # is.
  def message_says_something
    # Nokogiri drops the tags and decodes the entities in one pass, which
    # matters because a typed space arrives as &nbsp; -- neither blank nor a
    # space until it is decoded.
    text = Nokogiri::HTML5.fragment(message.to_s).text
    return if text.gsub(/[[:space:]]/, "").present?

    errors.add(:message, "The message can't be blank.")
  end

  # A date the column could not store reads back as nil, which is also what an
  # empty box gives. The raw value tells the two apart.
  def expires_at_is_readable
    return if expires_at.present? || expires_at_before_type_cast.blank?

    errors.add(:expires_at, "The end date is not a date we could read. Pick one from the calendar.")
  end
end
