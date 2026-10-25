# RBS.php to Ruby Translation Reference

This document maps the PHP `RBS` class (Laravel) to the Ruby `Rbs` class (Rails).
Use it as a reference when converting other PHP service classes to Ruby.

## Source and Target Files

| | File | Framework |
|---|---|---|
| **PHP Source** | `RBS.php` (`App\Lib\RBS`) | Laravel 12 / PHP 8.4 |
| **Ruby Target** | `app/lib/rbs.rb` (`Rbs`) | Rails 8.1 / ruby 4.0 |

## Class and Naming Mapping

| PHP | Ruby                                     | Notes |
|---|------------------------------------------|---|
| `class RBS` | `class Rbs`                              | Ruby convention: CamelCase class names without acronyms in all caps |
| `public static function` | `class << self` / `def self.method_name` | Ruby class methods |
| `broadcastSMS` | `broadcast_sms`                          | snake_case method names |
| `broadcastEmail` | `broadcast_email`                        | snake_case method names |
| `broadcastClubhouse` | `broadcast_message`                      | snake_case method names |
| `retryBroadcast` | `retry_broadcast`                        | snake_case method names |
| `retrieveRecipients` | `retrieve_recipients`                    | snake_case method names |
| `eventDates` | `event_dates`                            | snake_case method names |
| `isDuringEvent` | `during_event?`                          | Predicate methods end with `?` |
| `addOnSiteCond` | `add_on_site_cond`                       | snake_case method names |
| `addNotOnDutyJoin` | `add_not_on_duty_join`                   | snake_case method names |
| `addAlertPrefJoin` | `add_alert_pref_join`                    | snake_case method names |
| `clubhouseMessageNotify` | `message_notify`               | snake_case method names |

## Constants Mapping

| PHP | Ruby | Notes |
|---|---|---|
| `const FREQUENT_MUSTER_POSITIONS = [...]` | `FREQUENT_MUSTER_POSITIONS = [...].freeze` | Ruby constants with `.freeze` for immutability |
| `const ATTRIBUTES = [...]` | `ATTRIBUTES = {...}.freeze` | Convert array keys to symbols |
| `const SMS_PREFIX = ''` | `SMS_PREFIX = ""` | Use double quotes |
| `const SMS_SUFFIX = ' TXT STOP to unsub'` | `SMS_SUFFIX = " TXT STOP to unsub"` | Use double quotes |
| `const SMS_LIMIT = 142` | `SMS_LIMIT = 142` | Same |

### New Constants Added in Ruby

These constants were added to replace magic strings in the PHP code:

**SMS Status Constants:**
```ruby
SMS_STATUS_NO_PHONE = "no-phone"
SMS_STATUS_NO_CONTACT = "no-contact"
SMS_STATUS_STOPPED = "stopped"
SMS_STATUS_UNVERIFIED = "unverified"
SMS_STATUS_SENT = "sent"
SMS_STATUS_SERVICE_FAIL = "service-fail"
```

**Email Status Constants:**
```ruby
EMAIL_STATUS_NO_CONTACT = "no-contact"
EMAIL_STATUS_SENT = "sent"
EMAIL_STATUS_SERVICE_FAIL = "service-fail"
```

## Time Handling

| PHP | Ruby | Notes |
|---|---|---|
| `now()` | `Current.time` | Request-scoped current time |
| `Carbon::now()` | `Current.time` | Request-scoped current time |
| `current_year()` | `Current.year` | Request-scoped current year |
| `date('Y-m-d', $timestamp)` | `Time.at(timestamp).strftime("%Y-%m-%d")` | Format timestamp to date string |
| `strtotime($string)` | `Time.zone.parse(string).to_i` or `Date.parse(string).to_time.to_i` | Parse string to timestamp |
| `strtotime("September $year first monday")` | `Date.new(year, 9, 1); labor_day += 1 until labor_day.monday?` | Find first Monday of month |

## Settings Access

| PHP | Ruby | Notes |
|---|---|---|
| `setting('BroadcastSMSSandbox')` | `Setting.get_value(Setting::BROADCAST_SMS_SANDBOX)` | Constants in Setting model |
| `setting('BroadcastMailSandbox')` | `Setting.get_value(Setting::BROADCAST_MAIL_SANDBOX)` | Constants in Setting model |
| `setting('BroadcastClubhouseSandbox')` | `Setting.get_value(Setting::BROADCAST_CLUBHOUSE_SANDBOX)` | Constants in Setting model |
| `setting('BroadcastClubhouseNotify')` | `Setting.get_value(Setting::BROADCAST_CLUBHOUSE_NOTIFY)` | Constants in Setting model |
| `setting('DoNotReplyEmail')` | `EmailAddresses::DO_NOT_REPLY` | Constants in Setting model |
| `config('mail.mailers.smtp')` | N/A - Rails handles via `config/environments/*.rb` | SMTP config in environment files |

## Database Queries

### Basic Query Conversion

| PHP (Laravel) | Ruby (Rails) | Notes |
|---|---|---|
| `DB::table('person')` | `Person.unscoped` or `Person` | ActiveRecord model |
| `->join('table', 'a.id', '=', 'b.id')` | `.joins("INNER JOIN table ON a.id = b.id")` | String joins for complex cases |
| `->leftJoin('table', ...)` | `.left_joins(...)` or `.joins("LEFT JOIN ...")` | Left outer joins |
| `->where('column', 'value')` | `.where(column: "value")` | Hash syntax preferred |
| `->whereIn('column', $array)` | `.where(column: array)` | Array values |
| `->whereNotIn('column', $array)` | `.where.not(column: array)` | Negated array values |
| `->whereNull('column')` | `.where(column: nil)` | Null checks |
| `->whereRaw('SQL')` | `.where("SQL")` | Raw SQL strings |
| `->whereExists(function...)` | `.where("EXISTS (...)")` | Subquery as string |
| `->whereNotExists(function...)` | `.where.not("EXISTS (...)")` | Negated subquery |
| `->whereYear('column', $year)` | `.where("YEAR(column) = ?", year)` | SQL function in string |
| `->whereIntegerInRaw('id', $ids)` | `.where(id: ids)` | ActiveRecord handles this |
| `->select($cols)` | `.select(cols.join(", "))` | Array of column names |
| `->orderBy('column')` | `.order("column")` or `.order(column: :asc)` | Ordering |
| `->get()` | execute | Collection retrieval |
| `->count()` | `.count` | Count records |
| `->update(['key' => 'value'])` | `.update_all(key: "value")` | Batch updates |
| `->pluck('field')` | `.pluck(:field)` | Extract single column |

### Query Building Pattern

PHP builds queries step-by-step:
```php
$sql = DB::table('person');
$sql->where('status', 'active');
if ($condition) {
    $sql->whereIn('id', $ids);
}
$rows = $sql->get();
```

Ruby builds queries the same way:
```ruby
scope = Person.unscoped
scope = scope.where(status: "active")
scope = scope.where(id: ids) if condition
scope
```

## Collections and Arrays

| PHP | Ruby | Notes |
|---|---|---|
| `empty($var)` | `var.blank?` | Rails method (also checks for whitespace strings) |
| `$collection->isEmpty()` | `collection.empty?` | Check if empty |
| `$collection->pluck('field')` | `collection.pluck(:field)` | Extract field values |
| `$collection->toArray()` | `collection` | Convert to array |
| `$collection->filter($fn)` | `collection.select { \|item\| ... }` | Filter collection |
| `$collection->values()` | `collection` | Ruby arrays are already re-indexed |
| `count($array)` | `array.length` or `array.size` | Array length |
| `foreach ($arr as $item)` | `arr.each do \|item\| ... end` | Iteration |
| `$array[] = $value` | `array << value` | Append to array |
| `in_array($value, $array)` | `array.include?(value)` | Check membership |

## String Operations

| PHP | Ruby | Notes |
|---|---|---|
| `empty($phone)` | `phone.blank?` | Rails method |
| `!empty($phone)` | `phone.present?` | Rails method |
| `strlen($str)` | `str.length` | String length |
| `substr($str, $start, $length)` | `str[$start, $length]` | Substring |
| `$str1 . $str2` | `str1 + str2` or string interpolation | Concatenation |

## Object Access

| PHP | Ruby | Notes |
|---|---|---|
| `$person->$smsColumn` | `person.public_send(sms_column)` | Dynamic attribute access |
| `$person->field` | `person.field` | Direct attribute access |
| `$person->field = $value` | `person.field = value` | Attribute assignment |

## Model Operations

### Model Creation

PHP (Laravel):
```php
$pm = new PersonMessage;
$pm->forceFill([...]);
$pm->saveWithoutValidation();
```

Ruby (Rails):
```ruby
pm = PersonMessage.new
pm.assign_attributes(...)
pm.save(validate: false)
```

### Model Updates

PHP:
```php
Broadcast::where('id', $id)->update(['field' => $value]);
```

Ruby:
```ruby
Broadcast.where(id: id).update_all(field: value)
```

### Model Finding

PHP:
```php
$alert = Alert::findOrFail($id);
```

Ruby:
```ruby
alert = Alert.find(alert_id) # Raises if not found
```

## SMS Service Integration

| PHP | Ruby | Notes |
|---|---|---|
| `SMSService::broadcast($phones, $msg)` | `SmsService.broadcast(phones, msg)` | Class name changed to follow Ruby conventions |
| `catch (SMSException $e)` | `rescue SmsException => e` | Exception handling |
| `SMSException` | `SmsException` | Exception class |

## Error Logging

| PHP | Ruby | Notes |
|---|---|---|
| `ErrorLog::recordException($e, $type, $data)` | `ErrorLog.record_exception(e, type, extra: data)` | Keyword argument for extra data |
| `ErrorLog::recordException($e, 'type', ['key' => 'val'])` | `ErrorLog.record_exception(e, "type", extra: { key: "val" })` | Hash with symbol keys |

## Mailer Handling

### PHP (Laravel) - Symfony Mailer

PHP uses Symfony mailer directly:
```php
$mailer = self::setupSMTP();
$emailMessage = self::createEmail($from, $to, $subject, $body);
$sentMessage = $mailer->send($emailMessage);
$messageId = $sentMessage->getMessageId();
```

Or Laravel's mail helper:
```php
mail_send(new ClubhouseNewMessageMail($person, $from, $subject, $message));
```

### Ruby (Rails) - Amazon SES batches

Broadcast email no longer goes through SMTP one person at a time. `Rbs.broadcast_email` (in
`RbsTransmitEmailJob`) and `Rbs.deliver_retried_emails` (in `RbsRetryEmailJob`) draw the email once with
`RbsMailer.broadcast(subject:, rbs_message:, alert:, expires_at:).message`, then send it through Amazon SES
`SendBulkEmail`, up to 50 people a call (`Rbs.deliver_email_batch`). Each person's To line is written by
`Rbs.to_line`, and each email SES takes keeps the id SES gave it, on the `broadcast_message` row and in `mail_log`.
See `docs/FEATURES.md` (RBS › Broadcast emails) for the modes, the sandbox and the test address.

New Clubhouse message alerts still go through ActionMailer:
```ruby
ClubhouseNewMessageMailer.notify(person:, from:, subject:, message:).deliver_later
```

## Exception Handling

### PHP

```php
try {
    $status = SMSService::broadcast($phoneNumbers, $message);
} catch (SMSException $e) {
    ErrorLog::recordException($e, 'type', ['data' => $value]);
    $status = Broadcast::STATUS_SERVICE_FAIL;
}
```

### Ruby

```ruby
begin
  status = SmsService.broadcast(phone_numbers, message)
rescue SmsException => e
  ErrorLog.record_exception(e, "type", extra: { data: value })
  status = Broadcast::STATUS_SERVICE_FAIL
end
```

## Type Conversions

| PHP | Ruby | Notes |
|---|---|---|
| `(object)['key' => 'val']` | `OpenStruct.new(key: "val")` | Anonymous objects |
| `['key' => 'value']` | `{ key: "value" }` | Hashes with symbol keys |
| `(string)$obj` | `obj.to_s` | Convert to string |
| `(int)$val` | `val.to_i` | Convert to integer |
| `(bool)$val` | `!!val` or use truthiness | Convert to boolean |

## Person Status Constants

| PHP | Ruby | Notes |
|---|---|---|
| `Person::ACTIVE` | `Person::ACTIVE` | Same constant name |
| `Person::NO_MESSAGES_STATUSES` | `Person::NO_MESSAGES_STATUSES` | Same constant name |

## Return Values

### PHP - Multiple Return Values

```php
return [$sent, $fails];
```

### Ruby - Multiple Return Values

```ruby
[sent, fails]
```

Usage:
```ruby
sent, fails = broadcast_sms(alert, broadcast_id, sender_id, people, message)
```

## Model Associations & Methods

Models that don't exist yet are referenced but not created. These will work once models are created:

| Model | Method | Notes |
|---|---|---|
| `Broadcast` | `.where(id:).update_all(...)` | Standard ActiveRecord |
| `BroadcastMessage` | `.record(...)` | Class method (to be created) |
| `BroadcastMessage` | `.count_fail(broadcast_id, type)` | Class method (to be created) |
| `Alert` | `.find(id)` | Standard ActiveRecord |
| `PersonAlert` | `.find_alert_for_person(alert_id, person_id)` | Class method (to be created) |
| `MailLog` | `.create(...)` | Standard ActiveRecord |
| `PersonMessage` | `new` / `assign_attributes` / `save` | Standard ActiveRecord |
| `Position` | Constants like `Position::TRAINING` | To be defined in model |

## Additional Ruby Idioms

### Array Building

PHP:
```php
$recipients = [];
foreach ($people as $person) {
    $recipients[] = (object)[
        'person' => $person,
        'phone' => $phone,
    ];
}
```

Ruby:
```ruby
recipients = []
people.each do |person|
  recipients << OpenStruct.new(person: person, phone: phone)
end
```

### Conditional Assignment

PHP:
```php
$firstName = empty($person->preferred_name) ? $person->first_name : $person->preferred_name;
```

Ruby:
```ruby
first_name = person.preferred_name.presence || person.first_name
```

### Checking Array Membership

PHP:
```php
if (in_array($person->status, Person::NO_MESSAGES_STATUSES))
```

Ruby:
```ruby
if Person::NO_MESSAGES_STATUSES.include?(person.status)
```

## Summary of Key Patterns

1. **Class Names**: PHP acronyms (SMS, RBS) → Ruby CamelCase (Sms, Rbs)
2. **Method Names**: camelCase → snake_case, predicates end with `?`
3. **Time**: `now()` / `Carbon::now()` → `Current.time`
4. **Settings**: `setting('Name')` → `Setting.get_value(Setting::NAME)`
5. **Database**: `DB::table()` → `Model.unscoped` or `Model`
6. **Collections**: `->method()` → `.method`
7. **Strings**: `empty()` → `.blank?`, `!empty()` → `.present?`
8. **Constants**: Add `SMS_STATUS_*` and `EMAIL_STATUS_*` constants
9. **Mailers**: Broadcast email is drawn once by `RbsMailer.broadcast(...).message` and sent through SES by `Rbs.deliver_email_batch`; only `ClubhouseNewMessageMailer` uses `deliver_later`
10. **Error Logging**: `ErrorLog::recordException()` → `ErrorLog.record_exception()` with keyword args
