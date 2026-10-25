# frozen_string_literal: true

# Set BMID Titles: stamp the titles a person's positions earn onto their badge.
#
# Port of App\Lib\BMIDManagement::setBMIDTitles, split into a preview and a
# commit so the titles can be corrected before they are written -- upstream
# wrote straight to the badges with nothing to review.
#
# Only the current year is ever touched. The positions someone holds are a
# statement about now, not about a year that has already been printed.
class BmidTitleAssignment
  LINES = BmidTitle::TITLE_LINES

  AUDIT_REASON = "maintenance - set BMID titles"

  # One badge on the preview, with what its titles would become.
  #
  # proposed is line number => the title to print, so the preview and the
  # commit read the same shape whether or not the admin touched the row.
  #
  # new_badge is captured rather than asked of the record, because the results
  # page reports it after the save that makes it false.
  Row = Struct.new(:bmid, :held_position_ids, :proposed, :new_badge, keyword_init: true) do
    def person = bmid.person
    def person_id = bmid.person_id

    # The badge did not exist -- Bmid.find_for_person_ids synthesized it.
    def new_badge? = new_badge

    def holds?(position_id) = held_position_ids.include?(position_id)
  end

  class << self
    # Every qualified person holding a title-earning position, with the titles
    # their positions earn already filled in.
    #
    # @param year [Integer]
    # @return [Array<Row>] sorted by callsign, the order find_for_person_ids returns
    def preview(year)
      titles = BmidTitle.ordered.to_a
      return [] if titles.empty?

      held = held_position_ids_by_person(titles)
      return [] if held.empty?

      badges(year, held.keys).map do |bmid|
        held_ids = held[bmid.person_id]
        Row.new(bmid:, held_position_ids: held_ids, new_badge: bmid.new_record?,
                proposed: proposed_titles(bmid, titles, held_ids))
      end
    end

    # Write the previewed titles, as corrected by the admin.
    #
    # The candidates are re-derived here rather than trusted from the form: a
    # posted row for someone who does not qualify, or who holds no
    # title-earning position, is simply not in the preview and so is ignored.
    #
    # @param year [Integer]
    # @param submitted [Hash{Integer=>Hash{Integer=>String,nil}}] person id =>
    #   title line => the title to print, nil for a blank line. People and lines
    #   missing from the hash keep the titles the preview proposed.
    # @return [Array<Row>] the badges that changed, in preview order
    def apply(year, submitted)
      changed = preview(year).select { |row| assign(row, submitted[row.person_id]) }

      # One run, one outcome. A badge that fails to save half way through a few
      # hundred of them would otherwise leave the admin with no way to tell
      # which titles were written and which were not.
      Bmid.transaction do
        changed.each do |row|
          row.bmid.audit_reason = AUDIT_REASON
          row.bmid.save!
        end
      end

      changed
    end

    private

    # Move the badge onto its final titles, and answer whether that is a change
    # worth saving.
    def assign(row, overrides)
      LINES.each do |line|
        value = overrides&.key?(line) ? overrides[line] : row.proposed[line]
        row.bmid.public_send(:"title#{line}=", value.presence)
      end

      return false unless row.bmid.changed?

      # A brand new badge with nothing printed on it is not worth a row.
      !(row.new_badge? && LINES.all? { |line| row.bmid.public_send(:"title#{line}").blank? })
    end

    # What each line would say: the title the person's positions earn, or
    # whatever the badge already says when no position of theirs feeds it.
    #
    # titles arrives in BmidTitle.ordered order, so the first match on a line is
    # the one with the lowest sort_index -- the preference the admin set.
    def proposed_titles(bmid, titles, held_ids)
      LINES.index_with do |line|
        earned = titles.find { |title| title.title_line == line && held_ids.include?(title.position_id) }

        earned&.title || bmid.public_send(:"title#{line}")
      end
    end

    # person id => the title-earning positions they hold.
    def held_position_ids_by_person(titles)
      PersonPosition.where(position_id: titles.map(&:position_id))
                    .pluck(:person_id, :position_id)
                    .group_by(&:first)
                    .transform_values { |pairs| pairs.map(&:last).to_set }
    end

    # Departed people are excluded, and so is anyone who has not earned a
    # printed badge yet -- the 2024 Council ruling, via not_qualified_to_print?.
    def badges(year, person_ids)
      Bmid.find_for_person_ids(year, person_ids, true).reject(&:not_qualified_to_print?)
    end
  end
end
