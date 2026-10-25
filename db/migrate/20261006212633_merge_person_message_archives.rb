# frozen_string_literal: true

# Folds Clubhouse 2's yearly message archives back into person_message.
#
# Clubhouse 2 archived with CREATE TABLE person_message_<year> AS SELECT * FROM
# person_message, then deleted the earlier years, so each archived row kept its
# id: 1-16697, in date order, below every live row. An id found twice -- in two
# archives, or in the 2024 archive and the live table -- is one message copied
# twice. Keeping the ids keeps the table in date order and leaves the
# person-message-* action logs pointing where they did.
#
# Every merged row is read, delivered and archived on both sides. The archives
# never recorded a sender's account, so each row is a broadcast or, failing
# that, a message from whoever message_from names; a blank sender becomes
# "Unknown" and a blank subject "(no subject)" (decided 2026-10-06).
#
# Raw SQL on purpose: the archives have no models, and each is copied by one
# INSERT ... SELECT whose columns differ from table to table.
class MergePersonMessageArchives < ActiveRecord::Migration[8.1]
  ARCHIVES = %w[
    person_message_2012 person_message_2013 person_message_2014 person_message_2015
    person_message_2016 person_message_2017 person_message_2018 person_message_2019
    person_message_2022 person_message_2023 person_message_2024
  ].freeze

  # How the broadcast system signed its messages before the 2024 archive
  # carried broadcast_id.
  RBS_SENDERS = ["The Ranger Broadcasting System", "Broadcast Service"].freeze

  # A run that stopped part way can run again: rows already in person_message
  # are skipped, and a table an earlier run dropped had been merged first.
  def up
    present = connection.tables
    refuse_unknown_archives(present)
    archives = ARCHIVES & present
    return if archives.empty? # an earlier run merged and dropped them all

    on_phoenix_clock do
      refuse_shared_ids(archives)
      archives.each { |table| merge(table) }
      flatten_reply_chains(archives)
      refuse_missing_rows(archives)
    end

    archives.each { |table| drop_table table }
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "The year tables are dropped. From the backup taken before migrating, restore only the " \
          "person_message_<year> tables, delete from person_message every id they hold that the " \
          "backup's person_message did not, then delete this version from schema_migrations."
  end

  private

  # Anything already in person_message -- live, or merged by an earlier run --
  # is skipped. The helpers go through `connection` directly so the log shows
  # one line per table.
  def merge(table)
    rbs = "a.message_from IN (#{RBS_SENDERS.map { connection.quote(it) }.join(", ")})"
    rbs = "a.broadcast_id IS NOT NULL OR #{rbs}" if connection.column_exists?(table, :broadcast_id)

    say_with_time "Merging #{table}" do
      connection.exec_update(<<~SQL)
        INSERT INTO person_message
          (id, person_id, creator_person_id, created_at, expires_at, reply_to_id, broadcast_id,
           subject, body, message_from, sender_type,
           delivered, recipient_read, sender_read, recipient_archived, sender_archived)
        SELECT a.id, a.person_id, a.creator_person_id, a.#{created(table)},
               #{copied(table, :expires_at)}, #{copied(table, :reply_to_id)}, #{copied(table, :broadcast_id)},
               IF(TRIM(a.subject) = '', '(no subject)', a.subject), a.body,
               IF(TRIM(a.message_from) = '', 'Unknown', a.message_from),
               IF(#{rbs}, 'rbs', 'other'),
               TRUE, TRUE, TRUE, TRUE, TRUE
        FROM #{table} a
        LEFT JOIN person_message p ON p.id = a.id
        WHERE p.id IS NULL
        ORDER BY a.id
      SQL
    end
  end

  def created(table) = connection.column_exists?(table, :created_at) ? "created_at" : "`timestamp`"

  def copied(table, column) = connection.column_exists?(table, column) ? "a.#{column}" : "NULL"

  # Clubhouse 2 pointed a 2024 reply at the message it answered, often itself a
  # reply, in chains up to 7 deep. Clubhouse 3 shows one level under the thread
  # top, so each merged reply moves up to its top, or no page ever shows it.
  # Every pass lifts each one a level; a chain that never settles is a loop.
  def flatten_reply_chains(archives)
    sources = archives.select { connection.column_exists?(it, :reply_to_id) }
    return if sources.empty?

    join = "person_message r JOIN person_message p ON p.id = r.reply_to_id"
    nested = "p.reply_to_id IS NOT NULL AND r.id IN (#{sources.map { "SELECT id FROM #{it}" }.join(" UNION ")})"
    say_with_time "Pointing merged replies at their thread tops" do
      found = connection.select_value("SELECT COUNT(*) FROM #{join} WHERE #{nested}").to_i
      passes = 0
      until connection.exec_update("UPDATE #{join} SET r.reply_to_id = p.reply_to_id WHERE #{nested}").zero?
        raise "Merged reply chains did not settle in 10 passes" if (passes += 1) > 10
      end
      found
    end
  end

  # Keeping ids is safe only while each id names one message: the same
  # recipient, time and text in every copy (delivered differs, and is reset).
  def refuse_shared_ids(archives)
    copies = archives.map { "SELECT id, person_id, #{created(it)} AS created_at, MD5(body) FROM #{it}" }
    copies << "SELECT id, person_id, created_at, MD5(body) FROM person_message"
    shared = connection.select_values("SELECT id FROM (#{copies.join(" UNION ")}) c GROUP BY id HAVING COUNT(*) > 1 LIMIT 10")
    raise "Ids naming more than one message: #{shared.join(", ")}" if shared.any?
  end

  # A year archived after this was written has the modern columns and needs
  # its own mapping, not this one.
  def refuse_unknown_archives(present)
    unknown = present.grep(/\Aperson_message_\d{4}\z/) - ARCHIVES
    raise "Unexpected archive tables: #{unknown.join(", ")}" if unknown.any?
  end

  def refuse_missing_rows(archives)
    ids = archives.map { "SELECT id FROM #{it}" }.join(" UNION ")
    missing = connection.select_value("SELECT COUNT(*) FROM (#{ids}) a LEFT JOIN person_message p ON p.id = a.id WHERE p.id IS NULL")
    raise "#{missing} archived messages are not in person_message" unless missing.to_i.zero?
  end

  # The 2012-2022 archives keep a TIMESTAMP, which MariaDB turns into wall time
  # on the session's clock. Every DATETIME in person_message is Phoenix wall
  # time (Clubhouse 2 pinned its sessions to -07:00, and Arizona keeps no
  # daylight time), so convert at -07:00 whatever clock the server keeps. An
  # offset, not a zone name: a server without zone tables knows no names.
  def on_phoenix_clock
    zone = connection.select_value("SELECT @@session.time_zone")
    connection.execute("SET time_zone = '-07:00'")
    yield
  ensure
    connection.execute("SET time_zone = #{connection.quote(zone)}") if zone
  end
end
