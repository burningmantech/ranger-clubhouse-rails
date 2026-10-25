# frozen_string_literal: true

# The filters on Administration › Background Jobs: a state, a queue, part of
# a job class name, and the page. The same shape as ErrorLogFilterForm.
class JobFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"
  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  attribute :status, :string
  attribute :queue_name, :string
  attribute :class_name, :string
  attribute :page, :integer, default: 1

  def initialize(attributes = {})
    super
    # A state the page does not list -- a stale bookmark, a typo -- narrows
    # nothing rather than drawing a chip for a filter that is not applied.
    self.status = UiComponents::FilterBarHelper.known_filter(status, BackgroundJobs::STATES)
    self.queue_name = ALL if queue_name.blank?
    self.class_name = class_name.to_s.strip.presence
    # BackgroundJobs.page holds it to the last page that exists.
    self.page = [page.to_i, 1].max
  end

  def persisted?
    false
  end

  # The filters actually narrowing the list: the chips, what a page change
  # carries along, and what BackgroundJobs.page is asked for.
  def active_filters
    UiComponents::FilterBarHelper.active_filters(status:, queue_name:, class_name:)
  end

  def query_params(page:)
    values = active_filters
    values[:page] = page if page > 1
    { PARAM_SCOPE => values }
  end
end
