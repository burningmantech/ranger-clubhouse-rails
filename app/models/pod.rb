# frozen_string_literal: true

# A pod: a group of people who walk a shift together.
#
# Alpha pods come in linked TRIOS. Creating one writes three rows -- a mentor
# pod, an alpha pod, and a mitten pod -- with the alpha and mitten pods
# pointing back at the mentor pod through mentor_pod_id. There is no join
# table: upstream's App\Models\AlphaMentorPod is an empty stub with no backing
# table, and mentor_pod_id is the whole linkage. The Alpha Mentors Assignment
# page reads the trio the same way, so the type strings and the linkage column
# are a contract, not an implementation detail.
#
# The `shift` type belongs to the Cruise Direction interface and is untouched
# here; this model only grows the behaviour the Alpha Pod Management page needs.
#
# Upstream: app/Models/Pod.php and app/Http/Controllers/PodController.php. The
# controller owned the transactional bookkeeping there (renumbering, counts,
# disbanding); it lives here instead so no caller can write a half-formed trio.
class Pod < ApplicationRecord
  self.table_name = "pod"

  # `type` is a domain column (alpha/mentor/mitten/shift), not Rails STI.
  self.inheritance_column = nil

  self.audit_model = true

  # Matching upstream's $auditExclude. Ordering is not history: renumbering a
  # slot's pods would otherwise write an audit row per pod per arrow press,
  # and a sort-only update filters down to an empty payload, which
  # ApplicationRecord#record_audit drops entirely.
  self.audit_exclude = ["sort_index"].freeze

  TYPE_ALPHA = "alpha"
  TYPE_MENTOR = "mentor"
  TYPE_MITTEN = "mitten"
  TYPE_SHIFT = "shift"

  # The three types this page manages, in the order a pod card stacks them.
  ALPHA_SET_TYPES = [TYPE_MENTOR, TYPE_MITTEN, TYPE_ALPHA].freeze

  # How a shift pod gets around. Only Cruise Direction sets this; an Alpha pod
  # keeps the column default. The column is a MySQL enum, so an unlisted value
  # is a database error rather than a validation one -- hence the inclusion
  # check below, which upstream leaves to the browser's radio group.
  TRANSPORT_FOOT = "foot"
  TRANSPORT_BICYCLE = "bicycle"
  TRANSPORT_VEHICLE = "vehicle"
  TRANSPORTS = [TRANSPORT_FOOT, TRANSPORT_BICYCLE, TRANSPORT_VEHICLE].freeze

  # Pods move along the walk order; people move up and down inside a pod.
  # Upstream calls the pod directions left and right because its pods are
  # columns of one wide table -- in a card grid that reflows on a phone,
  # left means nothing and "earlier in the walk order" means what is meant.
  MOVE_EARLIER = "earlier"
  MOVE_LATER = "later"
  MOVE_DIRECTIONS = [MOVE_EARLIER, MOVE_LATER].freeze

  MOVE_UP = "up"
  MOVE_DOWN = "down"
  MEMBER_MOVE_DIRECTIONS = [MOVE_UP, MOVE_DOWN].freeze

  # Raised when a membership change cannot be honoured -- someone already in
  # the pod, or no longer in it. Controllers turn these into a toast rather
  # than a 500.
  class MembershipError < StandardError; end

  belongs_to :slot, optional: true
  belongs_to :mentor_pod, class_name: "Pod", optional: true

  # Hard delete, matching upstream's destroy: a deleted pod keeps no roster.
  # :destroy rather than :delete_all so each membership still lands in the
  # audit trail -- a pod holds a dozen people, not a million.
  has_many :person_pod, dependent: :destroy
  has_many :sub_pods, class_name: "Pod", foreign_key: :mentor_pod_id, dependent: nil, inverse_of: :mentor_pod

  scope :for_slot, ->(slot) { where(slot_id: slot) }
  scope :of_type, ->(type) { where(type:) }
  scope :ordered, -> { order(:sort_index, :id) }

  # Both messages are whole sentences naming their own subject: `errors.format`
  # is "%{message}", so nothing prepends the attribute, and these reach the
  # reader as a toast built from `full_messages`.
  validates :transport, inclusion: { in: TRANSPORTS, message: "A pod must be on foot, bike mobile, or in a vehicle." }

  # The same 34 the form's maxlength enforces. Client-side alone is not enough:
  # the column is a varchar(255), and under strict SQL mode a longer posted
  # location raises ValueTooLong, which is a 500 rather than the intended toast.
  #
  # Only when the location is actually being written. This table is shared with
  # the still-live Laravel page, which has no length rule, so longer locations
  # already exist -- and almost nothing that saves a pod is editing its
  # location. `refresh_person_count!`, `renumber!` and `renumber_line!` all
  # `update!` pods the operator never touched, and `Pod.shift_ended` reaches
  # `refresh_person_count!` from a Timesheet after_save, so validating a
  # legacy row on every save would make one long location block that person's
  # sign-out everywhere in the app.
  validates :location, length: { maximum: 34, message: "A pod location cannot be longer than 34 characters." },
                       allow_nil: true, if: :location_changed?

  # Upstream's NullIfEmptyAttribute: a location typed and then cleared reads as
  # no location rather than an empty one, so the card shows its placeholder.
  normalizes :location, with: ->(location) { location.strip.presence }

  before_create -> { self.formed_at ||= Current.time }

  def mentor? = type == TYPE_MENTOR
  def alpha? = type == TYPE_ALPHA
  def mitten? = type == TYPE_MITTEN
  def shift? = type == TYPE_SHIFT
  def disbanded? = disbanded_at.present?

  # What this pod is called out loud. A pod that stands on its own -- a mentor
  # pod, or a Cruise Direction shift pod -- is its own sort_index. An alpha or
  # mitten pod defers to the mentor pod it hangs off, because its own
  # sort_index is always 1 and would name a different pod. nil only while a
  # trio is malformed.
  #
  # Keyed on the type rather than on mentor_pod_id: an orphaned alpha or mitten
  # pod -- which `pod` being a Laravel-shared table makes reachable -- has no
  # mentor pod to defer to, and answering with its own sort_index would name
  # the real Pod 1 sitting beside it on the same slot.
  def number = shift? || mentor? ? sort_index : mentor_pod&.sort_index

  # The rows for people currently in the pod. `left_at` is deliberately NOT
  # filtered: someone whose shift ended is still nominally in the pod until a
  # mentor removes them, which is upstream's rule and the reason a pod does
  # not empty itself when the walk finishes.
  def current_members = person_pod.current

  class << self
    # The slot's mentor pods in display order. Every "Pod #N" label in the UI
    # is one of these sort_index values; the alpha and mitten pods stay pinned
    # at 1 and follow their mentor pod.
    def mentor_pods_for(slot) = for_slot(slot).of_type(TYPE_MENTOR).ordered

    # The slot's Cruise Direction pods in deployment order. Shift pods stand
    # alone -- no trio, no mentor_pod_id -- so the line is simply every shift
    # pod on the slot.
    def shift_pods_for(slot) = for_slot(slot).of_type(TYPE_SHIFT).ordered

    # Create one Cruise Direction pod on the end of the slot's line.
    def create_shift_pod!(slot, attributes = {})
      create!(**attributes,
              slot_id: slot.id,
              type: TYPE_SHIFT,
              sort_index: (shift_pods_for(slot).maximum(:sort_index) || 0) + 1)
    end

    # Create a linked mentor/mitten/alpha trio for an Alpha shift.
    #
    # The new mentor pod goes on the end. Upstream takes the max sort_index
    # over every pod in the slot, which only lands on the right number because
    # the sub-pods are pinned at 1; taking it over the mentor pods alone says
    # what is actually meant and gives the same answer.
    #
    # @return [Pod] the mentor pod of the new trio
    def create_alpha_set!(slot)
      transaction do
        mentor = create!(slot_id: slot.id, type: TYPE_MENTOR,
                         sort_index: (mentor_pods_for(slot).maximum(:sort_index) || 0) + 1)
        create!(slot_id: slot.id, type: TYPE_ALPHA, sort_index: 1, mentor_pod_id: mentor.id)
        create!(slot_id: slot.id, type: TYPE_MITTEN, sort_index: 1, mentor_pod_id: mentor.id)
        mentor
      end
    end

    # Stamp the moment a member's shift ended.
    #
    # Called by Timesheet#handle_shift_end when an entry's off_duty is first
    # set. The hook was already in place waiting for this model to exist, so
    # defining Pod is what switches it on. Only person_count is refreshed --
    # left_at does not reduce the current membership, so a pod never disbands
    # itself just because everyone signed out.
    def shift_ended(person_id, timesheet_id)
      membership = PersonPod.current.find_by(person_id:, timesheet_id:, left_at: nil)
      return unless membership

      # The pod is looked up rather than walked to through the association,
      # and a missing one bails. This runs inside the sign-out's own
      # transaction, and person_pod has no foreign key -- a membership orphaned
      # by the Laravel side would otherwise fail `belongs_to :pod`'s presence
      # check and take an unrelated Ranger's sign-out down with it.
      pod = find_by(id: membership.pod_id)
      return unless pod

      membership.update!(left_at: Current.time)
      pod.refresh_person_count!
    end

    # Close the gaps in one slot-and-type line's numbering after a pod is
    # deleted or dropped somewhere else in the line.
    def renumber_line!(slot_id, type)
      for_slot(slot_id).of_type(type).ordered.each_with_index do |pod, index|
        pod.update!(sort_index: index + 1) unless pod.sort_index == index + 1
      end
    end

    # Close the gaps in a slot's pod numbering after one is deleted.
    def renumber_mentor_pods!(slot_id) = renumber_line!(slot_id, TYPE_MENTOR)
  end

  # Delete this trio: the mentor pod, its alpha and mitten pods, and every
  # membership row. The survivors close ranks so pod numbers stay 1..N.
  def destroy_set!
    transaction do
      sub_pods.each(&:destroy!)
      destroy!
      self.class.renumber_mentor_pods!(slot_id)
    end
  end

  # Step this mentor pod one place left or right in the slot's walk order.
  #
  # The whole line is renumbered rather than two values swapped -- the same
  # shape as BmidTitle#move!, and equal or gapped numbers are legal here.
  # Upstream renumbers client-side and loses `this` partway through, leaving
  # the browser's copy out of step with the database; one transaction cannot.
  #
  # @param direction [String] MOVE_EARLIER or MOVE_LATER
  # @return [Boolean] false when the pod is already at that end
  def move!(direction)
    line = self.class.mentor_pods_for(slot_id).to_a
    from = line.index { |pod| pod.id == id }
    return false unless from

    to = direction == MOVE_EARLIER ? from - 1 : from + 1
    return false if to.negative? || to >= line.size

    line.insert(to, line.delete_at(from))
    transaction { renumber!(line) }
    true
  end

  # Drop this pod at `position` in its own slot-and-type line and close the
  # numbering around it. This is what a drag ends in: SortableJS reports where
  # the card was let go, 1-based, and the line is rewritten to match.
  #
  # Out-of-range positions are clamped rather than refused -- a card dragged
  # past either end of the grid means that end, and there is no failure to
  # report to someone who is watching the card land.
  #
  # @param position [Integer] 1-based place in the line
  # @return [Boolean] false when the pod did not move
  def move_to!(position)
    # A place in the line or nothing. `to_i` would read nil and "junk" alike as
    # 0, which clamps to the front -- so a request that lost its position, or
    # never had one, would silently renumber the line and report success.
    target = Integer(position, exception: false)
    return false unless target

    line = self.class.for_slot(slot_id).of_type(type).ordered.to_a
    from = line.index { |pod| pod.id == id }
    return false unless from

    to = target.clamp(1, line.size) - 1
    return false if to == from

    line.insert(to, line.delete_at(from))
    transaction { renumber!(line) }
    true
  end

  # Delete this pod and its memberships, then close the gap it leaves so the
  # survivors stay numbered 1..N. The trio equivalent is destroy_set!.
  def destroy_and_renumber!
    transaction do
      destroy!
      self.class.renumber_line!(slot_id, type)
    end
  end

  # Add someone to this pod.
  #
  # is_lead only means anything on a mentor pod, so it is dropped elsewhere
  # rather than stored and ignored -- upstream stores it on mitten pods, where
  # a stale checkbox from the previously opened dialog could set it.
  #
  # @raise [MembershipError] when they are already in a pod of this type
  def add_person!(person, is_lead: false)
    guard_not_already_podded!(person)

    transaction do
      person_pod.create!(
        person_id: person.id,
        is_lead: mentor? && is_lead,
        # Whichever shift they are signed in to right now, so the timesheet
        # hook can tell later that this membership's shift is the one ending.
        # Looked up in the pod's own year: Pod.shift_ended keys on this id, and
        # a current-year entry stamped onto a past year's pod would let today's
        # sign-out mark someone as having left a pod from another event.
        timesheet_id: Timesheet.find_person_on_duty(person.id, slot&.begins_year || Current.year)&.id,
        # Alphas walk in order, so a new one joins the back of the line.
        # Everyone else is a flat group and upstream inserts at 1.
        sort_index: alpha? ? current_members.count + 1 : 1
      )
      refresh_person_count!
    end
  end

  # Remove someone from this pod. The row is kept with removed_at stamped, so
  # who was in which pod stays answerable after the event.
  #
  # @raise [MembershipError] when they are not in the pod
  def remove_person!(person)
    transaction do
      membership = current_members.find_by(person_id: person.id)
      raise MembershipError, "#{person.callsign} is not in this pod." unless membership

      membership.update!(removed_at: Current.time)
      # Only an alpha pod's members carry an order of their own -- they walk in
      # it. Everyone else is written at sort_index 1 (see add_person!) so that
      # PersonPod.ordered falls through to callsign. Renumbering those
      # survivors 1..N would pin them in the order they happened to be removed
      # around, and the next person added -- back at 1 -- would sort above all
      # of them instead of into place.
      renumber_members! if alpha?
      refresh_person_count!
    end
  end

  # Move someone from this pod into another pod of the same type. Upstream
  # sends a delete and an add from the browser, so an interrupted relocation
  # can drop a person entirely; here it is one transaction.
  def relocate_person!(person, new_pod, is_lead: false)
    transaction do
      remove_person!(person)
      new_pod.add_person!(person, is_lead:)
    end
  end

  # Step a member one place up or down inside this pod.
  #
  # @return [Boolean] false when they are already at that end
  def move_person!(person, direction)
    line = current_members.ordered.to_a
    from = line.index { |membership| membership.person_id == person.id }
    return false unless from

    to = direction == MOVE_UP ? from - 1 : from + 1
    return false if to.negative? || to >= line.size

    line.insert(to, line.delete_at(from))
    transaction { renumber!(line) }
    true
  end

  # Keep the denormalised counter honest, and disband or reform the pod with
  # it. Upstream keeps person_count on the row and every header reads it.
  def refresh_person_count!
    count = current_members.count

    update!(
      person_count: count,
      # Already-disbanded pods keep their original timestamp rather than
      # having it bumped by an unrelated recount.
      disbanded_at: count.zero? ? (disbanded_at || Current.time) : nil
    )
  end

  private

  def guard_not_already_podded!(person)
    existing = self.class.for_slot(slot_id).of_type(type)
                   .joins(:person_pod)
                   .where(person_pod: { person_id: person.id, removed_at: nil })
                   .first
    return unless existing

    # Upstream only rejects a second membership in the SAME pod and leaves
    # cross-pod duplicates to a disabled checkbox, which the "not checked in"
    # list never gets. Someone in two pods of one walk is always a mistake.
    label = existing.number ? "Pod #{existing.number}" : "another pod"
    raise MembershipError, "#{person.callsign} is already in #{label} for this shift."
  end

  def renumber_members!
    renumber!(current_members.ordered.to_a)
  end

  # Write 1..N onto an ordered line, touching only the rows whose number
  # actually changed.
  def renumber!(line)
    line.each_with_index do |row, index|
      row.update!(sort_index: index + 1) unless row.sort_index == index + 1
    end
  end
end
