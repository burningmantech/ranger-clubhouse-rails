# frozen_string_literal: true

# The wording of the messages the Clubhouse sends. Editing here changes what the
# next message says, with no release needed.
#
# Templates are not created or deleted here. Each one belongs to a message the
# Clubhouse knows how to send, so a new row would go unread and a missing one
# would stop a message going out at all.
class Communication::MailTemplatesController < ApplicationController
  layout "admin"

  authorize_role [Role::ADMIN, Role::VC]

  before_action :set_mail_template, only: [:edit, :update]

  def index
    @mail_templates = MailTemplate.find_all.to_a
  end

  def edit
  end

  def update
    @mail_template.assign_attributes(mail_template_params)
    # Only a real change earns a new byline. Saving a form no one edited should
    # not make it look like someone rewrote the message.
    @mail_template.person_update_id = Current.person_id if @mail_template.changed?

    if @mail_template.save
      redirect_to communication_mail_templates_path,
                  success: "Email template #{@mail_template.tag} updated."
      return
    end

    render :edit, status: :unprocessable_entity
  end

  private

  def set_mail_template
    @mail_template = MailTemplate.find(params.expect!(:id))
  end

  def mail_template_params
    params.expect(mail_template: [:subject, :body, :text_body])
  end
end
