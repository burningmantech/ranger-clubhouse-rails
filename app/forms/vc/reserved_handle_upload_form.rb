# frozen_string_literal: true

# Holds the bulk upload page's submitted values. The verify -> commit flow is
# stateless: the results panel re-submits these same values with commit set,
# so the form must round trip through params unchanged.
class Vc::ReservedHandleUploadForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :handles, :string, default: ""
  attribute :reservation_type, :string, default: HandleReservation::RESERVATION_TYPE_UNCATEGORIZED
  attribute :expires_on, :string, default: ""
  attribute :reason, :string, default: ""
  attribute :twii_year, :integer
  attribute :commit, :boolean, default: false

  validates :handles, presence: { message: "List at least one handle." }
  validates :reservation_type, inclusion: { in: HandleReservation::RESERVATION_TYPES }
  validates :twii_year, presence: true, if: :twii_person?
  validate :expires_on_must_be_a_valid_date

  # Keeps the param scope and field ids short: params[:upload], #upload_handles.
  def self.model_name
    ActiveModel::Name.new(self, nil, "Upload")
  end

  def persisted? = false

  def twii_person?
    reservation_type == HandleReservation::RESERVATION_TYPE_TWII_PERSON
  end

  private

  def expires_on_must_be_a_valid_date
    return if expires_on.blank?

    Date.parse(expires_on)
  rescue ArgumentError
    errors.add(:expires_on, "The expiration date is not a valid date.")
  end
end
