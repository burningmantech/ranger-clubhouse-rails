# frozen_string_literal: true

# The four steps every bulk page runs, and the copy that tells them apart.
#
# Upstream is one page with a select of every action in the application; the
# split made it eight, each gated by the role that may perform its actions. The
# steps did not change, so they live here once rather than eight times:
#
#   GET  /          the form                                        (200)
#   POST preview    what would happen; writes nothing               (422)
#   POST /          rebuilds from its own params, writes, reports   (422)
#   POST edit       back to the form with the pasted list intact    (422)
#
# Every POST answers 422 because Turbo silently drops a 200 response to a form
# submission. The apply renders rather than redirects for the reason `refuse`
# does: a redirect drops the pasted list, and re-typing it is the whole cost of
# getting one of these pages wrong.
#
# A page supplies its copy through `bulk_upload_page`, its actions through
# `bulk_actions`, and -- if it needs one -- extra form state through
# `batch_context` and a `_extra_fields` partial. The two existing bulk pages
# (Bulk Teams, Bulk Positions) deliberately duplicate each other and are left
# alone; that ruling was made when there were two of them.
module BulkUploadPage
  extend ActiveSupport::Concern

  included do
    class_attribute :bulk_page_config, default: {}.freeze

    helper_method :bulk_page_config, :bulk_actions, :bulk_path
  end

  class_methods do
    # @param title [String] page heading
    # @param icon [String] FontAwesome name for the hero panel
    # @param description [String] the sentence under the heading
    # @param action_label [String] label on the action select
    # @param action_prompt [String] its blank-choice text
    # @param records_label [String] label on the textarea
    # @param records_help [String] the line format, for pages where every action
    #   shares one. Pages whose actions differ ship a `_formats` partial instead.
    # @param year_scoped [Boolean] true when the writes land in one event year,
    #   which the page then states out loud rather than leaving to be discovered
    # @param extra_params [Array<Symbol>] page params the preview must re-post so
    #   the apply can rebuild itself from its own request
    def bulk_upload_page(**config)
      self.bulk_page_config = { action_label: "Action",
                                action_prompt: "Choose an action",
                                records_label: "Callsigns",
                                extra_params: [] }.merge(config).freeze
    end
  end

  # Also the target of the "edit" POST, which re-renders the form with whatever
  # params arrived so a correction after a preview keeps the pasted list. A GET
  # could only manage that by putting every callsign in the URL.
  def index
    render_bulk_page(:index, status: request.post? ? :unprocessable_entity : :ok)
  end

  # Step one: show exactly what would happen, and write nothing.
  def preview
    @batch = build_batch
    return unless @batch

    render_bulk_page(:preview, status: :unprocessable_entity)
  end

  # Step two: rebuild from this request's own params and re-run every check,
  # then write. Nothing the preview computed is trusted here -- it described the
  # change, it did not authorize it.
  def apply
    @batch = build_batch
    return unless @batch

    @outcome = @batch.apply!
    render_bulk_page(:index, status: :unprocessable_entity)
  end

  private

  # The actions this page offers, in select order. Pages override.
  #
  # @return [Array<BulkUpload::Action>]
  def bulk_actions = raise(NotImplementedError, "#{self.class}#bulk_actions")

  # Page state the handler needs beyond the pasted list -- the chosen team, on
  # the one page that has one. Set by a before_action that has already refused
  # anything unreachable.
  def batch_context = {}

  # Returns the batch, or nil having already re-rendered the form.
  #
  # `bulk_action` rather than `action`: Rails owns params[:action], and a form
  # field of that name arrives as the controller's own action name.
  def build_batch
    action = bulk_actions.find { |candidate| candidate.id == params[:bulk_action].to_s }
    return refuse("Choose an action from the list.") unless action

    batch = BulkUpload::Batch.new(action:, records: params[:records],
                                  reason: params[:reason], context: batch_context)
    return refuse("Enter at least one callsign, one per line.") if batch.entries.empty?

    batch
  end

  # Re-renders rather than redirects, so the pasted list survives the refusal.
  def refuse(message)
    flash.now[:error] = message
    render_bulk_page(:index, status: :unprocessable_entity)
    nil
  end

  # The shared templates, rendered from whichever page's controller. Every page
  # would otherwise carry two identical files whose only content is a render.
  def render_bulk_page(name, status:)
    render template: "common/bulk_upload/#{name}", status:
  end

  # The page's own route helpers, by convention rather than configuration: the
  # four routes of a page at `namespace/page` are named `namespace_page`,
  # `namespace_preview_page`, `namespace_apply_page` and `namespace_edit_page`,
  # which is the shape the two existing bulk pages already use.
  def bulk_path(step = nil)
    namespace, page = controller_path.split("/")
    public_send([namespace, step, page].compact.join("_") + "_path")
  end
end
