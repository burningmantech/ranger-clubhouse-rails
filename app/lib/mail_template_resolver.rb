# frozen_string_literal: true

# Lets Rails render a message whose wording lives in the database.
#
# It answers the same lookups a mailer already makes for its own views: the
# folder and action Rails asks for become a tag, and the row found under that tag
# comes back as a template Rails can render. A lookup with no row answers with
# nothing, so anything still kept on disk is found the usual way.
#
# A built template is kept until its row changes. Without that, sending the same
# message a thousand times would compile it a thousand times over.
class MailTemplateResolver < ActionView::Resolver
  def initialize
    super
    @built = Concurrent::Map.new
  end

  def clear_cache
    @built.clear
  end

  private

  def find_templates(name, prefix, _partial, details, _locals)
    template = MailTemplate.find_by(tag: [prefix.presence, name].compact.join("/"))
    return [] if template.nil?

    formats_for(details).filter_map { |format| build(template, format) }
  end

  # The formats Rails asked for, narrowed to the ones a message can have. An
  # empty ask means either part will do.
  def formats_for(details)
    wanted = Array(details[:formats]).map(&:to_sym)
    known = MailTemplate::BODY_COLUMNS.keys
    wanted.empty? ? known : known & wanted
  end

  def build(template, format)
    source = template.source_for(format)
    return nil if source.nil?

    @built.fetch_or_store([template.tag, format, template.updated_at]) do
      ActionView::Template.new(
        source,
        "mail_template:#{template.tag} (#{format})",
        ActionView::Template.handler_for_extension(:liquid),
        format: format,
        locals: [],
        virtual_path: template.tag
      )
    end
  end
end
