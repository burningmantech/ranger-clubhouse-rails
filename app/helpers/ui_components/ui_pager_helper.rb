# frozen_string_literal: true

module UiComponents
  # Pager Helper
  # Where a page of a paged list sits in the whole set -- "Page 2 of 7 ·
  # 640 messages" -- beside Previous Page and Next Page. A button with no page
  # to go to stays on screen, disabled, so the pair never moves.
  #
  # Usage:
  #   <% pager = ui_pager(@meta, noun: "message") { |page| admin_mail_log_path(@form.query_params(to_page: page)) } %>
  #
  module UiPagerHelper
    PAGER_CLASSES = "flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between"

    # @param meta [Hash] { page:, total_pages:, total: }, as the paged model
    #   queries return it. A meta that also carries has_previous_page /
    #   has_next_page is taken at its word: a log whose total is estimated
    #   cannot tell from page arithmetic whether another page exists.
    # @param noun [String] What the list holds, singular: "message" reads
    #   "640 messages"
    # @param summary [String] Replaces the whole "Page 2 of 7 · 640 messages"
    #   line, for a page that words it differently -- an estimated total, or
    #   one never counted
    # @param options [Hash] Additional HTML options
    #   - :class - Additional CSS classes
    # @yieldparam page [Integer] The page a button leads to
    # @yieldreturn [String] That page's URL, its filters carried along
    def ui_pager(meta, noun: nil, summary: nil, **options)
      raise ArgumentError, "ui_pager needs noun: or summary:" unless noun || summary

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

    def ui_pager_button(label, url)
      return button_action(label, :secondary, disabled: true) unless url

      button_link(label, :secondary, url)
    end
  end
end
