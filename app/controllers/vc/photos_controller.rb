# frozen_string_literal: true

# Read-only browser for every BMID photo in the Clubhouse (all people, all
# statuses). Review actions live on the Photo Review page.
class Vc::PhotosController < ApplicationController
  layout "vc"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to view photos."

  def index
    result = PersonPhoto.find_for_query(page: params[:page])
    @photos = result[:person_photo]
    @pagy = result[:pagy]
  end
end
