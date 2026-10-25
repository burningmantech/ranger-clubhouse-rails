# Ticketing System Specification

> Comprehensive business rules and requirements for the Black Rock Rangers Ticketing & Provisions system

---

## Table of Contents

1. [Overview](#overview)
2. [Ticketing Periods](#ticketing-periods)
3. [Item Types & Definitions](#item-types--definitions)
4. [Delivery Methods](#delivery-methods)
5. [Payment System](#payment-system)
6. [Entry Dates & Restrictions](#entry-dates--restrictions)
7. [BMID Integration](#bmid-integration)
8. [Transfer & Sale Rules](#transfer--sale-rules)
9. [Expiration & Banking](#expiration--banking)
10. [Event Radios](#event-radios)
11. [Special Cases & Edge Conditions](#special-cases--edge-conditions)

---

## Overview

The Ticketing & Provisions system manages event access documents, vehicle passes, and appreciations for Black Rock Rangers. Items are earned through volunteer service and managed through the Clubhouse interface, with payment and final processing handled through the Burning Man Ticketing System.

**Key Principle:** The Clubhouse manages claiming and allocation; the Burning Man Ticketing System handles payment and final delivery.

---

## Ticketing Periods

The ticketing system operates in four distinct periods throughout the year:

### PERIOD_OFF_SEASON
- **When:** Post-event through late January
- **User Actions:** View banked tickets from previous years
- **System Behavior:** No claiming available; display informational content only
- **UI Display:** Show banked tickets with expiration dates

### PERIOD_ANNOUNCE
- **When:** Late January through early summer
- **User Actions:** View available tickets that were previous banked and have not expired, new uploaded tickets earn from the previous event. Provisions are not listed here.
- **System Behavior:** Display what user qualifies for; no claiming yet
- **UI Display:** Show available items with expiration dates and instructions to wait for ticketing window

### PERIOD_OPEN
- **When:** June or July (configurable)
- **User Actions:** Claim tickets, vehicle passes, provisions, and SAPs
- **System Behavior:** Accept claims, validate selections, prepare for submission
- **UI Display:** Active claiming interface with forms and confirmation
- **Important:** Window has a closing date (`submit_date`)

### PERIOD_CLOSED
- **When:** After ticketing window closes through event
- **User Actions:** View claimed and banked items only. Banked items have an expiration date.
- **System Behavior:** No changes allowed; items submitted to Burning Man Ticketing
- **UI Display:** Read-only view of claimed items with delivery information

---

## Item Types & Definitions

### Staff Credential (SC)
- **Type:** Wristband (NOT a paper ticket)
- **Cost:** Free
- **Qualification:** Earned through high volunteer service (`sc_credits` threshold)
- **Features:**
  - Acts as both event ticket AND Setup Access Pass (SAP)
  - Can have `access_any_time` flag (allows entry at any time)
  - Otherwise has specific `access_date` for entry restriction
  - Can be paired with free Vehicle Pass
- **Delivery:** Will Call only (pickup at event)
- **Transfer:** Cannot be transferred or sold

### Special-Priced Ticket (SPT)
- **Type:** Event ticket
- **Cost:** `@ticketing_info.spt_cost` (paid amount)
- **Qualification:** Earned through volunteer service (`spt_credits` threshold)
- **Features:**
  - Can be paired with paid Vehicle Pass
  - Separate Setup Access Pass (SAP) issued if qualified
- **Delivery:** Will Call OR USPS Mail (user choice at checkout)
- **Transfer:** Cannot be transferred or sold
- **Payment:** Through Burning Man Ticketing System

### Vehicle Pass (VP)
- **Type:** Vehicle entry permit
- **Cost:** 
  - Free when paired with Staff Credential
  - `@ticketing_info.sp_vp_cost` when paired with Special-Priced Ticket
- **Qualification:** Must have claimed a ticket (SC or SPT)
- **Delivery:** Same method as paired ticket
- **Transfer:** Cannot be transferred or sold
- **Payment:** Through Burning Man Ticketing System (if paid)

### Setup Access Pass (SAP/WAP)
- **Type:** Early entry document
- **Internal Code:** WAP (legacy naming)
- **Cost:** Free
- **Qualification:** All Rangers in good standing who intend to volunteer on playa
- **Features:**
  - Allows entry before general gate opening
  - Has specific `access_date` (cannot enter before this time)
  - For Staff Credential holders: SC acts as the SAP (no separate document)
  - For SPT holders: Separate email document
- **Delivery:** Email (PDF document)
- **Transfer:** Cannot be transferred or sold
- **Entry Enforcement:** Gate staff will turn away anyone attempting early entry

### Significant Other SAP (WAPSO)
- **Type:** Setup Access Pass for significant other
- **Internal Code:** WAPSO (legacy naming)
- **Cost:** Free
- **Qualification:** Available to qualified Rangers
- **Limit:** Maximum number defined in `@ticketing_info.wap_so_max`
- **Features:**
  - Individual name recorded per SAP (`AccessDocument.name`)
  - Each has own `access_date` (may differ from user's SAP)
  - Always emailed regardless of ticket delivery method
- **Delivery:** Email (PDF document)
- **Transfer:** Cannot be transferred or sold

### Gift Ticket
- **Type:** Event ticket
- **Cost:** Free (gifted by organization)
- **Qualification:** Issued by administration
- **Features:**
  - Can be transferred to anyone
  - Must be claimed to be used
- **Delivery:** Through Burning Man Ticketing System
- **Transfer:** CAN be transferred, CANNOT be sold
- **Important:** If unused, contact Ranger Ticketing Team to offer to another Ranger

### Provisions

Provisions are appreciations given to qualified Rangers:

#### Meal Passes
- **Type:** Event meal access
- **Cost:** Free
- **Integration:** Tied to user's BMID (event badge)
- **Delivery:** No separate document; linked to BMID
- **Variants:** Different meal plan types (defined in `Provisions.meals.title`)

#### Wet Spot Access (Showers)
- **Type:** Shower facility access
- **Cost:** Free
- **Integration:** Tied to user's BMID (event badge)
- **Delivery:** No separate document; linked to BMID

#### Event Radios
- **Type:** Communication equipment
- **Cost:** Free (limited resource)
- **Qualification:** Based on:
  1. Volunteer hours from previous event, OR
  2. User's role within department for coming event
  3. Priority given to department role
- **Integration:** NOT tied to BMID
- **Allocation:** NOT guaranteed even if qualified
- **Quantity:** User may qualify for multiple radios
- **Delivery:** Physical pickup at event

### Late Season Directed (LSD) Items

#### LSD Ticket
- **Type:** Late season ticket allocation
- **Claiming:** Handled OUTSIDE the Clubhouse
- **Recording:** Recorded IN Clubhouse for administration purposes
- **UI:** Not part of user-facing claiming interface

#### LSD Vehicle Pass
- **Type:** Late season vehicle pass allocation
- **Claiming:** Handled OUTSIDE the Clubhouse
- **Recording:** Recorded IN Clubhouse for administration purposes
- **UI:** Not part of user-facing claiming interface

---

## Delivery Methods

### Will Call
- **Pickup:** At event gate/box office
- **Name:** Items under user's legal name (`current_user.first_name` `current_user.last_name`)
- **Applicable Items:** 
  - Staff Credentials (always Will Call)
  - Special-Priced Tickets (user choice)
  - Vehicle Passes (follows paired ticket method)
- **Important:** User must have government ID matching legal name

### USPS Mail
- **Types:**
  - Standard Mail: `@ticketing_info.mail_standard_price`
  - Priority Mail: `@ticketing_info.mail_priority_price`
- **Address:** Entered during checkout in Burning Man Ticketing System
- **Applicable Items:**
  - Special-Priced Tickets (user choice)
  - Vehicle Passes (follows paired ticket method)
- **Important:** Address verification critical; cannot change after submission.

### Email
- **Format:** PDF document
- **Applicable Items:**
  - Setup Access Passes (SAP/WAP)
  - Significant Other SAPs (WAPSO) - always emailed
- **Important:** Check spam folder; contact ticketing if not received
- **Timing:** Late July - early August typically

---

## Payment System

### Burning Man Ticketing System
- **Vendor:** External system (separate from Clubhouse)
- **Vendor Name:** `@ticketing_info.ticket_vendor_name`
- **Contact Email:** `@ticketing_info.ticket_vendor_email`
- **Process:**
  1. User claims items in Clubhouse
  2. Clubhouse submits claims to Burning Man Ticketing
  3. Burning Man Ticketing sends payment email
  4. User pays through Burning Man Ticketing portal
  5. Items delivered via selected method

### Pricing

#### Special-Priced Ticket
- **Amount:** `@ticketing_info.spt_cost`
- **Payment Deadline:** `@ticketing_info.paid_by`

#### Vehicle Pass (with SPT)
- **Amount:** `@ticketing_info.sp_vp_cost`
- **Payment Deadline:** `@ticketing_info.paid_by`

#### Late Season Directed Items
- **Payment Deadline:** `@ticketing_info.lsd_paid_by`

#### Free Items
- Staff Credential: Free
- Vehicle Pass with Staff Credential: Free
- Setup Access Passes: Free
- Provisions: Free
- Gift Tickets: Free

---

## Entry Dates & Restrictions

### Access Date System

All Setup Access Passes (including Staff Credentials when acting as SAP) have entry date controls:

**AccessDocument Fields:**
- `access_date` - Earliest allowed entry date/time
- `access_any_time` - Boolean flag (Staff Credential only)

### Entry Rules

1. **Before Access Date:**
   - Entry NOT permitted
   - Gate staff will turn away early arrivals
   - No exceptions

2. **On or After Access Date:**
   - Entry permitted
   - Present credential/SAP to gate staff

3. **Access Any Time:**
   - Only available for Staff Credentials
   - When `access_any_time = true`
   - Allows entry at any time during event setup

### Entry Date Types

| Item Type | Entry Date Source | Notes |
|-----------|-------------------|-------|
| Staff Credential | `AccessDocument.access_date` OR `access_any_time` | Can enter any time if flag set |
| Setup Access Pass (WAP) | `AccessDocument.access_date` | Specific date/time required |
| Significant Other SAP (WAPSO) | `AccessDocument.access_date` | May differ from user's entry date |

### Multiple Entry Dates

**Scenario:** User has Staff Credential + multiple Significant Other SAPs
- Staff Credential may have `access_date` of August 15
- WAPSO #1 may have `access_date` of August 17  
- WAPSO #2 may have `access_date` of August 17
- This is normal and expected behavior
- Each person enters on their respective access date

---

## BMID Integration

### What is a BMID?
The BMID (Burning Man ID) is the event badge issued to all volunteers at the event.

### BMID-Linked Items

**Meal Passes:**
- Tied directly to BMID
- No separate document needed
- Scanned at meal tent using BMID

**Wet Spot Access (Showers):**
- Tied directly to BMID
- No separate document needed
- Scanned at shower facility using BMID

### Non-BMID Items

**Event Radios:**
- NOT tied to BMID
- Physical equipment checked out separately
- Requires qualification verification

---

## Transfer & Sale Rules

### Cannot Transfer or Sell
The following items are strictly non-transferable and non-sellable:
- Staff Credentials
- Special-Priced Tickets
- Vehicle Passes
- Setup Access Passes (SAP/WAP)
- Significant Other SAPs (WAPSO)

**Enforcement:** Violations may result in revocation and loss of future eligibility.

### Gift Tickets - Limited Transfer
- **CAN** be transferred to anyone
- **CANNOT** be sold
- Must be claimed through the system to be used
- If unused, should be offered back to Ranger Ticketing Team
- More than one ticket may be issued (rare case)

---

## Expiration & Banking

### Ticket Banking System

**When Tickets are Banked:**
- User doesn't claim during open window (automatic banking post-event)
- User explicitly chooses to bank for future event
- Ticket not used for current event

**Expiration Dates:**
- All banked items have `AccessDocument.expiry_date`
- Expiration occurs in **September of the expiry_date year**
- Example: `expiry_date = 2027-09-15` means ticket expires September 2027

**Banking Rules:**
- Tickets can be banked year-over-year
- Must be claimed during ticketing window to be used
- Expired tickets cannot be claimed.
- Expired tickets will be canceled post-event.

### Viewing Banked Tickets

**Off-Season Period:**
- Shows all banked tickets with expiration dates
- Format: "Ticket Type - earned YEAR, expires September YEAR"

**Announce Period:**
- Shows available tickets (including banked)
- Prompts user to return when window opens

---

## Event Radios

### Qualification Criteria

Event Radios are qualified based on **TWO** possible criteria:

1. **Volunteer Hours** - Hours logged during previous event
2. **Department Role** - User's position for upcoming event

**Priority:** Department role qualification takes priority over hour-based qualification.

### Allocation Rules

- **Limited Availability:** Total radio pool is finite
- **Not Guaranteed:** Qualification does not guarantee allocation
- **Multiple Radios:** User may qualify for more than one radio
- **Allocation Process:** Determined closer to event date
- **Display:** Show number qualified for (e.g., "2 Event Radios")

### Important Distinctions

- Event Radios are provisions (internal classification)
- But NOT tied to BMID (unlike meals/showers)
- Requires separate check-out process at event
- Different qualification rules than other provisions

---

## Special Cases & Edge Conditions

### Late Season Directed (LSD) Items

**LSD Tickets & LSD Vehicle Passes:**
- **Claiming:** Handled OUTSIDE the Clubhouse through separate process
- **Recording:** Recorded IN the Clubhouse for administration tracking
- **UI Display:** May appear in user's records but not in claiming interface
- **Purpose:** Administration needs to track these for reporting purposes

### Multiple WAPSO with Individual Details

**Scenario:** User claims SAPs for multiple significant others
- Each WAPSO has individual `AccessDocument.name` (the SO's name)
- Each WAPSO has individual `access_date` (may differ from each other)
- Each WAPSO has individual `access_date` (may differ from user's entry date)
- Maximum count: `@ticketing_info.wap_so_max`
- All WAPSO are emailed regardless of ticket delivery method

**Example:**
```
User: Jane Ranger (Staff Credential, access_date: Aug 15, access_any_time: true)
  WAPSO #1: John Smith (access_date: Aug 17 10:00 AM)
  WAPSO #2: Mary Jones (access_date: Aug 17 10:00 AM)
```

### Staff Credential as SAP

When a user has a Staff Credential:
- The Staff Credential acts as the Setup Access Pass
- No separate SAP document is issued
- No separate SAP email sent
- Entry date controlled by Staff Credential's `access_date` or `access_any_time`

### Internal Naming: WAP vs SAP

**Historical Context:**
- System internally uses "WAP" (Work Access Pass - legacy term)
- User-facing terminology: "SAP" (Setup Access Pass)
- Code references: `AccessDocument::WAP`, `AccessDocument::WAPSO`
- UI displays: "Setup Access Pass", "SAP"

**Avoid:** Don't use "work" terminology in user-facing content.

### Will Call Legal Name Requirement

All Will Call items are retrieved under the user's legal name as recorded in the system:
- **First Name:** `current_user.first_name`
- **Last Name:** `current_user.last_name`
- **Requirement:** Must match government-issued ID
- **Critical:** Name changes must be updated in profile before ticketing submission

### Access Document Types

The system tracks various document types in the `AccessDocument` model:

```ruby
AccessDocument.type values:
- STAFF_CREDENTIAL
- SPT (Special-Priced Ticket)
- GIFT (Gift Ticket)
- WAP (Setup Access Pass)
- WAPSO (Significant Other SAP)
- VEHICLE_PASS
- VEHICLE_PASS_GIFT
- VEHICLE_PASS_LSD
- LSD (Late Season Directed Ticket)
```

### Delivery Method Codes

```ruby
AccessDocument delivery methods:
- delivery_will_call
- delivery_postal (standard mail)
- delivery_priority (priority mail)
```

### Item States

```ruby
AccessDocument states:
- is_qualified? - User meets requirements
- is_using? - User has claimed this item
- is_banked? - Item is banked for future use
- available? - Item can be claimed
```

---

## Data Model References

### TicketingInfo
Configuration and settings for ticketing system:
- `period` - Current ticketing period
- `spt_cost` - Special-Priced Ticket cost
- `sp_vp_cost` - Special-Priced Vehicle Pass cost
- `spt_credits` - Credits threshold for SPT qualification
- `sc_credits` - Credits threshold for SC qualification
- `wap_default_date` - Default SAP entry date
- `wap_alpha_default_date` - Default Alpha SAP entry date (applicants)
- `wap_so_default_date` - Default Significant Other SAP entry date
- `wap_so_max` - Maximum WAPSO count
- `submit_date` - Ticketing window close date
- `paid_by` - Payment deadline
- `ticket_vendor_name` - External ticketing system name
- `ticket_vendor_email` - External ticketing contact

### TicketAndProvisionsPackage
Wrapper for user's ticket/provision data:
- `access_documents` - All tickets, passes, SAPs
- `provisions` - Meal passes, showers, radios
- `gift_items` - Gift tickets
- `lsd_items` - LSD tickets and passes
- `credits_earned` - User's service credits

### Provisions
User's provision allocations:
- `have_meals` - Boolean, has meal pass
- `meals` - Meal plan details
- `showers` - Boolean, has shower access
- `radios` - Integer, number of event radios qualified for

### AccessDocument
Individual ticket/pass/credential record:
- `type` - Document type (see types above)
- `access_date` - Entry date (for SAPs/SC)
- `access_any_time` - Boolean, unrestricted entry (SC only)
- `expiry_date` - Banking expiration date
- `source_year` - Year item was earned
- `name` - For WAPSO: significant other's name
- Delivery methods and status flags

---

## Business Rules Summary

### Critical Rules
1. **No early entry** - Users will be turned away if arriving before `access_date`
2. **Payment outside Clubhouse** - All paid items processed through Burning Man Ticketing
3. **Legal name for Will Call** - Must match government ID
4. **BMID for meals/showers** - No separate documents; BMID must be active
5. **Non-transferable** - Most items cannot be transferred or sold (Gift Tickets exception)

### User Experience Implications
1. Users need clear warnings about entry date restrictions
2. Pricing information should be visible when claiming
3. Delivery method affects how items are received
4. BMID integration must be explained for provisions
5. Event Radio qualification ≠ allocation guarantee
6. Multiple entry dates (user vs SO) should be explained as normal

---

## FAQ Content Areas

The system maintains FAQ URLs for different topics:
- `@ticketing_info.faqs[:ticketing]` - General ticketing questions
- `@ticketing_info.faqs[:wap]` - Setup Access Pass info
- `@ticketing_info.faqs[:alpha]` - Alpha SAP info (applicants)
- `@ticketing_info.faqs[:vp]` - Vehicle Pass info
- `@ticketing_info.faqs[:provisions]` - Provisions and appreciations

These are external resources maintained separately from the Clubhouse.

---

## Development Notes

### When Building UI
- Always show pricing for SPT/VP when claimed
- Always show entry dates prominently with warnings
- Distinguish between BMID-linked and non-BMID provisions
- Use "wristband" when describing Staff Credential
- Explain that SC acts as SAP (no separate document)
- Clarify payment happens in external system
- Show expiration dates for banked items
- Make transfer restrictions clear

### When Writing Content
- Avoid "work" terminology (use "volunteer", "rangering", "service")
- Use "Setup Access Pass" or "SAP" (not "WAP" in UI)
- Be explicit about "no exceptions" for entry dates
- Explain separate systems (Clubhouse vs Burning Man Ticketing)

### Testing Considerations
- Test all four ticketing periods
- Test with/without various item combinations
- Verify entry date logic for multiple SAPs
- Check BMID vs non-BMID provision displays
- Validate pricing display for SPT+VP combinations
