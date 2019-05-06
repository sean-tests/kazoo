# Channel Bridge

This webhook is triggered when two channels are bridged together, such as two users/devices connected together.

## Info

* **Name:** channel_bridge
* **Friendly name:** Channel Bridge

## Modifiers

_None._

## Sample

In addition to [Base Channel Payload](README.md) this event includes below fields:

```json
    "hook_event": "channel_bridge",
    "original_number": "+15555674567",
    "other_leg_destination_number": "+1345678349"
```
