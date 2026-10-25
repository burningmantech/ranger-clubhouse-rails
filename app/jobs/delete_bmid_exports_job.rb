# frozen_string_literal: true

# Deletes the badge export archives once the event is over. The archives exist
# so a batch can be looked up or reprinted during the event; afterwards they are
# only a copy of everyone's badge details sitting in storage.
class DeleteBmidExportsJob < ApplicationJob
  def perform
    count = BmidExport.delete_all_for_post_event
    Rails.logger.info("Post-event cleanup removed #{count} badge #{'export'.pluralize(count)}")
  end
end
