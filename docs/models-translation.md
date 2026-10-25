# Laravel Models to Rails Translation Reference

This document maps Laravel 12 PHP models to Rails 8.1 Ruby models.
Use it as a reference when converting other PHP model classes to Ruby.

## Source and Target Files

| PHP Source | Ruby Target |
|------------|-------------|
| `Alert.php` | `app/models/alert.rb` |
| `AlertPerson.php` | `app/models/person_alert.rb` |
| `Broadcast.php` | `app/models/broadcast.rb` |
| `BroadcastMessage.php` | `app/models/broadcast_message.rb` |
| `MailLog.php` | `app/models/mail_log.rb` |

## Class and Method Naming

### Class Names

| PHP | Ruby | Notes |
|-----|------|-------|
| `class Alert extends ApiModel` | `class Alert < ApplicationRecord` | Standard Rails model |
| `class AlertPerson extends ApiModel` | `class PersonAlert < ApplicationRecord` | Standard Rails model |
| `class Broadcast extends ApiModel` | `class Broadcast < ApplicationRecord` | Standard Rails model |
| `class BroadcastMessage extends ApiModel` | `class BroadcastMessage < ApplicationRecord` | Standard Rails model |
| `class MailLog extends ApiModel` | `class MailLog < ApplicationRecord` | Standard Rails model |

### Method Name Mappings

| PHP (camelCase) | Ruby (snake_case) | Model |
|-----------------|-------------------|-------|
| `findAll()` | `find_all` | Alert |
| `getSmsOnlyAttribute()` | `sms_only` | Alert |
| `getEmailOnlyAttribute()` | `email_only` | Alert |
| `getNoOptOutAttribute()` | `no_opt_out` | Alert |
| `findAllForPerson()` | `find_all_for_person` | PersonAlert |
| `findOrCreateForPerson()` | `find_or_create_for_person` | PersonAlert |
| `findAlertForPerson()` | `find_alert_for_person` | PersonAlert |
| `allowEmailForAlert()` | `allow_email_for_alert?` | PersonAlert |
| `findWithFailedMessages()` | `find_with_failed_messages` | Broadcast |
| `findLogs()` | `find_logs` | Broadcast |
| `getPeopleAttribute()` | `people` (attr_accessor) | Broadcast |
| `findUnknownPhonesForYear()` | `find_unknown_phones_for_year` | BroadcastMessage |
| `retrieveUnknownPhonesForDailyReport()` | `retrieve_unknown_phones_for_daily_report` | BroadcastMessage |
| `findForQuery()` | `find_for_query` | BroadcastMessage, MailLog |
| `record()` | `record` | BroadcastMessage |
| `countFail()` | `count_fail` | BroadcastMessage |
| `findForProspectiveApplication()` | `find_for_prospective_application` | MailLog |
| `retrieveYears()` | `retrieve_years` | MailLog |
| `countStats()` | `count_for_period`, `count_for_year` | MailLog |
| `retrieveStats()` | `retrieve_stats` | MailLog |
| `markAsBounced()` | `mark_as_bounced` | MailLog |
| `markAsComplaint()` | `mark_as_complaint` | MailLog |
| `setBodyAttribute()` | `body=` | MailLog |
| `getSubjectAttribute()` | `subject` | MailLog |
| `getBodyAttribute()` | `body` | MailLog |

## Constants

### Alert Constants

| PHP | Ruby |
|-----|------|
| `const int SHIFT_CHANGE = 1` | `SHIFT_CHANGE = 1` |
| `const int SHIFT_MUSTER = 2` | `SHIFT_MUSTER = 2` |
| `const int EMERGENCY_BROADCAST = 3` | `EMERGENCY_BROADCAST = 3` |
| `const int RANGER_SOCIALS = 4` | `RANGER_SOCIALS = 4` |
| `const int TICKETING = 5` | `TICKETING = 5` |
| `const int ON_SHIFT = 6` | `ON_SHIFT = 6` |
| `const int TRAINING = 7` | `TRAINING = 7` |
| `const int CLUBHOUSE_NOTIFY_ON_PLAYA = 8` | `CLUBHOUSE_NOTIFY_ON_PLAYA = 8` |
| `const int CLUBHOUSE_NOTIFY_PRE_EVENT = 9` | `CLUBHOUSE_NOTIFY_PRE_EVENT = 9` |
| `const int SHIFT_CHANGE_PRE_EVENT = 10` | `SHIFT_CHANGE_PRE_EVENT = 10` |
| `const int SHIFT_MUSTER_PRE_EVENT = 11` | `SHIFT_MUSTER_PRE_EVENT = 11` |
| `const int RANGER_CONTACT = 12` | `RANGER_CONTACT = 12` |
| `const int MENTOR_CONTACT = 13` | `MENTOR_CONTACT = 13` |

### Broadcast Type Constants

| PHP | Ruby |
|-----|------|
| `const string TYPE_GENERAL = 'general'` | `TYPE_GENERAL = "general"` |
| `const string TYPE_SLOT_EDIT = 'slot-edit'` | `TYPE_SLOT_EDIT = "slot-edit"` |
| `const string TYPE_POSITION = 'position'` | `TYPE_POSITION = "position"` |
| `const string TYPE_SLOT = 'slot'` | `TYPE_SLOT = "slot"` |
| `const string TYPE_ONSHIFT = 'onshift'` | `TYPE_ONSHIFT = "onshift"` |
| `const string TYPE_RECRUIT_DIRT = 'recruit-dirt'` | `TYPE_RECRUIT_DIRT = "recruit-dirt"` |
| `const string TYPE_RECRUIT_POSITION = 'recruit-position'` | `TYPE_RECRUIT_POSITION = "recruit-position"` |
| `const string TYPE_EMERGENCY = 'emergency'` | `TYPE_EMERGENCY = "emergency"` |

### Broadcast Status Constants

| PHP | Ruby |
|-----|------|
| `const string STATUS_SENT = 'sent'` | `STATUS_SENT = "sent"` |
| `const string STATUS_SERVICE_FAIL = 'service-fail'` | `STATUS_SERVICE_FAIL = "service-fail"` |
| `const string STATUS_VERIFY = 'verify'` | `STATUS_VERIFY = "verify"` |
| `const string STATUS_STOP = 'stop'` | `STATUS_STOP = "stop"` |
| `const string STATUS_START = 'start'` | `STATUS_START = "start"` |
| `const string STATUS_HELP = 'help'` | `STATUS_HELP = "help"` |
| `const string STATUS_STATS = 'stats'` | `STATUS_STATS = "stats"` |
| `const string STATUS_NEXT = 'next'` | `STATUS_NEXT = "next"` |
| `const string STATUS_UNKNOWN_COMMAND = 'unknown-command'` | `STATUS_UNKNOWN_COMMAND = "unknown-command"` |
| `const string STATUS_UNKNOWN_PHONE = 'unknown-phone'` | `STATUS_UNKNOWN_PHONE = "unknown-phone"` |
| `const string STATUS_REPLY = 'reply'` | `STATUS_REPLY = "reply"` |
| `const string STATUS_BOUNCED = 'bounced'` | `STATUS_BOUNCED = "bounced"` |
| `const string STATUS_BLOCKED = 'blocked'` | `STATUS_BLOCKED = "blocked"` |

### Pagination Constants

| PHP | Ruby |
|-----|------|
| `const int DEFAULT_PAGE_SIZE = 50` | `PAGE_SIZE_DEFAULT = 50` |
| `const int PAGE_SIZE_DEFAULT = 50` | `PAGE_SIZE_DEFAULT = 50` |

## Relationships (Associations)

### Laravel to Rails Association Mapping

| PHP (Laravel) | Ruby (Rails) | Notes |
|---------------|--------------|-------|
| `belongsTo(Person::class)` | `belongs_to :person` | Standard belongs_to |
| `belongsTo(Person::class)` as sender | `belongs_to :sender, class_name: "Person"` | Custom foreign key |
| `belongsTo(Alert::class)` | `belongs_to :alert` | Standard belongs_to |
| `hasMany(BroadcastMessage::class)` | `has_many :broadcast_message` | Singular table name |
| `hasMany(...)->where('status', ...)` | `has_many :failed_messages, -> { where(...) }` | Scoped association |

### By Model

**Alert:**
```ruby
has_many :person_alert, dependent: :delete_all
has_many :broadcast
```

**PersonAlert:**
```ruby
belongs_to :person
belongs_to :alert
```

**Broadcast:**
```ruby
belongs_to :sender, class_name: "Person", optional: true
belongs_to :retry_person, class_name: "Person", optional: true
belongs_to :alert, optional: true
has_many :broadcast_message, dependent: :destroy
has_many :failed_messages, -> { where(status: STATUS_SERVICE_FAIL) }, class_name: "BroadcastMessage"
```

**BroadcastMessage:**
```ruby
belongs_to :person, optional: true
belongs_to :broadcast, optional: true
```

**MailLog:**
```ruby
belongs_to :broadcast, optional: true
belongs_to :sender, class_name: "Person", optional: true
belongs_to :person, optional: true
belongs_to :prospective_application, optional: true
```

## Accessors and Mutators

### PHP Accessors → Ruby Methods

PHP uses `get*Attribute()` methods that are automatically called when accessing properties:

```php
public function getSmsOnlyAttribute() {
    return ($this->id == Alert::ON_SHIFT);
}
```

Ruby uses standard method definitions:

```ruby
def sms_only
  id == ON_SHIFT
end
```

### PHP Mutators → Ruby Setters

PHP uses `set*Attribute()` methods:

```php
public function setBodyAttribute($value) {
    $this->attributes['body'] = !empty($value) ? gzencode($value) : '';
}
```

Ruby overrides the setter:

```ruby
def body=(value)
  compressed = value.present? ? ActiveSupport::Gzip.compress(value) : ""
  write_attribute(:body, compressed)
end
```

### Complex Getter with Fallback

PHP:
```php
public function getSubjectAttribute(): string {
    if ($this->broadcast_id) {
        return $this->broadcast?->subject ?? '';
    }
    return $this->attributes['subject'];
}
```

Ruby:
```ruby
def subject
  return broadcast&.subject || "" if broadcast_id.present?
  read_attribute(:subject)
end
```

## Time Handling

| PHP | Ruby | Notes |
|-----|------|-------|
| `now()` | `Current.time` | Request-scoped current time |
| `now()->subHours(24)` | `Current.time - 24.hours` | 24 hours ago |
| `now()->subDay(1)` | `Current.time - 1.day` | 1 day ago |
| `now()->subDays(7)` | `Current.time - 7.days` | 7 days ago |
| `current_year()` | `Current.year` | Request-scoped current year |
| `whereYear('created_at', $year)` | `where("YEAR(created_at) = ?", year)` | Year filter in SQL |
| `DATE_SUB(?, INTERVAL 1 DAY)` | `Current.time - 1.day` | Date subtraction |

## Query Patterns

### Basic Query Building

PHP:
```php
$sql = self::query();
$sql->where('status', $status);
$sql->whereYear('created_at', $year);
$rows = $sql->get();
```

Ruby:
```ruby
scope = all
scope = scope.where(status: status)
scope = scope.where("YEAR(created_at) = ?", year)
```

### Complex JOIN with Condition

PHP:
```php
Alert::select(...)->leftJoin('alert_person', function ($join) use ($personId) {
    $join->where('alert_person.person_id', '=', $personId);
    $join->whereRaw('alert_person.alert_id=alert.id');
})->get();
```

Ruby:
```ruby
Alert
  .select(...)
  .joins(
    sanitize_sql_array([
      "LEFT JOIN person_alert ON person_alert.alert_id = alert.id AND person_alert.person_id = ?",
      person_id
    ])
  )
```

### Computed Columns in SELECT

PHP:
```php
DB::raw('IFNULL(use_sms, 1) as use_sms')
```

Ruby:
```ruby
.select("IFNULL(person_alert.use_sms, 1) as use_sms")
```

With virtual attribute definition:
```ruby
attribute :use_sms, :boolean
```

### OR Conditions

PHP:
```php
$sql->where(function ($q) use ($personId) {
    $q->where('person_id', $personId);
    $q->orWhere('sender_id', $personId);
});
```

Ruby:
```ruby
scope.where("person_id = ? OR sender_id = ?", person_id, person_id)
```

### Scoped Associations

PHP:
```php
public function failed_messages(): HasMany {
    return $this->hasMany(BroadcastMessage::class)->where('status', Broadcast::STATUS_SERVICE_FAIL);
}
```

Ruby:
```ruby
has_many :failed_messages,
         -> { where(status: STATUS_SERVICE_FAIL) },
         class_name: "BroadcastMessage"
```

## Pagination

### Manual Pagination → Pagy Gem

PHP (manual):
```php
$page = (int)($query['page'] ?? 1);
$pageSize = (int)($query['page_size'] ?? self::PAGE_SIZE_DEFAULT);
$total = $sql->count();
$sql->offset(($page - 1) * $pageSize)->limit($pageSize);
$rows = $sql->get();

return [
    'messages' => $rows,
    'total' => $total,
    'total_pages' => (int)(($total + ($pageSize - 1)) / $pageSize),
    'page_size' => $pageSize,
    'page' => $page,
];
```

Ruby (Pagy):
```ruby
class << self
  include Pagy::Method

  def find_for_query(query)
    page = (query[:page] || 1).to_i
    page_size = (query[:page_size] || PAGE_SIZE_DEFAULT).to_i

    scope = all # build your query

    pagy_instance, records = pagy(:offset, scope, page: page, limit: page_size, request: { params: {} })

    {
      messages: records,
      meta: {
        total: pagy_instance.count,
        total_pages: pagy_instance.pages,
        page_size: pagy_instance.limit,
        page: pagy_instance.page
      }
    }
  end
end
```

## Compression (Gzip)

### PHP gzencode → Ruby ActiveSupport::Gzip

PHP setter:
```php
public function setBodyAttribute($value) {
    $this->attributes['body'] = !empty($value) ? gzencode($value) : '';
}
```

Ruby setter:
```ruby
def body=(value)
  compressed = value.present? ? ActiveSupport::Gzip.compress(value) : ""
  write_attribute(:body, compressed)
end
```

PHP getter:
```php
$body = gzdecode($this->attributes['body']);
```

Ruby getter:
```ruby
body_text = ActiveSupport::Gzip.decompress(raw_body)
```

### Quoted-Printable Decoding

PHP:
```php
if (preg_match("/=3d/i", $body)) {
    $body = quoted_printable_decode($body);
}
```

Ruby:
```ruby
if body_text =~ /=3d/i
  body_text.unpack1("M")
else
  body_text
end
```

## Virtual Attributes

### For Computed SQL Columns

When SELECT includes computed columns like `IFNULL(use_sms, 1) as use_sms`:

```ruby
attribute :use_sms, :boolean
attribute :use_email, :boolean
```

### For Dynamically Set Properties

PHP:
```php
public $people;
protected $appends = ['people'];
```

Ruby:
```ruby
attr_accessor :people
```

## Model Validations

PHP:
```php
protected $rules = [
    'title' => 'required|string',
    'description' => 'required|string',
    'on_playa' => 'boolean'
];
```

Ruby:
```ruby
validates :title, presence: true
validates :description, presence: true
```

## Table Configuration

PHP:
```php
protected $table = 'alert';
```

Ruby:
```ruby
self.table_name = "alert"
```

## Eager Loading

PHP:
```php
$sql->with(['person:id,callsign', 'sender:id,callsign', 'broadcast']);
```

Ruby:
```ruby
scope.includes(:person, :sender, :broadcast)
```

## Summary of Key Patterns

1. **Class Names**: Same names, extend `ApplicationRecord` instead of `ApiModel`
2. **Method Names**: camelCase → snake_case, predicates end with `?`
3. **Constants**: Remove type hints, use `=` instead of `const`
4. **Time**: `now()` → `Current.time`, `current_year()` → `Current.year`
5. **Relationships**: `belongsTo` → `belongs_to`, `hasMany` → `has_many`
6. **Accessors**: `get*Attribute()` → plain method
7. **Mutators**: `set*Attribute()` → setter method with `=`
8. **Queries**: Use ActiveRecord methods, SQL strings for complex expressions
9. **Pagination**: Manual offset/limit → Pagy gem with `Pagy::Method`
10. **Compression**: `gzencode/gzdecode` → `ActiveSupport::Gzip.compress/decompress`
