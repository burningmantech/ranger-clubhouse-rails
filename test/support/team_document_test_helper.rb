# frozen_string_literal: true

# A team's published resource document, for the pages that list or read one
# (Me › Agreements, Me › Team Document). No team fixture carries a resource_tag,
# so the pointer is written here as Team Records stores it. `by:` defaults to the
# test's signed-in @person.
module TeamDocumentTestHelper
  def publish_team_document(team, by: @person, tag: "#{team.title.parameterize}-resources",
                            description: "#{team.title} Resources",
                            body: "<p>#{team.title} publishes this for its members.</p>")
    team.update_column(:resource_tag, tag)
    Document.create!(tag:, description:, body:, person_create_id: by.id, person_update_id: by.id)
  end
end
