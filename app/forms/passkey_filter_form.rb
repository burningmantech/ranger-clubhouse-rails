# frozen_string_literal: true

# The one filter on the Admin's list of every passkey, and the page of it.
class PasskeyFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  # The only value the filter takes. Anything else means everyone's passkeys.
  ADMIN = "admin"
  ADDED_BY_OPTIONS = [["Anyone", ""], ["An Admin", ADMIN]].freeze

  # Far past any real page: see MailLogFilterForm.
  MAX_PAGE = 100_000

  attribute :added_by, :string
  attribute :page, :integer, default: 1

  def initialize(attributes = {})
    super
    self.page = page.to_i.clamp(1, MAX_PAGE)
  end

  def added_by_admin?
    added_by == ADMIN
  end

  # Only the filter actually being applied, so pager links and the chip carry
  # it forward without collecting empty values.
  def query_params(to_page: nil)
    values = { added_by: (ADMIN if added_by_admin?) }.compact
    values[:page] = to_page if to_page.present? && to_page.to_i > 1
    return {} if values.empty?

    { PARAM_SCOPE => values }
  end
end
