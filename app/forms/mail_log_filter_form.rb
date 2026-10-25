# frozen_string_literal: true

class MailLogFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  # Far past any real page. The page number is multiplied into a SQL OFFSET,
  # and an unbounded one overflows the database's limit rather than simply
  # coming back empty.
  MAX_PAGE = 100_000

  attribute :person_callsign, :string
  attribute :email, :string
  attribute :subject, :string
  attribute :page, :integer, default: 1

  def initialize(attributes = {})
    super
    self.page = page.to_i.clamp(1, MAX_PAGE)
  end

  # Only the filters actually being applied, so pager links and chips carry
  # the search forward without collecting empty values.
  def query_params(to_page: nil)
    values = {
      person_callsign: person_callsign.presence,
      email: email.presence,
      subject: subject.presence
    }.compact
    values[:page] = to_page if to_page.present? && to_page.to_i > 1
    return {} if values.empty?

    { PARAM_SCOPE => values }
  end
end
