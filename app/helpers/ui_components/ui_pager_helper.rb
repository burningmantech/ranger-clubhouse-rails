# frozen_string_literal: true

module UiComponents
  # Pager Helper
  # Where a page of a paged list sits in the whole set -- "Page 2 of 7 ·
  # 640 messages" -- beside Previous Page and Next Page. A button with no page
  # to go to stays on screen, disabled, so the pair never moves.
  #
  # Usage:
  #   <% pager = ui_pager(@pagy, noun: "request") { |page| admin_request_logs_path(@form.query_params(page:)) } %>
  #
  module UiPagerHelper
    PAGER_CLASSES = "flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between"

    # @param meta [Pagy, Hash] The list's Pagy object, offset or countless, or
    #   its numbers as { page:, total_pages:, total: }. A meta that also
    #   carries has_previous_page / has_next_page is taken at its word: a log
    #   whose total is estimated cannot tell from page arithmetic whether
    #   another page exists.
    # @param noun [String] What the list holds, singular: "message" reads
    #   "640 messages". Only a counted list has a total to put it beside
    # @param summary [String] Replaces the whole "Page 2 of 7 · 640 messages"
    #   line, for a page that words it differently -- an estimated total, or
    #   one never counted, as a countless Pagy's is
    # @param options [Hash] Additional HTML options
    #   - :class - Additional CSS classes
    # @yieldparam page [Integer] The page a button leads to
    # @yieldreturn [String] That page's URL, its filters carried along
    def ui_pager(meta, noun: nil, summary: nil, **options)
      meta = ui_pager_meta(meta) if meta.is_a?(Pagy)
      raise ArgumentError, "ui_pager needs summary:, or noun: for a counted list" unless summary || (noun && meta[:total])

      page = meta[:page]
      summary ||= "Page #{page} of #{[meta[:total_pages], 1].max} · #{pluralize(meta[:total], noun)}"
      previous_url = yield(page - 1) if meta.fetch(:has_previous_page) { page > 1 }
      next_url = yield(page + 1) if meta.fetch(:has_next_page) { page < meta[:total_pages] }
      buttons = safe_join([ui_pager_button("Previous Page", previous_url), ui_pager_button("Next Page", next_url)])
      options[:class] = class_names(PAGER_CLASSES, options[:class])

      tag.div(**options) do
        safe_join([tag.p(summary, class: "text-base text-body"), tag.div(buttons, class: "flex flex-wrap gap-2")])
      end
    end

    private

    # A Pagy object's numbers. Pagy knows whether a page lies either side: a
    # countless one fetched a row past the page to find out, and has no total.
    def ui_pager_meta(pagy)
      { page: pagy.page, total_pages: pagy.last, total: pagy.count,
        has_previous_page: pagy.previous.present?, has_next_page: pagy.next.present? }
    end

    def ui_pager_button(label, url)
      return button_action(label, :secondary, disabled: true) unless url

      button_link(label, :secondary, url)
    end
  end
end
