class RubyMetaphone < ActiveRecord::Migration[8.1]
  def change
    people = Person.select(:id, :callsign).all
    people.each do |person|
      sql = Person.sanitize_sql_array(
        [
          "UPDATE person SET callsign_soundex=? WHERE id=?",
          WordUtils.metaphone(WordUtils.normalize_word(person.callsign)),
          person.id
        ])
      ActiveRecord::Base.connection.execute(sql)
    end

    PersonFka.all.map do |fka|
      sql = PersonFka.sanitize_sql_array(
        [
          "UPDATE person_fka SET fka_soundex=? WHERE id=?",
          WordUtils.metaphone(WordUtils.normalize_word(fka.fka)),
          fka.id
        ])
      ActiveRecord::Base.connection.execute(sql)
    end
  end
end