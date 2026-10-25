# frozen_string_literal: true

# Lets one mail template include another. A template asking for a piece by tag
# gets that row's HTML back.
#
# A piece is asked for by name in a template, so a missing one is a mistake
# worth hearing about rather than a gap in the middle of a message.
class MailTemplateFileSystem
  def read_template_file(tag)
    MailTemplate.find_by(tag: tag)&.body ||
      raise(Liquid::FileSystemError, "There is no mail template named #{tag}")
  end
end
