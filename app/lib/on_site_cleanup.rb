# frozen_string_literal: true

# Marks people off site once nothing ties them to the site: they are off duty,
# hold none of this year's assets, and have no shift left this year. The page at
# /people/on-site previews it and runs it; OnSiteCleanupJob runs it the three
# nights after Labor Day.
#
# The mark is dated at the person's last sign-out or asset return, not at the
# moment of the run: the site log should say when they left, not when someone
# got round to the housekeeping. Activity from before they were marked on site
# is no evidence of leaving, and an off-site mark dated before the on-site mark
# it closes would turn the history upside down -- PersonOnSite reads it by
# date -- so with nothing later to go by the mark is dated when the run happens.
class OnSiteCleanup
  AUDIT_REASON = "on-site cleanup"

  # Why someone stays on site, in the order the page lists them.
  ON_DUTY = :on_duty
  ASSET_OUT = :asset_out
  UPCOMING_SHIFT = :upcoming_shift

  BLOCKER_LABELS = {
    ON_DUTY => "On duty",
    ASSET_OUT => "Asset checked out",
    UPCOMING_SHIFT => "Shift still to come"
  }.freeze

  # left_at: the time the off-site mark will carry. nil for someone staying,
  # and for someone leaving with no activity to date the mark from: theirs is
  # dated when the run happens.
  Row = Data.define(:person, :left_at, :blockers)

  def initialize(now: Current.time, year: Current.year)
    @now = now
    @year = year
  end

  # Both by callsign.
  def leaving = rows.select { it.blockers.empty? }

  def staying = rows.reject { it.blockers.empty? }

  # Marks everyone in #leaving off site, each through Person's own save so the
  # site log and the audit log are written the way a mark at the window is.
  # A raise stops the run where it is; the next run picks up the rest.
  #
  # @return [Integer] how many people were marked
  def run!
    marked = leaving.each do |row|
      person = row.person
      person.on_site = false
      person.on_site_reason = PersonOnSite::AUTOMATIC
      person.on_site_changed_at = row.left_at
      person.audit_reason = AUDIT_REASON
      person.save!(validate: false)
    end
    @rows = nil
    marked.size
  end

  private

  def rows
    @rows ||= begin
      people = Person.where(on_site: true).order(:callsign).to_a
      ids = people.map(&:id)
      blockers = blockers_for(ids)
      left_at = left_at_for(ids - blockers.keys)
      people.map { Row.new(person: it, left_at: left_at[it.id], blockers: blockers.fetch(it.id, [])) }
    end
  end

  # {person_id => [blocker, ...]}, only for the people something holds here.
  def blockers_for(ids)
    {
      ON_DUTY => Timesheet.on_duty_now.where(person_id: ids),
      ASSET_OUT => PersonAsset.where(person_id: ids, checked_in: nil).where_year("checked_out", @year),
      # A shift still running counts: someone working it without having signed
      # in is not gone. Slot times are compared as stored, as the schedule does.
      UPCOMING_SHIFT => PersonSlot.joins(:slot).merge(Slot.for_year(@year)).where(person_id: ids)
                                  .where("slot.ends > ?", @now)
    }.each_with_object({}) do |(blocker, held), found|
      held.distinct.pluck(:person_id).each { (found[it] ||= []) << blocker }
    end
  end

  # {person_id => time}: this year's last sign-out or asset return when it came
  # after the person's newest on-site mark, else nil.
  def left_at_for(ids)
    signed_out = Timesheet.for_year(@year).where(person_id: ids).group(:person_id).maximum(:off_duty)
    returned = PersonAsset.where(person_id: ids).where_year("checked_out", @year)
                          .group(:person_id).maximum(:checked_in)
    marked = PersonOnSite.where(person_id: ids, action: PersonOnSite::ON_SITE)
                         .group(:person_id).maximum(:created_at)

    ids.index_with do |id|
      last = [signed_out[id], returned[id]].compact.max
      last if last && (marked[id].nil? || last > marked[id])
    end
  end
end
