# frozen_string_literal: true

# A Clubhouse message's text: something written, and no more than
# PersonMessage::MAX_TEXT characters of it. The editor's markup is not
# counted, so a bold word or a list costs what its words do
# (PersonMessage.plain_text); the markup itself is capped well above anything
# the editor writes for that much text (PersonMessage::MAX_HTML_BYTES), and
# checked first, so a crafted post is never parsed.
#
#   validates :body, message_text: true
class MessageTextValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    # nil when it has too much markup to read, or markup nested too deep to.
    text = PersonMessage.plain_text(value) if value.to_s.bytesize <= PersonMessage::MAX_HTML_BYTES
    if text.nil?
      record.errors.add(attribute, :too_long, message: "Your message has too much formatting to send. " \
                                                       "Remove some, or shorten it.")
    elsif text.blank?
      record.errors.add(attribute, :blank, message: "Write your message before sending it.")
    elsif text.length > PersonMessage::MAX_TEXT
      record.errors.add(attribute, :too_long, message: "Your message is #{text.length.to_fs(:delimited)} characters " \
                                                       "long. Shorten it to #{PersonMessage::MAX_TEXT.to_fs(:delimited)} or fewer.")
    end
  end
end
