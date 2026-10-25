# frozen_string_literal: true

# One option in a bulk page's action select: what it is called, what a line of
# the pasted list has to look like, and which handler carries it out.
#
# Upstream keeps all of these in one ACTION_DESCRIPTIONS constant on the single
# admin/bulk-upload page. Here each page owns its own list, because the split
# put the gate on the page: an action reachable from a page is an action that
# page's role may perform, and a list assembled anywhere else would have to be
# re-checked against the gate on every request.
#
# `id` is the value the select posts and the handler dispatches on, and it keeps
# upstream's spelling ("bmidsubmitted", "alloc_wet_spot", "cert-12") so the
# action_log rows the two applications write stay searchable together.
class BulkUpload::Action
  attr_reader :id, :label, :help, :handler, :group

  # @param id [String] the posted value; upstream's spelling
  # @param label [String] what the select and the preview headline call it
  # @param help [String] the line format, shown under the textarea
  # @param handler [Class] a BulkUpload::Handler subclass
  # @param group [String, nil] optgroup heading, when the page groups its list
  def initialize(id:, label:, help:, handler:, group: nil)
    @id = id
    @label = label
    @help = help
    @handler = handler
    @group = group
    freeze
  end
end
