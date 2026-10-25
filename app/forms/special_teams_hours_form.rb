# frozen_string_literal: true

# What a Special Teams Hours report is asked for: the positions, the span of
# years, and the two things the table can add.
class SpecialTeamsHoursForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "report"

  # The chosen positions ride outside the scope, one ids[] parameter each. The
  # whole request is in the address, and a position costs 14 bytes of it this
  # way against 35 as report[position_ids][] -- so choosing every position
  # stays far inside the 8 KB request line nginx accepts by default.
  IDS_PARAM = "ids"

  attribute :start_year, :integer
  attribute :end_year, :integer
  # Also list people who hold a chosen position but have no hours on it.
  attribute :include_holders, :boolean, default: false
  # Also count each person's sign-ups, and list people who only signed up.
  attribute :show_signups, :boolean, default: false
  attribute :position_ids, IdList::Type.new, default: -> { [] }

  validate :positions_chosen

  # Only ids still naming a position: a bookmark can outlive one, and a report
  # run over ids that match nothing would say no one was found instead of
  # asking for a position.
  def position_ids=(values)
    ids = IdList.parse(values)
    super(ids.empty? ? [] : Position.where(id: ids).pluck(:id))
  end

  # The span as years the menus offer. The selects show this rather than what
  # was sent, so they always agree with the report the page is showing.
  def span = EventYearSpan.span(start_year, end_year)

  # Everything needed to rebuild this page, for the export link.
  def query_params
    from, to = span

    { PARAM_SCOPE => {
      start_year: from,
      end_year: to,
      include_holders: ("1" if include_holders),
      show_signups: ("1" if show_signups)
    }.compact, IDS_PARAM => position_ids.presence }.compact
  end

  private

  # Named in full: the error summary prints the message alone.
  def positions_chosen
    return if position_ids.any?

    errors.add(:position_ids, "Choose at least one position to report on.")
  end
end
