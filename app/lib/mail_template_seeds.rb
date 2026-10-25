# frozen_string_literal: true

# Loads the mail templates that ship with the Clubhouse into the database.
#
# Every file under db/mail_templates describes one message, and its path is the
# tag it is stored under. Running this again is safe: a row is written only while
# it still matches what was loaded into it last, so a template someone has since
# edited in the Clubhouse is left as it is and reported instead.
module MailTemplateSeeds
  DIRECTORY = "db/mail_templates"

  # What a file may set. Anything else in it is ignored.
  FIELDS = %w[description subject body text_body].freeze

  module_function

  # Returns which tags were created, brought up to date, already current, and
  # left alone because someone had edited them.
  def load!
    results = { created: [], updated: [], unchanged: [], edited: [] }

    files.each do |path|
      tag = tag_for(path)
      values = values_for(path)
      record = MailTemplate.find_by(tag: tag)

      if record.nil?
        create(tag, values)
        results[:created] << tag
      elsif edited?(record)
        results[:edited] << tag
      elsif record.seeded_digest == digest_for(values)
        results[:unchanged] << tag
      else
        update(record, values)
        results[:updated] << tag
      end
    end

    results
  end

  def files
    Dir.glob(Rails.root.join(DIRECTORY, "**/*.yml")).sort
  end

  # db/mail_templates/password_reset_mailer/notify.yml -> password_reset_mailer/notify
  def tag_for(path)
    Pathname.new(path).relative_path_from(Rails.root.join(DIRECTORY)).sub_ext("").to_s
  end

  # Every field a row stores, so a field a file has dropped is cleared rather
  # than left behind, and so a fingerprint covers the same ground either way.
  def values_for(path)
    file = YAML.safe_load_file(path) || {}
    FIELDS.index_with { |field| file[field].presence }
  end

  # Taken over a list rather than the text run together, so no arrangement of
  # two fields can produce the fingerprint of another.
  def digest_for(values)
    Digest::SHA256.hexdigest(FIELDS.map { |field| values[field] }.to_json)
  end

  # Whether a row now holds something other than what was loaded into it. A row
  # made by hand in the Clubhouse counts, since nothing was ever loaded into it.
  def edited?(record)
    return true if record.seeded_digest.blank?

    record.seeded_digest != digest_for(record.attributes.slice(*FIELDS))
  end

  # Written past the model rather than through it, so a load leaves no trail in
  # the action log: that log is there to show who changed some wording, and a
  # deployment is not a who. The same checks still run, on a stand-in first, so a
  # file the Clubhouse would refuse stops the whole load.
  def create(tag, values)
    MailTemplate.new(values.merge("tag" => tag)).validate!

    now = Time.current
    MailTemplate.insert_all!(
      [values.merge("tag" => tag, "seeded_digest" => digest_for(values),
                    "created_at" => now, "updated_at" => now)]
    )
  end

  def update(record, values)
    record.assign_attributes(values)
    record.validate!

    record.update_columns(
      values.merge("seeded_digest" => digest_for(values), "updated_at" => Time.current)
    )
  end
end
