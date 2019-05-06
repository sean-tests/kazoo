# Notification events

This events will fire when a notification event is triggered in Kazoo. These are the same notifications as those Email notifications you can get from Branding application.

Please note that most of the fields should be present on all payloads, but they could also be missing base on the available information.

## Info

* **Name:** notifications
* **Friendly Name:** Notifications Webhook

## Modifiers

* **type:** Any of teletype notifications, see below for a list of all notifications.

## Notifications types

All notifications might include these common fields:

* `account_db`
* `attachment_url`
* `bcc`
* `cc`
* `from`
* `html`
* `preview`
* `reply_to`
* `subject`
* `text`
* `to`

### Account Zone Change: account_zone_change

This event is triggered when an end user requests the home zone of an account is changed.

##### Possible fields

* `account_id`
* `zones`

### Customer defined notification: cf_notification

This event is triggered when an customer want send own notification, as example from callflow.

##### Possible fields

* `account_id`
* `call_bridged`
* `call_id`
* `caller_id_name`
* `caller_id_number`
* `comments`
* `from_realm`
* `from_user`
* `message_left`
* `notification_media`
* `notify`
* `template_id`
* `timestamp`
* `to_realm`
* `to_user`
* `to`

### CNAM Update: cnam_request

This event is triggered when an end user would like the CNAM for a number changed.

##### Possible fields

* `account_id`
* `acquired_for`
* `cnam`
* `local_number`
* `number`
* `number_state`
* `request`

### Customer Update: customer_update

This event is triggered when the customer update API is used to deliver a message to the account.

##### Possible fields

* `account_id`
* `databag`
* `recipient_id`
* `template_id`
* `user_type`

### Emergency Call Failed: denied_emergency_bridge

This event is triggered when a call to an number classified as emergency fails.

##### Possible fields

* `account_id`
* `call_id`
* `emergency_caller_id_name`
* `emergency_caller_id_number`
* `outbound_caller_id_name`
* `outbound_caller_id_number`

### De-Registration: deregister

This event is triggered when a device fails to re-register and the contact expires.

##### Possible fields

* `account_db`
* `account_id`
* `authorizing_id`
* `call_id`
* `contact`
* `event_timestamp`
* `expires`
* `freeswitch_hostname`
* `from_host`
* `from_user`
* `network_ip`
* `network_port`
* `presence_hosts`
* `profile_name`
* `rpid`
* `realm`
* `status`
* `suppress_unregister_notify`
* `to_host`
* `to_user`
* `user_agent`
* `username`

### Account First Occurrence: first_occurrence

This event is triggered when an end user registers the first device and/or places the first call on an account.

##### Possible fields

* `account_id`
* `occurrence`

### Successful Fax Reception: inbound_fax

This event is triggered when a fax is successfully received.

##### Possible fields

* `account_id`
* `call_id`
* `callee_id_name`
* `callee_id_number`
* `caller_id_name`
* `caller_id_number`
* `fax_id`
* `fax_info`
* `fax_notifications`
* `fax_timestamp`
* `faxbox_id`
* `from_realm`
* `from_user`
* `owner_id`
* `to_realm`
* `to_user`

### Fax Reception Error: inbound_fax_error

This event is triggered when receiving a fax fails.

##### Possible fields

* `account_id`
* `call_id`
* `callee_id_name`
* `callee_id_number`
* `caller_id_name`
* `caller_id_number`
* `fax_error`
* `fax_id`
* `fax_info`
* `fax_notifications`
* `fax_result_code`
* `fax_timestamp`
* `faxbox_id`
* `from_realm`
* `from_user`
* `owner_id`
* `to_realm`
* `to_user`

### Account Low Balance: low_balance

This event is triggered when an account is found with a balance below the notification threshold.

##### Possible fields

* `account_id`
* `current_balance`

### Missed Call: missed_call

This event is triggered when an corresponding missed call action in a callflow is invoked.

##### Possible fields

* `account_id`
* `call_bridged`
* `call_id`
* `caller_id_name`
* `caller_id_number`
* `from_realm`
* `from_user`
* `message_left`
* `notify`
* `timestamp`
* `to_realm`
* `to_user`
* `to`

### New Account: new_account

This event is triggered when an end user creates a new account.

##### Possible fields

* `account_api_key`
* `account_db`
* `account_id`
* `account_name`
* `account_realm`

### New User: new_user

This event is triggered when an end user creates a new user.

##### Possible fields

* `account_id`
* `password`
* `user_id`

### Successful Fax Transmission: outbound_fax

This event is triggered when a fax is successfully transmitted.

##### Possible fields

* `account_id`
* `call_id`
* `callee_id_name`
* `callee_id_number`
* `caller_id_name`
* `caller_id_number`
* `fax_id`
* `fax_info`
* `fax_jobid`
* `fax_notifications`
* `fax_timestamp`
* `faxbox_id`
* `owner_id`

### Fax Transmission Error: outbound_fax_error

This event is triggered when transmitting a fax fails.

##### Possible fields

* `account_id`
* `call_id`
* `callee_id_name`
* `callee_id_number`
* `caller_id_name`
* `caller_id_number`
* `fax_error`
* `fax_id`
* `fax_info`
* `fax_jobid`
* `fax_notifications`
* `fax_timestamp`
* `faxbox_id`
* `owner_id`

### Invalid Email-to-Fax Email: outbound_smtp_fax_error

This event is triggered when the received email-to-fax email is invalid.

##### Possible fields

* `account_id`
* `errors`
* `fax_from_email`
* `fax_to_email`
* `faxbox_id`
* `faxbox_name`
* `faxbox_timezone`
* `number`
* `original_number`
* `owner_id`
* `timestamp`

### Password Recovery: password_recovery

This event is triggered when an end user requests a password recovery link.

##### Possible fields

* `account_db`
* `account_id`
* `email`
* `first_name`
* `last_name`
* `password_reset_link`
* `timezone`
* `user_id`

### Port Cancel: port_cancel

This event is triggered when a port request is canceled.

##### Possible fields

* `account_id`
* `authorized_by`
* `local_number`
* `number`
* `number_state`
* `port`
* `port_request_id`
* `reason`

### Port Comment: port_comment

This event is triggered when a comment is left on a port request.

##### Possible fields

* `account_id`
* `authorized_by`
* `comment`
* `local_number`
* `number`
* `number_state`
* `port`
* `port_request_id`

### Port Pending: port_pending

This event is triggered when a port request is accepted and submitted to a carrier.

##### Possible fields

* `account_id`
* `authorized_by`
* `local_number`
* `number`
* `number_state`
* `port`
* `port_request_id`
* `reason`

### Port Rejected: port_rejected

This event is triggered when a port request is rejected.

##### Possible fields

* `account_id`
* `authorized_by`
* `local_number`
* `number`
* `number_state`
* `port`
* `port_request_id`
* `reason`

### Port Request: port_request

This event is triggered when a port is submitted for processing.

##### Possible fields

* `account_id`
* `authorized_by`
* `local_number`
* `number`
* `number_state`
* `port`
* `port_request_id`
* `reason`
* `version`

### Port Scheduled: port_scheduled

This event is triggered when a port is accepted by a carrier and scheduled.

##### Possible fields

* `account_id`
* `authorized_by`
* `local_number`
* `number`
* `number_state`
* `port`
* `port_request_id`
* `reason`

### Port Unconfirmed: port_unconfirmed

This event is triggered when a port is created, prior to submitting.

##### Possible fields

* `account_id`
* `authorized_by`
* `local_number`
* `number`
* `number_state`
* `port`
* `port_request_id`
* `reason`

### Ported: ported

This event is triggered when a port request for number is completed.

##### Possible fields

* `account_id`
* `authorized_by`
* `local_number`
* `number`
* `number_state`
* `port`
* `port_request_id`
* `reason`

### Registration: register

This event is triggered when a device registers but is not currently registered.

##### Possible fields

* `account_db`
* `account_id`
* `authorizing_id`
* `authorizing_type`
* `call_id`
* `contact`
* `event_timestamp`
* `expires`
* `from_host`
* `from_user`
* `network_ip`
* `network_port`
* `owner_id`
* `realm`
* `suppress_unregister_notify`
* `to_host`
* `to_user`
* `user_agent`
* `username`

### Service Added: service_added

This event is triggered when an account's billable quantities change.

##### Possible fields

* `account_id`
* `audit_log`
* `items`
* `timestamp`

### System Alert: system_alert

This event is triggered to alert the system administrators.

##### Possible fields

* `account_id`
* `details`
* `line`
* `message`
* `module`
* `node`
* `pid`
* `request_id`
* `section`
* `subject`

### Automatic Account Top-up: topup

This event is triggered when an account automatic top-up is attempted.

##### Possible fields

* `account_id`
* `add_ons`
* `amount`
* `billing_address`
* `card_last_four`
* `currency_code`
* `discounts`
* `id`
* `purchase_order`
* `response`
* `success`
* `tax_amount`
* `timestamp`

### Transaction Completed: transaction

This event is triggered when a transaction is attempted.

##### Possible fields

* `account_id`
* `add_ons`
* `amount`
* `billing_address`
* `card_last_four`
* `currency_code`
* `discounts`
* `id`
* `purchase_order`
* `response`
* `service_plan`
* `success`
* `tax_amount`
* `timestamp`

### Voicemail Box Full: voicemail_full

This event is triggered any time an attempt to leave a voicemail message is blocked because the voicemail box is full.

##### Possible fields

* `account_id`
* `max_message_count`
* `message_count`
* `voicemail_box`

### New Voicemail Message: voicemail_new

This event is triggered any time a voicemail message is left.

##### Possible fields

* `account_id`
* `call_id`
* `caller_id_name`
* `caller_id_number`
* `from_realm`
* `from_user`
* `to_realm`
* `to_user`
* `voicemail_box`
* `voicemail_id`
* `voicemail_length`
* `voicemail_timestamp`
* `voicemail_transcription`

### Voicemail Message Saved: voicemail_saved

This event is triggered any time a voicemail message is saved in the voicemail box 'new' folder.

##### Possible fields

* `account_id`
* `call_id`
* `caller_id_name`
* `caller_id_number`
* `from_realm`
* `from_user`
* `to_realm`
* `to_user`
* `voicemail_box`
* `voicemail_id`
* `voicemail_length`
* `voicemail_timestamp`
* `voicemail_transcription`

### Callflow Webhook Triggered: webhook

This event is triggered when a corresponding webhook action in a callflow is reached.

##### Possible fields

* `account_id`
* `data`
* `hook`
* `timestamp`

### Webhook Disabled: webhook_disabled

This event is triggered when a webhook is disabled.

##### Possible fields

* `account_id`
* `hook_id`

