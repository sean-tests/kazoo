# Channel Destroy

This webhook is triggered when a channel is destroyed, usually as a result of a hangup.

## Info

* **Name:** channel_destroy
* **Friendly name:** Channel Destroy

## Modifiers

_None._

## Sample

In addition to [Base Channel Payload](README.md) this event includes below fields:

```json
    "hook_event": "channel_destroy",
    "hangup_cause": "NORMAL_CLEARING",
    "hangup_code": "sip:200",
    "duration_seconds": 6,
    "ringing_seconds": 0,
    "billing_seconds": 6
```
