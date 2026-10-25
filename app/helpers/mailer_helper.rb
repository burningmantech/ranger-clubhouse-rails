# frozen_string_literal: true

module MailerHelper
  # Render the Ranger header image for emails
  def ranger_header_image
    # Use inline styles for email compatibility
    content_tag(:div, style: "text-align: center; margin-bottom: 20px;") do
      image_tag(
        asset_url("ranger-logo.png"),
        alt: "Black Rock Rangers",
        style: "max-width: 200px; height: auto;"
      )
    end
  end
end
