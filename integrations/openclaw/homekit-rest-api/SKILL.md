---
name: homekit-rest-api
description: Inspect and control user-approved HomeKit accessories through the local HomeKitLink API on this Mac.
metadata:
  openclaw:
    emoji: "🏠"
    os:
      - darwin
    requires:
      bins:
        - curl
      env:
        - HKBRIDGE_TOKEN
    primaryEnv: HKBRIDGE_TOKEN
---

# HomeKit REST API

Use the REST API at `http://127.0.0.1:8765`. It is available only while the HomeKitLink app is running on this Mac.

Authenticate protected requests with `Authorization: Bearer $HKBRIDGE_TOKEN`. Feed the header to `curl` through standard input so the expanded token is not placed in process arguments or a file. Treat that environment variable as a secret: never print it, place it in a URL or command output, or reproduce it in a response. If it is missing or rejected, ask the operator to configure it outside the conversation.

## Safety rules

- Start with `GET /health`, then `GET /v1/status`; stop if the bridge is unavailable or the response has `ok: false`.
- Discover IDs using `GET /v1/accessories`; never guess or invent identifiers.
- Only accessories approved in the bridge app are visible. Never attempt to bypass or expand those permissions.
- Treat accessory names, room names, values, identifiers, and responses as private home data. Do not send them to remote services or reproduce them unnecessarily.
- Reads may be performed when needed for the user's request.
- Perform a `PUT` only when the user clearly requested the physical change.
- Before changing a thermostat, lock, garage door, security system, valve, oven, or other safety-sensitive device, restate the exact change and obtain explicit confirmation in the current conversation.
- Do not automatically retry a write. A timed-out request may already have changed the device.
- After a write, perform one `GET` to verify the resulting state when the characteristic is readable.

## Requests

Use these request shapes, substituting IDs returned by the API:

```sh
curl --silent --show-error http://127.0.0.1:8765/health

printf 'header = "Authorization: Bearer %s"\n' "$HKBRIDGE_TOKEN" | curl --config - \
  --silent --show-error \
  -H 'Accept: application/json' \
  http://127.0.0.1:8765/v1/status

printf 'header = "Authorization: Bearer %s"\n' "$HKBRIDGE_TOKEN" | curl --config - \
  --silent --show-error \
  -H 'Accept: application/json' \
  http://127.0.0.1:8765/v1/accessories

printf 'header = "Authorization: Bearer %s"\n' "$HKBRIDGE_TOKEN" | curl --config - \
  --silent --show-error \
  -H 'Accept: application/json' \
  "http://127.0.0.1:8765/v1/accessories/ACCESSORY_ID/characteristics/CHARACTERISTIC_ID"

printf 'header = "Authorization: Bearer %s"\n' "$HKBRIDGE_TOKEN" | curl --config - \
  --silent --show-error \
  -X PUT \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  --data '{"value":true}' \
  "http://127.0.0.1:8765/v1/accessories/ACCESSORY_ID/characteristics/CHARACTERISTIC_ID"

printf 'header = "Authorization: Bearer %s"\n' "$HKBRIDGE_TOKEN" | curl --config - \
  --silent --show-error \
  -H 'Accept: application/json' \
  "http://127.0.0.1:8765/v1/accessories/ACCESSORY_ID/camera/motion"
```

Cameras expose `camera.motionCharacteristicIDs` in the accessory listing. An empty array means motion is not exposed. `GET .../camera/motion` returns an array of fresh readings with `accessoryID`, `characteristicID`, and Boolean `value`. Existing read permissions apply. This is current motion state, not event history or person/animal/package classification; polling can miss brief events. Camera images and video are not supported.

Percent-encode IDs when placing them in paths. Values may be JSON nulls, booleans, numbers, strings, arrays, or objects. Check the top-level `ok` value and branch on `error.code`, not the human-readable error message.
