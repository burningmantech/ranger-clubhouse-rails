# SMSService.php to Ruby Translation Reference

This document maps the PHP `SMSService` class (Laravel) to the Ruby `SmsService` class (Rails).
Use it as a reference when converting other PHP service classes to Ruby.

## Source and Target Files

| | File | Framework |
|---|---|---|
| **PHP Source** | `SMSService.php` (`App\Lib\SMSService`) | Laravel 12 / PHP 8.4 |
| **Ruby Target** | `app/lib/sms_service.rb` (`SmsService`) | Rails 8.1 / ruby 4.0 |

## Class and Exception Mapping

| PHP | Ruby | Notes |
|---|---|---|
| `class SMSException extends Exception` | `class SmsException < StandardError` | Ruby convention: `StandardError` for application errors |
| `class SMSService` | `class SmsService` | Ruby convention: CamelCase without acronyms in caps |
| `const NO_STOP_REPLIES = 1` | `NO_STOP_REPLIES = 1` | Ruby class constant |

## Method Name Mapping

| PHP Method | Ruby Method | Signature Change |
|---|---|---|
| `SMSService::getTokens()` | `SmsService.get_tokens` | Same return: `[sid, auth_token]` |
| `SMSService::broadcast($phoneNumbers, $message)` | `SmsService.broadcast(phone_numbers, message)` | Same params, same return `"sent"` |
| `SMSService::isSMSCapable($phoneNumber)` | `SmsService.sms_capable?(phone_number)` | Ruby predicate method with `?` suffix |
| `SMSService::processIncoming($request)` | `SmsService.process_incoming(params)` | Accepts `params` hash instead of Request object; returns `SmsService::IncomingMessage` instead of stdClass |
| `SMSService::processStatusCallback()` | `SmsService.process_status_callback(params)` | Accepts `params` hash (no global state); returns `SmsService::StatusCallback` instead of array |
| `SMSService::replyResponse($reply)` | `SmsService.reply_response(reply)` | Returns TwiML XML string instead of HTTP Response object |
| `SMSService::normalizePhone($phone)` | `SmsService.normalize_phone(phone)` | Same behavior, uses Phonelib instead of libphonenumber |

## Return Type Conversions (Associative Arrays to Classes)

PHP functions that return associative arrays are converted to named Ruby classes with `attr_reader` accessors and keyword-argument constructors.

### `processIncoming` Return Type

| PHP (associative array / stdClass) | Ruby (`SmsService::IncomingMessage`) |
|---|---|
| `$result->phone` | `result.phone` |
| `$result->message` | `result.message` |
| `$result->raw` | `result.raw` |

### `processStatusCallback` Return Type

| PHP (associative array) | Ruby (`SmsService::StatusCallback`) |
|---|---|
| `$result['status']` | `result.status` |
| `$result['message']` | `result.message` |
| `$result['broadcast_id']` | `result.broadcast_id` |
| `$result['phone']` | `result.phone` |

## Library Substitutions

### Twilio SDK

| PHP (twilio/twilio-php) | Ruby (twilio-ruby) |
|---|---|
| `use Twilio\Rest\Client` | `Twilio::REST::Client` |
| `new Client($sid, $token)` | `Twilio::REST::Client.new(sid, token)` |
| `$client->notify->v1->services($id)->notifications` | `client.notify.v1.services(id).notifications` |
| `$notification->create($params)` | `notification.create(**params)` |
| `$client->lookups->v1->phoneNumbers($num)->fetch(...)` | `client.lookups.v1.phone_numbers(num).fetch(...)` |
| `use Twilio\TwiML\MessagingResponse` | `Twilio::TwiML::MessagingResponse` |
| `$response->message($text)` | `response.message(body: text)` |
| `(string)$response` | `response.to_s` |
| `Twilio\Exceptions\TwilioException` | `Twilio::REST::TwilioError` |
| `Twilio\Exceptions\RestException` | `Twilio::REST::RestError` |
| `$e->getStatusCode()` | `e.status_code` |

### Phone Number Parsing (libphonenumber -> phonelib)

| PHP (libphonenumber-for-php) | Ruby (phonelib gem) |
|---|---|
| `PhoneNumberUtil::getInstance()` | `Phonelib` (module, no instance needed) |
| `$util->parse($phone, $country)` | `Phonelib.parse(phone, country)` |
| `$util->format($parsed, PhoneNumberFormat::E164)` | `parsed.e164` |
| `NumberParseException` catch | Check `parsed.valid?` (phonelib does not raise on invalid input) |
| `$util->isValidNumber($parsed)` | `parsed.valid?` |
| `PhoneNumberFormat::NATIONAL` | `parsed.national` |
| `PhoneNumberFormat::INTERNATIONAL` | `parsed.international` |

### Settings Access

| PHP (Laravel) | Ruby (Rails) |
|---|---|
| `setting('TwilioAccountSID')` | `Setting.get_value(Setting::TWILIO_ACCOUNT_SID)` |
| `setting('TwilioAuthToken')` | `Setting.get_value(Setting::TWILIO_AUTH_TOKEN)` |
| `setting('TwilioServiceId')` | `Setting.get_value(Setting::TWILIO_SERVICE_ID)` |

**Pattern**: The `setting()` helper is only available in controllers/views via `ApplicationHelper`. In `app/lib/` files, use `Setting.get_value(Setting::CONSTANT_NAME)` directly. Setting constants are defined in `app/models/setting.rb`.

## Reusable Translation Patterns

These patterns apply broadly when converting Laravel PHP to Rails Ruby.

### Naming Conventions

| PHP | Ruby |
|---|---|
| `camelCase` methods | `snake_case` methods |
| `SMSService` (acronym caps) | `SmsService` (CamelCase, no acronym caps) |
| `isSomething()` boolean | `something?` predicate method |
| `getSomething()` accessor | `something` (drop the `get` prefix) |

### Static Methods to Class Methods

```php
// PHP
class MyService {
    public static function doWork($arg) { ... }
}
MyService::doWork($arg);
```

```ruby
# Ruby
class MyService
  class << self
    def do_work(arg) ... end
  end
end
MyService.do_work(arg)
```

### Exceptions

```php
// PHP
class MyException extends Exception {}
throw new MyException('message');
try { ... } catch (MyException $e) { ... }
```

```ruby
# Ruby
class MyException < StandardError; end
raise MyException, "message"
begin ... rescue MyException => e ... end
```

### Associative Arrays to Structured Classes

```php
// PHP - returns associative array
return ['name' => $name, 'value' => $value];
```

```ruby
# Ruby - return a named class instance
class MyResult
  attr_reader :name, :value
  def initialize(name:, value:)
    @name = name
    @value = value
  end
end
MyResult.new(name: name, value: value)
```

### Request Data Access

| PHP (Laravel) | Ruby (Rails) |
|---|---|
| `$request->input('FieldName')` | `params[:FieldName]` |
| `$request->all()` | `params.to_unsafe_h` or `params` |
| `Input::get('field')` | `params[:field]` |
| `$_POST` | `request.POST` or `params` |

### String and Array Operations

| PHP | Ruby |
|---|---|
| `empty($var)` | `var.blank?` (Rails) or `var.nil? \|\| var.empty?` |
| `trim($str)` | `str.strip` |
| `explode(',', $str)` | `str.split(",")` |
| `array_chunk($arr, $size)` | `arr.each_slice(size)` |
| `count($arr)` | `arr.length` or `arr.size` |
| `intval($n)` | `n.to_i` |
| `strlen($str)` | `str.length` |
| `str_starts_with($str, $prefix)` | `str.start_with?(prefix)` |
| `preg_replace($pattern, $replacement, $str)` | `str.gsub(pattern, replacement)` |
| `json_encode($data)` | `data.to_json` |
