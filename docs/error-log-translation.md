# ErrorLog.php to Ruby Translation Reference

This document maps the PHP `ErrorLog` class (Laravel) to the Ruby `ErrorLog` class (Rails).
Use it as a reference when converting other PHP model classes that interact with ErrorLog methods.

## Source and Target Files

| | File | Framework |
|---|---|---|
| **PHP Source** | `ErrorLog.php` (`App\Models\ErrorLog`) | Laravel 12 / PHP 8.4 |
| **Ruby Target** | `app/models/error_log.rb` (`ErrorLog`) | Rails 8.1 / ruby 4.0 |

## Class Mapping

| PHP | Ruby | Notes |
|---|---|---|
| `class ErrorLog extends ApiModel` | `class ErrorLog < ApplicationRecord` | Standard Rails model base class |
| `const PAGE_SIZE_DEFAULT = 50` | `PAGE_SIZE_DEFAULT = 50` | Same constant |
| `protected $guarded = []` | _(not needed)_ | Rails models don't mass-assign by default; use strong parameters in controllers |
| `public function person(): BelongsTo` | `belongs_to :person, optional: true` | Association declaration |

## Method Name Mapping

| PHP Method | Ruby Method | Signature Change |
|---|---|---|
| `ErrorLog::record($error_type, $data = [])` | `ErrorLog.record(error_type, data: {}, request: nil)` | `request` is now an explicit keyword parameter instead of using global `request()` helper |
| `ErrorLog::recordException($e, $error_type, $extra = [])` | `ErrorLog.record_exception(exception, error_type, extra: {}, request: nil)` | `exception` instead of `$e`; `request` explicit parameter |
| `ErrorLog::findForQuery($query)` | `ErrorLog.find_for_query(query)` | Uses Pagy instead of manual offset/limit; signature unchanged |

## Method Details

### `record` Method

**PHP (Laravel):**
```php
ErrorLog::record('error-type', ['key' => 'value']);
// Implicitly accesses request() helper
```

**Ruby (Rails):**
```ruby
ErrorLog.record("error-type", data: { key: "value" }, request: request)
# Requires explicit request parameter
```

**Changes:**
- `$error_type` (positional) → `error_type` (positional, snake_case)
- `$data = []` (positional) → `data: {}` (keyword argument)
- Implicit `request()` → Explicit `request: nil` (keyword argument)
- `$req->method()` → `request.method`
- `$req->all()` → `request.params.to_unsafe_h`
- `$req->getClientIp()` → `request.remote_ip`
- `$req->userAgent()` → `request.user_agent`
- `$req->fullUrl()` → `request.original_url`

### `record_exception` Method

**PHP (Laravel):**
```php
try {
    // code
} catch (Exception $e) {
    ErrorLog::recordException($e, 'exception-type', ['extra' => 'data']);
}
```

**Ruby (Rails):**
```ruby
begin
  # code
rescue StandardError => e
  ErrorLog.record_exception(e, "exception-type", extra: { extra: "data" }, request: request)
end
```

**Changes:**
- `Throwable $e` → `Exception exception` (Ruby exceptions inherit from `Exception`)
- `$error_type` → `error_type`
- `$extra = []` → `extra: {}`
- Explicit `request: nil` parameter added
- `$e->getTrace()` → `exception.backtrace` (Ruby backtraces don't include args by default)
- `$e->getMessage()` → `exception.message`
- `$e->getFile()` → Extracted from `exception.backtrace.first.split(":")[0]`
- `$e->getLine()` → Extracted from `exception.backtrace.first.split(":")[1]`

### `find_for_query` Method

**PHP (Laravel):**
```php
$result = ErrorLog::findForQuery([
    'person_id' => 123,
    'error_type' => 'api-error',
    'page' => 2,
    'page_size' => 25
]);
// Returns: ['error_logs' => [...], 'meta' => [...]]
```

**Ruby (Rails):**
```ruby
result = ErrorLog.find_for_query(
  person_id: 123,
  error_type: "api-error",
  page: 2,
  page_size: 25
)
# Returns: { error_logs: [...], meta: {...} }
```

**Changes:**
- Uses Pagy v43 for pagination instead of manual `offset()` and `limit()`
- Return structure is the same: `{ error_logs:, meta: { total:, total_pages:, page_size:, page: } }`
- Query parameter keys remain the same (symbols instead of strings)

## Pagination: Manual Offset/Limit to Pagy

### PHP (Laravel Manual Pagination)

```php
$total = $sql->count();
$pageSize = (int)($query['page_size'] ?? self::PAGE_SIZE_DEFAULT);
$page = (int)($query['page'] ?? 1);
$page = $page - 1;

$sql = $sql->offset($page * $pageSize)->limit($pageSize);
$rows = $sql->with('person:id,callsign')->get();

return [
    'error_logs' => $rows,
    'meta' => [
        'total' => $total,
        'total_pages' => (int)(($total + ($pageSize - 1)) / $pageSize),
        'page_size' => $pageSize,
        'page' => $page + 1,
    ]
];
```

### Ruby (Rails with Pagy)

```ruby
# Include Pagy::Method in class << self block
class << self
  include Pagy::Method
  
  def find_for_query(query)
    scope = all.includes(:person)
    # ... apply filters ...
    
    page = (query[:page] || 1).to_i
    page_size = (query[:page_size] || PAGE_SIZE_DEFAULT).to_i
    
    # Use Pagy with minimal request hash (models don't have self.request)
    pagy_instance, records = pagy(:offset, scope, page: page, limit: page_size, request: { params: {} })
    
    {
      error_logs: records,
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

**Key Differences:**
- Pagy handles offset/limit calculation automatically
- `pagy(:offset, scope, page:, limit:, request:)` returns `[pagy_instance, records]`
- `request: { params: {} }` is required in models (no `self.request` available)
- Pagy provides `.count`, `.pages`, `.limit`, `.page` methods on the instance

## Auth Mapping

| PHP (Laravel) | Ruby (Rails) | Notes |
|---|---|---|
| `Auth::check()` | `Current.person` | Check if a person is authenticated |
| `Auth::id()` | `Current.person&.id` | Get authenticated person's ID (safe navigation) |
| `if (Auth::check()) { ... }` | `if Current.person { ... }` | Conditional authentication check |

**Example in context:**

```php
// PHP
if (Auth::check()) {
    $error['person_id'] = Auth::id();
}
```

```ruby
# Ruby
if Current.person
  error[:person_id] = Current.person.id
end
```

## Exception Handling

| PHP (Laravel) | Ruby (Rails) | Notes |
|---|---|---|
| `use Illuminate\Database\QueryException` | `ActiveRecord::StatementInvalid` | Database exception class |
| `try { ... } catch (QueryException $e) { ... }` | `begin ... rescue ActiveRecord::StatementInvalid => e ... end` | Exception handling syntax |
| `self::create($error)` | `create!(error)` | Model creation (raises on failure) |

**Example:**

```php
// PHP
try {
    self::create($error);
} catch (QueryException $e) {
    // Log::emergency("error log create exception ".$e->getMessage());
}
```

```ruby
# Ruby
begin
  create!(error)
rescue ActiveRecord::StatementInvalid => e
  # Silently fail if database error occurs while logging
end
```

## Laravel Eloquent to ActiveRecord Query Builder

| PHP (Laravel Eloquent) | Ruby (Rails ActiveRecord) | Notes                               |
|---|---|-------------------------------------|
| `self::query()` | `all` | Start a query scope                 |
| `$sql->where('column', $value)` | `scope.where(column: value)` | Simple where clause                 |
| `$sql->where('column', '>=', $value)` | `scope.where("column >= ?", value)` | Comparison where clause             |
| `$sql->whereRaw('created_at >= DATE_SUB(?, INTERVAL 1 DAY)', [now()])` | `scope.where("created_at >= ?", 1.day.ago)` | Raw SQL to ActiveRecord             |
| `$sql->orderBy('created_at', 'desc')` | `scope.order(created_at: :desc)` | Order by clause                     |
| `$sql->with('person:id,callsign')` | `scope.includes(:person)` | Eager loading association           |
| `$sql->get()` | `scope` | Execute query and return rows       |
| `$sql->count()` | `scope.count` | Count records                       |
| `self::create($attrs)` | `create!(attrs)` | Create record (! raises on failure) |
| `isset($query['key'])` | `query[:key].present?` | Check if parameter exists           |

## Query Parameter Mapping

### `find_for_query` Parameters

| Parameter | Type | Description | PHP Check | Ruby Check |
|---|---|---|---|---|
| `person_id` | Integer | Filter by person ID | `isset($query['person_id'])` | `query[:person_id].present?` |
| `error_type` | String | Filter by error type | `isset($query['error_type'])` | `query[:error_type].present?` |
| `start_at` | DateTime | Errors on or after | `isset($query['start_at'])` | `query[:start_at].present?` |
| `ends_at` | DateTime | Errors on or before | `isset($query['ends_at'])` | `query[:ends_at].present?` |
| `last_day` | Boolean | Last 24 hours | `isset($query['last_day'])` | `query[:last_day]` |
| `sort` | String | Sort order ('asc'/'desc') | `isset($query['sort'])` | `query[:sort]` |
| `page` | Integer | Page number (1-based) | `$query['page'] ?? 1` | `query[:page] || 1` |
| `page_size` | Integer | Items per page | `$query['page_size'] ?? PAGE_SIZE_DEFAULT` | `query[:page_size] || PAGE_SIZE_DEFAULT` |

## Return Type Structure

Both PHP and Ruby versions return the same hash structure:

```ruby
{
  error_logs: [<ErrorLog>, <ErrorLog>, ...],
  meta: {
    total: 142,           # Total number of records matching filters
    total_pages: 6,       # Total number of pages
    page_size: 25,        # Items per page
    page: 2               # Current page number (1-based)
  }
}
```

**Note:** Ruby uses symbols for hash keys (`:error_logs`, `:meta`) while PHP uses strings.

## JSON Serialization

| PHP (Laravel) | Ruby (Rails) | Notes |
|---|---|---|
| `json_encode($data)` | `data.to_json` | Convert to JSON string |
| `json_encode($data, JSON_INVALID_UTF8_SUBSTITUTE \| JSON_UNESCAPED_UNICODE)` | `data.to_json` | Rails handles UTF-8 properly by default |
| `protected $casts = ['data' => 'array']` | `serialize :data, coder: JSON` | Automatic JSON serialization for database column |

## Request Object Methods

| PHP (Laravel) | Ruby (Rails) | Returns |
|---|---|---|
| `request()` | `request` (parameter) | Request object (must be passed explicitly in models) |
| `$request->method()` | `request.method` | HTTP method ("GET", "POST", etc.) |
| `$request->all()` | `request.params.to_unsafe_h` | All request parameters as hash |
| `$request->getClientIp()` | `request.remote_ip` | Client IP address |
| `$request->userAgent()` | `request.user_agent` | User agent string |
| `$request->fullUrl()` | `request.original_url` | Full URL with query string |

## Common Translation Patterns

### Model Constants

```php
// PHP
class ErrorLog extends ApiModel {
    const PAGE_SIZE_DEFAULT = 50;
}
```

```ruby
# Ruby
class ErrorLog < ApplicationRecord
  PAGE_SIZE_DEFAULT = 50
end
```

### Associations

```php
// PHP
public function person(): BelongsTo {
    return $this->belongsTo(Person::class);
}
```

```ruby
# Ruby
belongs_to :person, optional: true
```

### Class Methods

```php
// PHP
class ErrorLog extends ApiModel {
    public static function record($error_type, $data = []) {
        // ...
    }
}
```

```ruby
# Ruby
class ErrorLog < ApplicationRecord
  class << self
    def record(error_type, data: {}, request: nil)
      # ...
    end
  end
end
```

## Migration Notes

When converting code that calls `ErrorLog` methods:

1. **Always pass `request` explicitly** - Models cannot access the global `request()` helper
2. **Use symbols for hash keys** - Ruby convention uses symbols (`:person_id`) instead of strings
3. **Use keyword arguments** - `data:` and `extra:` are keyword arguments, not positional
4. **Check for `Current.person`** - Instead of `Auth::check()` or `Auth::id()`
5. **Rescue `ActiveRecord::StatementInvalid`** - Instead of catching `QueryException`
6. **Use `create!` with bang** - Rails convention for methods that raise on failure
