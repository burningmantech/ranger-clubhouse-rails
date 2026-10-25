# frozen_string_literal: true

# Recording one certification for a list of callsigns at once.
#
# The Certification Actions group of upstream's admin/bulk-upload, and the page
# a class roster is entered on: one line per person, the card number and dates
# each of them came away with.
#
# The only page whose action list is not a constant. Upstream builds this group
# from the certification table on every request and so does this, because a
# certification is a record an administrator creates -- a frozen list here would
# mean a deploy before the newest one could be recorded.
class Certificates::BulkRecordController < ApplicationController
  include BulkUploadPage

  layout "certificates"

  authorize_role [Role::ADMIN],
                 message: "Admin role required to record certifications in bulk."

  # Upstream's line format, said in sentences rather than in its five lines: the
  # help text renders as one block, so its newlines would run together anyway.
  #
  # Upstream's second example reads "2022-01-4", which teaches a shape the
  # sentence before it has just ruled out. Written out here -- Date parsing
  # accepts either, but an example is what gets copied.
  RECORDS_HELP = "One line per person: callsign,issued on date,card number,trained on date. " \
                 "Date format is YYYY-MM-DD. Every field after the callsign is optional and may " \
                 "be left blank. Examples: hubcap,,12345 records the card number; " \
                 "hubcap,2022-01-04,,2021-12-20 records the issued on and trained on dates."

  bulk_upload_page title: "Bulk Record Certifications",
                   icon: "certificate",
                   description: "Record or update one certification for a list of callsigns.",
                   action_label: "Certification",
                   action_prompt: "Choose a certification",
                   records_label: "Certification records",
                   records_help: RECORDS_HELP

  private

  # Memoized because it is not a constant: the form, the preview and the apply
  # each ask for this list, and without the ivar every render would go back to
  # the database three or four times for the same rows.
  def bulk_actions
    @bulk_actions ||= Certification.order(:title).map do |certification|
      BulkUpload::Action.new(id: "#{BulkUpload::CertificationHandler::ID_PREFIX}#{certification.id}",
                             label: "Record/Update #{certification.title} cert.",
                             help: RECORDS_HELP,
                             handler: BulkUpload::CertificationHandler)
    end
  end
end
