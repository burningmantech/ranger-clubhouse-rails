# frozen_string_literal: true

# The filters on Administration › SMS Management's log, which are what Twilio
# can filter its message list by: the number a text went to, the number it
# came from, and the UTC date it was sent. Plus where Twilio's paging stands.
class SmsFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"
  # Twilio's page tokens are letters, digits, dashes and underscores.
  PAGE_TOKEN = /\A[\w-]{1,200}\z/

  attribute :to, :string
  attribute :from, :string
  attribute :sent_after, :string
  attribute :sent_before, :string
  attribute :page, :integer, default: 0
  attribute :page_token, :string

  attr_reader :sent_after_date, :sent_before_date

  def initialize(attributes = {})
    super
    # A date that cannot be read narrows nothing, rather than drawing a chip
    # for a filter that is not applied.
    self.to = to.to_s.strip.presence
    self.from = from.to_s.strip.presence
    # The UTC date, as Twilio reads it, of whatever moment the value names.
    @sent_after_date = UiComponents::FilterBarHelper.filter_time(sent_after)&.utc&.to_date
    @sent_before_date = UiComponents::FilterBarHelper.filter_time(sent_before)&.utc&.to_date
    self.sent_after = sent_after_date&.iso8601
    self.sent_before = sent_before_date&.iso8601
    # A page past the first is reached only by the token Twilio handed back.
    self.page_token = nil unless PAGE_TOKEN.match?(page_token.to_s)
    self.page = page_token ? [page.to_i, 0].max : 0
  end

  # The filters actually narrowing the log: the chips, and what the export and
  # a page link carry along.
  def active_filters
    { to:, from:, sent_after:, sent_before: }.compact
  end

  # The same filters as TwilioMessageLog takes them, the dates read.
  def criteria
    { to:, from:, sent_after: sent_after_date, sent_before: sent_before_date }
  end

  # The filters, and a page of Twilio's when one is named by its token.
  def query_params(page: nil, page_token: nil)
    values = active_filters
    values = values.merge(page:, page_token:) if page_token
    { PARAM_SCOPE => values }
  end
end
