# Laravel to Rails Mailer Translation Guide

This document describes the conversion of Laravel 12 mailer classes and Blade templates to Rails 8.1 ActionMailer classes and ERB views.

## Overview

| Category | Laravel | Rails |
|----------|---------|-------|
| Base mailer classes | 2 | 2 |
| Main mailers | 26 | 26 |
| ProspectiveApplication mailers | 13 | 13 |
| Total mailer classes | 41 | 41 |
| View templates | 40 | 40 |

## File Mapping

### Base Mailers

| Laravel | Rails |
|---------|-------|
| `ClubhouseMailable.php` | `app/mailers/clubhouse_mailer.rb` |
| `ProspectiveApplicationMail.php` | `app/mailers/prospective_application_mailer.rb` |

### Main Mailers (26)

| Laravel Source | Rails Target |
|----------------|--------------|
| `AccountCreationMail.php` | `app/mailers/account_creation_mailer.rb` |
| `AlertWhenSignUpsEmptyMail.php` | `app/mailers/alert_when_sign_ups_empty_mailer.rb` |
| `AutomaticActiveConversionMail.php` | `app/mailers/automatic_active_conversion_mailer.rb` |
| `AutomaticSignOutMail.php` | `app/mailers/automatic_sign_out_mailer.rb` |
| `ClubhouseNewMessageMail.php` | `app/mailers/clubhouse_new_message_mailer.rb` |
| `ContactMail.php` | `app/mailers/contact_mailer.rb` |
| `DailyReportMail.php` | `app/mailers/daily_report_mailer.rb` |
| `ExpiredHandleReservationsMail.php` | `app/mailers/expired_handle_reservations_mailer.rb` |
| `NotifyVCEmailChangeMail.php` | `app/mailers/notify_vc_email_change_mailer.rb` |
| `OnlineCourseCompletedMail.php` | `app/mailers/online_course_completed_mailer.rb` |
| `OnlineCourseEnrollmentMail.php` | `app/mailers/online_course_enrollment_mailer.rb` |
| `OnlineCourseResetPasswordMail.php` | `app/mailers/online_course_reset_password_mailer.rb` |
| `PhotoApprovedMail.php` | `app/mailers/photo_approved_mailer.rb` |
| `PhotoPendingMail.php` | `app/mailers/photo_pending_mailer.rb` |
| `PhotoRejectedMail.php` | `app/mailers/photo_rejected_mailer.rb` |
| `PhotosExpiredMail.php` | `app/mailers/photos_expired_mailer.rb` |
| `RangersWhoNeedWorkAccessPassesMail.php` | `app/mailers/rangers_who_need_waps_mailer.rb` |
| `RBSMail.php` | `app/mailers/rbs_mailer.rb` |
| `ResetPasswordMail.php` | `app/mailers/reset_password_mailer.rb` |
| `TestMail.php` | `app/mailers/test_mailer.rb` |
| `TrainerReminderMail.php` | `app/mailers/trainer_reminder_mailer.rb` |
| `TrainingSessionFullMail.php` | `app/mailers/training_session_full_mailer.rb` |
| `TrainingSignupMail.php` | `app/mailers/training_signup_mailer.rb` |
| `UpdateMailingListSubscriptionsMail.php` | `app/mailers/update_mailing_list_subscriptions_mailer.rb` |
| `VehiclePendingMail.php` | `app/mailers/vehicle_pending_mailer.rb` |
| `WelcomeMail.php` | `app/mailers/welcome_mailer.rb` |

### ProspectiveApplication Mailers (13)

| Laravel Source | Rails Target |
|----------------|--------------|
| `ProspectiveApplication/AgeConfirmationMail.php` | `app/mailers/prospective_application/age_confirmation_mailer.rb` |
| `ProspectiveApplication/ApprovedCallsignMail.php` | `app/mailers/prospective_application/approved_callsign_mailer.rb` |
| `ProspectiveApplication/ApprovedReminderMail.php` | `app/mailers/prospective_application/approved_reminder_mailer.rb` |
| `ProspectiveApplication/ExperienceConfirmationMail.php` | `app/mailers/prospective_application/experience_confirmation_mailer.rb` |
| `ProspectiveApplication/MoreHandlesMail.php` | `app/mailers/prospective_application/more_handles_mailer.rb` |
| `ProspectiveApplication/PiiIssueMail.php` | `app/mailers/prospective_application/pii_issue_mailer.rb` |
| `ProspectiveApplication/RejectRegionalMail.php` | `app/mailers/prospective_application/reject_regional_mailer.rb` |
| `ProspectiveApplication/RejectTooYoungMail.php` | `app/mailers/prospective_application/reject_too_young_mailer.rb` |
| `ProspectiveApplication/RejectUnqualifiedMail.php` | `app/mailers/prospective_application/reject_unqualified_mailer.rb` |
| `ProspectiveApplication/ReturningRangerMail.php` | `app/mailers/prospective_application/returning_ranger_mailer.rb` |
| `ProspectiveApplication/RRNCheckMail.php` | `app/mailers/prospective_application/rrn_check_mailer.rb` |
| `ProspectiveApplication/SendEmail.php` | `app/mailers/prospective_application/send_email_mailer.rb` |
| `ProspectiveApplication/WhyRangerQuestionMail.php` | `app/mailers/prospective_application/why_ranger_question_mailer.rb` |

## Conversion Patterns

### Class Structure

**Laravel (PHP):**
```php
class WelcomeMail extends ClubhouseMailable
{
    use Queueable, SerializesModels;

    public function __construct(public Person $person, public string $inviteToken)
    {
        parent::__construct();
    }

    public function envelope(): Envelope
    {
        $envelope = $this->fromVC('Welcome...');
        $envelope->to([new Address($this->person->email)]);
        return $envelope;
    }

    public function content(): Content
    {
        return new Content(view: 'emails.welcome');
    }
}
```

**Rails (Ruby):**
```ruby
class WelcomeMailer < ApplicationMailer
  def notify(person:, invite_token:)
    @person = person
    @invite_url = "#{default_host}/login?token=#{invite_token}&welcome=1"

    mail(
      from: vc_from,
      to: person.email,
      subject: 'Welcome to the Black Rock Rangers Secret Clubhouse!'
    )
  end
end
```

### Settings Access

| Laravel | Rails |
|---------|-------|
| `setting('VCEmail')` | `EmailAddresses::VOLUNTEER_COORDINATORS_TEAM` |
| `setting('DoNotReplyEmail')` | `EmailAddresses::DO_NOT_REPLY` |
| `setting('TrainingAcademyEmail')` | `EmailAddress::TRAINING_ACADEMY` |
| `setting('DailyReportEmail')` | `Setting.get_value(Setting::DAILY_REPORT_EMAIL)` |
| `setting('ProspectiveApplicationMailSandbox')` | `Setting.get_value(Setting::PROSPECTIVE_APPLICATION_MAIL_SANDBOX)` |
| `setting('AdminEmail')` | no longer used |
| `setting('OnlineCourseSiteUrl')` | `Setting.get_value(Setting::ONLINE_COURSE_SITE_URL)` |
| `setting('AccountCreationEmail')` | `Setting.get_value(Setting::ACCOUNT_CREATION_EMAIL)` |
| `setting('PhotoPendingNotifyEmail')` | `EmailAddresses::VOLUNTEER_COORDINATORS_TEAM` |
| `setting('VehiclePendingEmail')` | `Setting.get_value(Setting::VEHICLE_PENDING_EMAIL)` |
| `setting('RRNEmail')` | `Setting.get_value(Setting::RRN_EMAIL)` |
| `setting('MailingListUpdateRequestEmail')` | `Setting.get_value(Setting::MAILING_LIST_UPDATE_REQUEST_EMAIL)` |
| `setting('TAS_SAP_Report_Email')` | `Setting.get_value(Setting::TAS_SAP_REPORT_EMAIL)` |

### Mail Method Patterns

**Single recipient:**
```ruby
mail(
  from: vc_from,
  to: person.email,
  subject: '[Clubhouse] Subject here'
)
```

**Multiple recipients (comma-separated setting):**
```ruby
mail(
  from: do_not_reply_from,
  to: build_addresses(Setting.get_value(Setting::DAILY_REPORT_EMAIL)),
  subject: "[Clubhouse] Daily Report #{Date.current.strftime('%Y-%m-%d')}"
)
```

### From Address Helpers

| Laravel Method | Rails Method | Description |
|----------------|--------------|-------------|
| `fromVC()` | `vc_from` | Volunteer Coordinators email |
| `fromDoNotReply()` | `do_not_reply_from` | Do not reply email |
| `fromTrainingAcademy()` | `training_academy_from` | Training Academy email |

### Template Conversion (Blade to ERB)

| Blade | ERB |
|-------|-----|
| `{{ $variable }}` | `<%= @variable %>` |
| `{!! $html !!}` | `<%= raw @html %>` or `<%= simple_format(@html) %>` |
| `@if ($condition)` | `<% if @condition %>` |
| `@else` | `<% else %>` |
| `@endif` | `<% end %>` |
| `@foreach ($items as $item)` | `<% @items.each do \|item\| %>` |
| `@endforeach` | `<% end %>` |
| `@empty` | `<% if @items.empty? %>` |
| `{{ $person->callsign }}` | `<%= @person.callsign %>` |
| `{{ nl2br($text) }}` | `<%= simple_format(@text) %>` |

### Blade Components to ERB Partials

| Blade Component | ERB Partial |
|-----------------|-------------|
| `<x-html-email>` | Layout: `app/views/layouts/mailer.html.erb` |
| `<x-ranger-header-image/>` | `<%= render 'shared/mailer/ranger_header_image' %>` |
| `<x-vc-application-on-hold/>` | `<%= render 'shared/mailer/vc_application_on_hold' %>` |
| `<x-vc-application-footer :application="$application"/>` | `<%= render 'shared/mailer/vc_application_footer' %>` |

## Directory Structure

```
app/
├── mailers/
│   ├── application_mailer.rb
│   ├── clubhouse_mailer.rb
│   ├── prospective_application_mailer.rb
│   ├── account_creation_mailer.rb
│   ├── alert_when_sign_ups_empty_mailer.rb
│   ├── ... (24 more main mailers)
│   └── prospective_application/
│       ├── age_confirmation_mailer.rb
│       ├── approved_callsign_mailer.rb
│       └── ... (11 more PA mailers)
├── views/
│   ├── layouts/
│   │   └── mailer.html.erb
│   ├── shared/
│   │   └── mailer/
│   │       ├── _ranger_header_image.html.erb
│   │       ├── _vc_application_on_hold.html.erb
│   │       └── _vc_application_footer.html.erb
│   ├── account_creation_mailer/
│   │   └── notify.html.erb
│   ├── ... (25 more main mailer view directories)
│   └── prospective_application/
│       ├── age_confirmation_mailer/
│       │   └── notify.html.erb
│       └── ... (12 more PA view directories)
└── helpers/
    └── mailer_helper.rb
```

## Mailer Method Naming Convention

| Mailer | Primary Method |
|--------|----------------|
| Most mailers | `notify` |
| ContactMailer | `send_message` |
| ProspectiveApplication::SendEmailMailer | `send_message` |
| RbsMailer | `broadcast` |
| ProspectiveApplication::RrnCheckMailer | `check` |

## Usage Examples

### Sending a Welcome Email
```ruby
WelcomeMailer.notify(person: person, invite_token: token).deliver_later
```

### Sending a ProspectiveApplication Email
```ruby
ProspectiveApplication::AgeConfirmationMailer.notify(
  application: application,
  status: 'hold',
  message_to_user: 'Custom message here'
).deliver_later
```

### Sending a Broadcast Email
`RbsMailer` only draws a broadcast email; it never delivers one. `Rbs` renders it once and hands it to Amazon
SES in batches (see `docs/rbs-translation.md` and `docs/FEATURES.md`, RBS › Broadcast emails):
```ruby
mail = RbsMailer.broadcast(
  subject: "Important Announcement",
  rbs_message: message_text,
  alert: alert,
  expires_at: 1.day.from_now
).message
```

## Notes

1. **Async Delivery**: All mailers should use `deliver_later` for async delivery via Active Job, except `RbsMailer`, which only draws the email for SES (see Sending a Broadcast Email)
2. **Sandbox Mode**: ProspectiveApplication mailers support sandbox mode via `PROSPECTIVE_APPLICATION_MAIL_SANDBOX` setting
3. **Template Path Mapping**: Laravel's `prospective-application/` maps to Rails' `prospective_application/`
4. **ruby 4.0 Syntax**: All mailers use keyword arguments per ruby 4.0 best practices
5. **Rails 8.1 Best Practices**: Mailers follow Rails 8.1 ActionMailer conventions
