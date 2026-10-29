# frozen_string_literal: true

module TeamsPositions::TeamDocumentsHelper
  # "Updated Jun 18, 2026 by Lantern": who last saved the document, and when.
  # An old row may lack the dates; the saver is named even once deleted.
  def team_document_updated(document)
    at = document.updated_at || document.created_at
    by = person_display_name(document.person_update, document.person_update_id, blank: nil)
    return nil unless at || by

    ["Updated", (mdy_format(at) if at), ("by #{by}" if by)].compact.join(" ")
  end

  # One team's row on the index. Most teams have no document, so saying so is
  # the row's ordinary text; only a pointer that leads nowhere -- its document
  # deleted, or a tag no resource document may have (Document.resource_tag) --
  # and a team no longer active earn a badge. The team's own page says more.
  def team_document_row(team, document)
    problem = team_document_pointer_problem(team, document)
    meta = document ? team_document_updated(document) : ("No document yet" unless problem)

    ui_drill_down_row teams_positions_team_document_path(team), team.title,
                      id: "team-#{team.id}", meta:,
                      badges: [(ui_badge(problem, :error, size: "base") if problem),
                               (ui_badge("Inactive", :secondary, size: "base") unless team.active)]
  end

  private

  def team_document_pointer_problem(team, document)
    return nil if document || team.resource_tag.blank?

    Document.resource_tag(team.resource_tag) ? "Document missing" : "Tag cannot be used"
  end
end
