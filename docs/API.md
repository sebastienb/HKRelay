# API reference

The API is served at `http://127.0.0.1:8765` by default. Enable **Allow Local Network Connections** in the app's **API and MCP** screen to connect through one of the displayed `http://MAC_IP:8765` addresses.

Except for `/health`, data requests always require the token shown in the app:

```http
Authorization: Bearer YOUR_LOCAL_TOKEN
Accept: application/json
```

Do not put the token in source code, command arguments, URLs, prompts, screenshots, or logs. The `hkrelay` CLI handles the header after its local credential setup. Authentication cannot be turned off. Browser-origin requests are rejected.

The LAN endpoint is plain HTTP: authentication limits who may make requests, but it does not encrypt request or response data. Use it only on a trusted network and do not expose port `8765` to the internet.

## MCP endpoint

`POST /mcp` provides Streamable HTTP MCP using JSON-RPC responses, separately from the REST response envelope below. It always requires the bearer token, just like REST. See [MCP connection](MCP.md) for client setup and tools.

## Local request history

The app's Security & Logs tab displays the API bearer token and can retain the newest 500 parsed API and CLI requests so the user can review method, path, request body, client type, result, and duration. Logging can be paused or cleared from that tab. Authentication headers and response bodies are never retained, query strings, characteristic values and sensitive JSON fields are redacted. Non-JSON bodies, bodies over 16 KiB, and bodies of authentication/authorization rejections are omitted. The native menu-bar helper's internal health polling is not included.

## Response envelope

Success:

```json
{
  "ok": true,
  "data": {}
}
```

Failure:

```json
{
  "ok": false,
  "error": {
    "code": "read_denied",
    "message": "Read access is disabled for this characteristic."
  }
}
```

Clients should branch on `ok` and `error.code`, not on the human-readable message.

## Endpoints

### `GET /health`

Returns a minimal unauthenticated liveness response. It does not reveal HomeKit authorization or accessory data.

### `GET /v1/status`

Returns the bridge version, whether HomeKit is authorized and loaded, whether loopback-only mode is active, and whether bearer authentication is required.

### `GET /v1/accessories`

Lists only accessories that the user has granted read or read-and-write access in the app. Denied accessories are omitted.
Each result includes a localized `category` label and a stable `categoryType` identifier so clients can present an appropriate device type without depending on the user's language.

### `GET /v1/accessories/{accessoryID}`

Returns one permitted accessory with its services and characteristics. List and detail discovery omit cached characteristic values, including for denied characteristics. Use the permission-checked read endpoint below for fresh values.

### `GET /v1/accessories/{accessoryID}/characteristics/{characteristicID}`

Requests a fresh value from HomeKit. The operation fails unless both the bridge policy and the HomeKit characteristic allow reads.

### `PUT /v1/accessories/{accessoryID}/characteristics/{characteristicID}`

Writes a JSON-compatible value:

```json
{
  "value": true
}
```

The operation fails unless both the bridge policy and the HomeKit characteristic allow writes. The CLI requires an additional `--yes` confirmation flag.

### `GET /v1/accessories/{accessoryID}/camera/motion`

Requests a fresh motion reading for each HomeKit motion characteristic exposed by a permitted camera. The normal bearer authentication and accessory/characteristic read permissions apply. It never starts a video session or opens a camera window.

Discover cameras with `GET /v1/accessories`. Their `camera.motionCharacteristicIDs` lists the motion characteristic IDs; an empty array means that the camera exposes no motion characteristic to the bridge. A missing `camera` object means the accessory has no camera profile. Manufacturer, model, and firmware fields help distinguish similarly named cameras.

```sh
printf 'header = "Authorization: Bearer %s"\n' "$HKRELAY_TOKEN" | curl --config - \
  --fail-with-body --silent --show-error \
  "http://127.0.0.1:8765/v1/accessories/$ACCESSORY_ID/camera/motion"

hkrelay camera motion ACCESSORY_ID
```

Example response (IDs are illustrative):

```json
{
  "ok": true,
  "data": [
    {"accessoryID": "camera-id", "characteristicID": "motion-id", "value": true}
  ]
}
```

`true` means motion detected; `false` means no motion currently reported. Multiple sensors return separate readings, taken sequentially, not an atomic combined state. A failed read fails the request rather than reporting false. `motion_unsupported` returns HTTP 404, denied reads return HTTP 403, and a missing/non-Boolean state returns `motion_unavailable` (HTTP 503). HomeKit read failures use the normal error envelope.

You can also read one sensor through the existing characteristic endpoint or `hkrelay read ACCESSORY_ID CHARACTERISTIC_ID`.

This reports current state only: no push notifications, event history, or person/animal/package classification. Polling can miss brief motion. Keep the Mac awake and the bridge running; no foreground camera capture is required. Locked-desktop behavior still needs validation on real hardware.

Camera snapshot/stream endpoints and the camera test page have been removed. The camera descriptor no longer advertises snapshot or streaming support.

## Limits

- Request bodies are limited to 1 MB.
- Connections are closed after every response; stopping closes all accepted sockets.
- At most 32 connections or pending handlers are admitted. Excess connections are closed.
- Reading an incomplete request is limited to 10 seconds, handling to 30 seconds, and sending to 5 seconds. A timed-out write may still complete in HomeKit; never retry it automatically.
- Headers are limited to 16 KiB and request targets to 2 KiB.
- Values are JSON nulls, booleans, numbers, strings, arrays, or objects. Binary HomeKit values are represented as Base64 strings.
- Accessory and characteristic IDs must be treated as opaque strings. They can change if an accessory is removed and added to a Home again.
