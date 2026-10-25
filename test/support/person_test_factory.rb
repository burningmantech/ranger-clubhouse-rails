# frozen_string_literal: true

# A fully valid Person with every required column filled -- the same
# boilerplate several older tests still open-code locally. attributes: any
# other column the test needs set at creation, e.g. on_site: true.
module PersonTestFactory
  def create_person(callsign, status: Person::ACTIVE, years: [], **attributes)
    Person.create!(callsign: callsign, first_name: callsign, last_name: "Shifter",
                   email: "#{callsign.downcase}@example.com", status: status,
                   password: "password", home_phone: "+17755550100", street1: "123 Test St",
                   city: "Test City", state: "California", zip: "90000", country: "United States",
                   years_as_ranger: years, **attributes)
  end
end
