# frozen_string_literal: true

# Clicks on outbound links, once recorded from the MVR page. Nothing here
# writes or reads them any more; the model stays for the table it maps.
class OutboundLink < ApplicationRecord
  belongs_to :person, optional: true
end
