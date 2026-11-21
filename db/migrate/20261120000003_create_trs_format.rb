# frozen_string_literal: true

# The ticket vendor's three TRS import templates: the CSV columns each TRS
# export carries, in order. They were constants in TrsExport; they are rows now
# so ticketing can follow the vendor's template changes without a deploy.
#
# Seeded with exactly what those constants held, so the export reads the same
# the day this runs. The headers are the vendor's bytes: the literal &amp;, the
# out-of-order dates (that way since 2022), the double space in
# "Setup Access Pass  8/15" and the "Method of"/"Method Of" case difference are
# all load-bearing. Do not reflow, dedupe or "fix" them.
#
# Each column is [header, source]. A nil source is a column the template needs
# and the Clubhouse never fills. The constants gave those placeholder keys that
# matched nothing: ignore, not_used_*, paid_vp, spt_xfer, vp_xfer,
# vehicle_pass_gift and discount_vp_xfer.
class CreateTrsFormat < ActiveRecord::Migration[8.1]
  FORMATS = {
    "paid" => [
      ["First Name", "first_name"],
      ["Last Name", "last_name"],
      ["Email", "email"],
      ["Question: Method Of Delivery:", "delivery_type"],
      ["Question: Nickname/Project:", "project_name"],
      ["Question: Notes:", "note"],
      ["Request: $250 Ticket", "spt"],
      ["Request: $165 Vehicle Pass", nil],
      ["Request: Gift Ticket", nil], # The transferrable gift ticket is used instead
      ["Request: Gift Vehicle Pass", "gift_vp"],
      ["Request: Transferrable $250 Ticket", nil],
      ["Request: Transferrable $165 Vehicle Pass", nil],
      ["Request: Transferrable Gift Ticket", "gift_ticket"],
      ["Request: Transferrable Gift Vehicle Pass", nil],
      ["Request: Transferrable $75 Vehicle Pass", nil],
      ["Request: $75 Vehicle Pass", "sp_vp"]
    ],
    "unpaid" => [
      ["First Name", "first_name"],
      ["Last Name", "last_name"],
      ["Email", "email"],
      ["Question: Method of Delivery:", "delivery_type"],
      ["Question: Nickname/Project:", "project_name"],
      ["Question: Notes:", "note"],
      ["Request: Gift Vehicle Pass", "gift_vp"],
      ["Request: Setup Access Pass 8/26 &amp; Later", "sap_0826"],
      ["Request: Setup Access Pass 8/27 &amp; Later", "sap_0827"],
      ["Request: Setup Access Pass 8/28 &amp; Later", "sap_0828"],
      ["Request: Setup Access Pass 8/29 &amp; Later", "sap_0829"],
      ["Request: Setup Access Pass 8/8 &amp; Later", "sap_0808"],
      ["Request: Setup Access Pass 8/9 &amp; Later", "sap_0809"],
      ["Request: Setup Access Pass 8/10 &amp; Later", "sap_0810"],
      ["Request: Setup Access Pass 8/11 &amp; Later", "sap_0811"],
      ["Request: Setup Access Pass 8/12 &amp; Later", "sap_0812"],
      ["Request: Setup Access Pass 8/13 &amp; Later", "sap_0813"],
      ["Request: Setup Access Pass 8/14 &amp; Later", "sap_0814"],
      ["Request: Setup Access Pass  8/15 &amp; Later", "sap_0815"],
      ["Request: Setup Access Pass 8/16 &amp; Later", "sap_0816"],
      ["Request: Setup Access Pass 8/17 &amp; Later", "sap_0817"],
      ["Request: Setup Access Pass 8/18 &amp; Later", "sap_0818"],
      ["Request: Setup Access Pass 8/19 &amp; Later", "sap_0819"],
      ["Request: Setup Access Pass 8/20 &amp; Later", "sap_0820"],
      ["Request: Setup Access Pass 8/21 &amp; Later", "sap_0821"],
      ["Request: Setup Access Pass 8/22 &amp; Later", "sap_0822"],
      ["Request: Setup Access Pass 8/23 &amp; Later", "sap_0823"],
      ["Request: Setup Access Pass 8/24 &amp; Later", "sap_0824"],
      ["Request: Setup Access Pass 8/25 &amp; Later", "sap_0825"],
      ["Request: Setup Access Pass - Anytime", "sap_anytime"],
      ["Request: Staff Credential Pickup 8/14 &amp; After", "sc_0814"],
      ["Request: Staff Credential Pickup 8/13 &amp; After", "sc_0813"],
      ["Request: Staff Credential Pickup 8/26 &amp; After", "sc_0826"],
      ["Request: Staff Credential Pickup 8/27 &amp; After", "sc_0827"],
      ["Request: Staff Credential Pickup 8/28 &amp; After", "sc_0828"],
      ["Request: Staff Credential Pickup 8/29 &amp; After", "sc_0829"],
      ["Request: Staff Credential Pickup 8/8 &amp; After", "sc_0808"],
      ["Request: Staff Credential Pickup 8/9 &amp; After", "sc_0809"],
      ["Request: Staff Credential Pickup 8/10 &amp; After", "sc_0810"],
      ["Request: Staff Credential Pickup 8/11 &amp; After", "sc_0811"],
      ["Request: Staff Credential Pickup 8/12 &amp; After", "sc_0812"],
      ["Request: Staff Credential Pickup 8/15 &amp; After", "sc_0815"],
      ["Request: Staff Credential Pickup 8/16 &amp; After", "sc_0816"],
      ["Request: Staff Credential Pickup 8/17 &amp; After", "sc_0817"],
      ["Request: Staff Credential Pickup 8/18 &amp; After", "sc_0818"],
      ["Request: Staff Credential Pickup 8/19 &amp; After", "sc_0819"],
      ["Request: Staff Credential Pickup 8/20 &amp; After", "sc_0820"],
      ["Request: Staff Credential Pickup 8/21 &amp; After", "sc_0821"],
      ["Request: Staff Credential Pickup 8/22 &amp; After", "sc_0822"],
      ["Request: Staff Credential Pickup 8/23 &amp; After", "sc_0823"],
      ["Request: Staff Credential Pickup 8/24 &amp; After", "sc_0824"],
      ["Request: Staff Credential Pickup Anytime", "sc_anytime"],
      ["Request: Staff Credential Pickup 8/25 &amp; After", "sc_0825"]
    ],
    "lsd" => [
      ["First Name", "first_name"],
      ["Last Name", "last_name"],
      ["Email", "email"],
      ["Question: Method Of Delivery:", "delivery_type"],
      ["Question: Nickname/Project:", "project_name"],
      ["Question: Notes:", "note"],
      # Shipping addresses are unused but the vendor template still carries the
      # headers; the cells always export empty.
      ["Shipping Address:: Country", nil],
      ["Shipping Address:: Full Name", nil],
      ["Shipping Address:: Address", nil],
      ["Shipping Address:: Address Line 2", nil],
      ["Shipping Address:: City", nil],
      ["Shipping Address:: State", nil],
      ["Shipping Address:: Zip", nil],
      ["Shipping Address:: Phone", nil],
      ["Request: $165 Vehicle Pass - Directed", "lsd_vp"],
      ["Request: $550 Ticket - Directed", "lsd"],
      ["Request: $675 Ticket - Directed", nil],
      ["Request: $775 Ticket - Directed", nil],
      ["Request: $975 Ticket - Directed", nil],
      ["Request: $1500 Ticket - Directed", nil],
      ["Request: $3000 Ticket - Directed", nil],
      ["Request: Non-Transferrable $550 Ticket", nil]
    ]
  }.freeze

  # Seeding through the live model would tie this migration to whatever it
  # validates years from now.
  class Format < ActiveRecord::Base
    self.table_name = "trs_format"
  end

  def up
    create_table :trs_format, charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.string :slug, null: false
      t.json :columns, null: false
      t.index :slug, unique: true
    end

    seed
  end

  def down
    drop_table :trs_format
  end

  private

  # JSON.generate spells these the way the model's coder writes them, so a
  # seeded row does not read as changed the first time it is loaded.
  def seed
    Format.insert_all(FORMATS.map { |slug, columns| { slug:, columns: JSON.generate(columns) } })
  end
end
