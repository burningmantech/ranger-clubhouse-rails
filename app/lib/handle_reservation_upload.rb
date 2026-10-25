# frozen_string_literal: true

# Bulk-creates reserved handles from pasted text, one handle per line:
#
#   handle                    - handle using the form's expiration date
#   handle,YYYY-MM-DD         - handle with its own expiration date
#   handle,YYYY-MM-DD,reason  - handle with its own date and reason
#   handle,,reason            - handle with its own reason only
#
# Returns one result row per line, each carrying the source line and its
# number so the page can point at the line that needs fixing. Each row is
# validated through the model itself, so a verify pass (commit: false) reports
# exactly what a commit would reject without saving anything. Committing saves
# row by row: rows that fail are reported while the rest are still created —
# the page only offers commit after a clean verify.
class HandleReservationUpload
  def self.execute(handles:, reservation_type:, expires_on: nil, reason: "", twii_year: nil, commit: false)
    is_twii = reservation_type == HandleReservation::RESERVATION_TYPE_TWII_PERSON
    seen = Set.new

    handles.to_s.each_line.with_index(1).filter_map do |line, number|
      line = line.strip
      next if line.empty?

      handle, line_expires, line_reason = line.split(",", 3).map(&:strip)
      row = {
        line_number: number,
        line: line,
        handle: handle,
        reservation_type: reservation_type,
        reason: line_reason.presence || reason,
        expires_on: expires_on,
        twii_year: is_twii ? twii_year : nil
      }

      # Line dates are part of the paste format, so a garbled one is reported
      # against the line rather than surfacing as a model cast error.
      if line_expires.present?
        begin
          row[:expires_on] = Date.parse(line_expires).to_s
        rescue ArgumentError
          next row.merge(error: "Invalid Date")
        end
      end

      record = HandleReservation.new(row.except(:line_number, :line))

      # Validating before saving catches a handle the list repeats: the model
      # only sees rows already in the database, so a repeat would otherwise
      # pass verify and then fail partway through the commit.
      if !record.valid?
        row[:error] = record.errors.full_messages.join(" ")
      elsif !seen.add?(duplicate_key(record))
        row[:error] = "Handle is listed more than once in this upload"
      elsif commit && !record.save
        row[:error] = record.errors.full_messages.join(" ")
      else
        row[:expires_on] = record.expires_on&.to_s
      end

      row
    end
  end

  # Mirrors HandleReservation#ensure_unique_reservation_key so a repeat within
  # the pasted list is judged exactly the way a repeat of a saved handle is.
  def self.duplicate_key(record)
    [record.normalized_handle, record.reservation_type, (record.twii_year if record.twii_person?)]
  end
  private_class_method :duplicate_key
end
