# frozen_string_literal: true

# BMID > Badge Titles: the per-line select on the Set BMID Titles preview.
# (Compact form: Bmid is the model class, not a module.)
module Bmid::TitlesHelper
  # A title's position, or an honest placeholder. The table carries no foreign
  # key, so a position deleted on the Laravel side leaves the row pointing at
  # nothing.
  def bmid_title_position_name(title)
    title.position&.title || "Position ##{title.position_id} (missing)"
  end

  # Everything one badge line's cell needs: the options, which is selected, the
  # text behind the custom option, and the key both fields post under.
  #
  # A badge already carrying a title the list has no option for -- an older
  # custom title, or one whose row has since been deleted -- opens on Custom
  # with that text in the box, so reviewing a row never silently drops it.
  def bmid_title_cell(titles, row, line)
    value = row.proposed[line].to_s
    options = bmid_title_options(titles, row)
    custom = value.present? && options.none? { |(_label, option)| option == value }

    { options:,
      selected: custom ? Bmid::TitlesController::CUSTOM : value,
      custom: custom ? value : nil,
      key: "#{row.person_id}-#{line}" }
  end

  # The titles a line offers, each labelled with the position that earns it and
  # flagged when this person does not hold it. Not-held titles stay selectable:
  # the point of the preview is that an admin can overrule the positions.
  def bmid_title_options(titles, row)
    titles.map do |title|
      position = bmid_title_position_name(title)
      # A position named after its own title -- 007 -- would otherwise read
      # "007 (007)".
      notes = [(position unless position == title.title),
               ("not held" unless row.holds?(title.position_id))].compact

      [notes.any? ? "#{title.title} (#{notes.join(", ")})" : title.title, title.title]
    end
  end

  # The title-earning positions a person holds, for the row's subtitle.
  def bmid_title_positions_held(titles, row)
    titles.filter_map { |title| bmid_title_position_name(title) if row.holds?(title.position_id) }.uniq
  end
end
