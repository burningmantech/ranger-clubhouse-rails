# frozen_string_literal: true

# Mail templates are written by people, so a mistake should read like one:
# strict parsing reports markup it does not understand instead of printing it.
Liquid::Environment.default.error_mode = :strict

# Where a template looks when it includes a piece shared with other messages.
# Set here rather than at load time, so the class is only reached for once a
# template actually asks for a piece.
Rails.application.config.to_prepare do
  Liquid::Environment.default.file_system = MailTemplateFileSystem.new
end

# Teaches Rails to render Liquid. A template becomes a call that renders its own
# source against the values the mailer supplied. Escaping is decided here, where
# the part is still known: an HTML part escapes what it is given, a plain text
# part does not.
ActionView::Template.register_template_handler :liquid, lambda { |template, source|
  "MailTemplateRenderer.render(#{source.inspect}, liquid_assigns, " \
    "escape_html: #{template.format != :text}).html_safe"
}
