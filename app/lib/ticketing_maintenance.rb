# frozen_string_literal: true

# The one-shot ticketing maintenance tasks behind /ticketing/maintenance,
# ported from the Ember vc/access-documents/maintenance page and the Laravel
# maintenance actions on AccessDocumentController and ProvisionController
# (app/Lib/GrantPasses.php, app/Lib/ProvisionMaintenance.php).
#
# Tasks are grouped by when in the year they run. The controller looks a task
# up by slug, renders execute(commit: false) as a full-page preview, and
# re-runs it with commit: true from the POST on that preview page.
module TicketingMaintenance
  # One ledger row, shared by every task's preview and results. person may be
  # nil for orphaned records; ref is nil for a grant that has not happened yet.
  Row = Data.define(:person, :ref, :type_label, :change, :detail, :email, :error)

  # An index card that links to its own page instead of running a task here.
  LinkCard = Data.define(:title, :description, :path_helper) do
    def link? = true
  end

  UNSUBMIT_LINK = LinkCard.new(
    title: "Un-Submit Provisions",
    description: "Review people who claimed or submitted earned provisions but did not ranger, " \
                 "and return their provisions to available.",
    path_helper: :ticketing_unsubmit_provisions_path
  )

  GROUPS = [
    { title: "Before Ticketing Opens",
      blurb: "Run these before the ticketing window opens for the year.",
      entries: [UnbankTickets, UnbankProvisions, GrantSaps, GrantVps, SetScAccessDates] },
    { title: "Before the Event",
      blurb: "Run this once Alphas are signed up for training.",
      entries: [GrantAlphaSaps] },
    { title: "After the Event",
      blurb: "Run these in order once the event has wrapped up.",
      ordered: true,
      entries: [CleanTickets, BankTickets, ExpireTickets, UNSUBMIT_LINK,
                CleanProvisions, BankProvisions, ExpireProvisions] },
    { title: "Anytime",
      blurb: "Run when needed.",
      entries: [BumpExpiration] }
  ].freeze

  TASKS = GROUPS.flat_map { |group| group[:entries] }.reject(&:link?).freeze

  # @return [Class, nil] the task registered under the slug
  def self.find(slug) = TASKS.find { |task| task.slug == slug }

  # The event year maintenance is cleaning up after: last year's event until
  # August, when the current one is imminent. Port of the Laravel
  # maintenance_year() helper.
  def self.maintenance_year
    today = Date.current
    today.month < 8 ? today.year - 1 : today.year
  end
end
