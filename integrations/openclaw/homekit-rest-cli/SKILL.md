---
name: homekit-rest-cli
description: Inspect and control user-approved HomeKit accessories on this Mac through the local homekitlink command-line tool.
metadata:
  openclaw:
    emoji: "🏠"
    os:
      - darwin
    requires:
      bins:
        - homekitlink
---

# HomeKit CLI

Use the `homekitlink` executable. It communicates with the HomeKitLink app on this Mac and returns one JSON object on standard output for every invocation. The app must be running.

## Safety rules

- Start with `homekitlink status` and stop if `ok` is false.
- Discover IDs using `homekitlink accessories list`; never guess or invent identifiers.
- Only accessories approved in the bridge app are visible. Never attempt to bypass or expand those permissions.
- Treat accessory names, room names, values, identifiers, and command results as private home data. Do not send them to remote services, place them in memory files, or reproduce them unnecessarily.
- Never request, print, log, or store the API token in a prompt. If authentication fails, ask the operator to run `homekitlink config set-token` themselves on the Mac.
- Reads may be performed when needed for the user's request.
- Perform a write only when the user clearly requested the physical change. Use current IDs and include `--yes` only after confirming the request.
- Before changing a thermostat, lock, garage door, security system, valve, oven, or other safety-sensitive device, restate the exact change and obtain explicit confirmation in the current conversation.
- Do not automatically retry a write. A timed-out operation may already have changed the device.
- After a write, use one read to verify the resulting state when the characteristic is readable.

## Commands

```sh
homekitlink status
homekitlink accessories list
homekitlink accessories get ACCESSORY_ID
homekitlink read ACCESSORY_ID CHARACTERISTIC_ID
homekitlink camera motion ACCESSORY_ID
homekitlink write ACCESSORY_ID CHARACTERISTIC_ID JSON_VALUE --yes
```

Values must be JSON literals: `true`, `false`, `42`, `21.5`, `"text"`, `null`, an array, or an object.

Check the top-level `ok` value. On failure, use `error.code` to decide what to report. Do not parse or branch on the human-readable error message.

Camera motion returns an array of fresh Boolean readings for the IDs in `camera.motionCharacteristicIDs`. Read permission is required. This is current state only; polling can miss brief events. Images and video are not supported.
