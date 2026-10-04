# MCP connection

The running Mac app serves MCP at `http://127.0.0.1:8765/mcp` using Streamable HTTP. Use a native MCP client that supports a preconfigured `Authorization` header. The app's API screen displays the endpoint; Security & Logs provides the token.

MCP **always** requires `Authorization: Bearer YOUR_LOCAL_TOKEN`, including initialization, discovery, notifications, and tool calls. REST also always requires authentication. Generating or setting a new token revokes the old token on subsequent requests for both interfaces.

Configure these values in your client's MCP server settings:

| Setting | Value |
| --- | --- |
| Transport | Streamable HTTP |
| URL | `http://127.0.0.1:8765/mcp` |
| Header name | `Authorization` |
| Header value | `Bearer ` followed by the token from Security & Logs |

Use the client's private credential storage. Header configuration and environment-variable interpolation vary by client; do not commit a configuration containing the actual token or paste it into a model prompt. OAuth discovery/sign-in and clients that cannot supply a custom bearer header are not supported. No OAuth endpoints are advertised.

## Tools and permissions

| Tool | Required arguments | Behavior |
| --- | --- | --- |
| `homekit_status` | None | Bridge and HomeKit availability |
| `homekit_list_accessories` | None | Compact summaries of permitted accessories: ID, name, room, category, access, reachability |
| `homekit_get_accessory` | `accessoryID` | Compact accessory details and characteristic IDs, names, types, permissions; no cached values |
| `homekit_read_characteristic` | `accessoryID`, `characteristicID` | Fresh value; read permission required |
| `homekit_camera_motion` | `accessoryID` | Fresh camera motion; read permission required; no images/video |
| `homekit_write_characteristic` | `accessoryID`, `characteristicID`, `value`, `confirm` | Writes a JSON value; `confirm` must be Boolean `true`; read-write permission required |

All operations dispatch through the same routes and HomeKit permission checks as REST. MCP cannot expand permissions or change the token, authentication settings, or network settings. IDs must come from bridge responses. Unknown tools, unexpected arguments, malformed IDs, and writes without confirmation are rejected before reaching HomeKit.

The write tool is marked destructive. Configure your client to ask for approval before invoking it. `confirm: true` expresses the client's confirmation; the server cannot verify that a human approved it. A client holding the token can use all permissions granted in the app. Grant only read access to clients that should not operate devices.

Discovery omits services, characteristic values, and manufacturer/firmware metadata to fit client output limits. Fetch one accessory with `homekit_get_accessory`, then read only the values needed. REST responses retain full details.

Results contain compact JSON as MCP text content. HomeKit errors, including denied access, return a tool result with `isError: true`; invalid arguments and unknown methods return JSON-RPC errors. A tool error does not imply a successful write and should not trigger automatic retries of device operations.

## Transport details

This implementation supports MCP protocol versions `2025-11-25`, `2025-06-18`, and `2025-03-26`. It implements `initialize`, `notifications/initialized`, `ping`, `tools/list`, and `tools/call`. It uses no session IDs and returns JSON responses rather than SSE. Authenticated `GET` and `DELETE` return HTTP 405; notifications return an empty HTTP 202. Batches, resources, prompts, tasks, and server-initiated messages are not implemented. Cancellation notifications are acknowledged but do not roll back or cancel HomeKit actions already underway.

POST requests require `Content-Type: application/json` and `Accept: application/json, text/event-stream`. After initialization, send the negotiated `MCP-Protocol-Version` header. Unsupported explicit header versions return HTTP 400. When omitted, the endpoint assumes the compatible `2025-03-26` behavior. These versions do not require persistent server-side session state.

Browser-origin requests are rejected with HTTP 403, including localhost origins; this endpoint is intended for native clients. Missing or incorrect tokens return HTTP 401 with a bearer challenge. Tokens must never be supplied through a URL, query parameter, or JSON argument.

The existing 1 MB request limit applies. Request history records `/mcp` plus sanitized JSON-RPC request bodies, so tool names and write arguments are visible locally when history is enabled. Authentication headers and response bodies are not retained. Logging can be paused or cleared.

## Local protocol smoke test

Enter the token at a hidden prompt in zsh, then initialize without putting the token in command arguments:

```sh
printf 'Bridge token: '; read -rs HKRELAY_TOKEN; printf '\n'
printf 'header = "Authorization: Bearer %s"\n' "$HKRELAY_TOKEN" | curl --config - \
  --fail-with-body --silent --show-error \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"local-test","version":"1"}}}' \
  http://127.0.0.1:8765/mcp
```

Send `notifications/initialized` without an `id`, then call `tools/list` with an `id`. These subsequent POSTs use the same headers plus `MCP-Protocol-Version: 2025-11-25`. Clear the shell variable when done with `unset HKRELAY_TOKEN`.

## Network and release limitations

Loopback is the default. If the existing local-network setting is enabled, `/mcp` is also reachable on all IPv4 interfaces. LAN HTTP does not encrypt the token or device data; use only a trusted network and never expose the port publicly. This source release does not implement TLS. Encrypted remote access and Apple distribution approval are not supplied by the project.

A cloud-hosted client cannot reach this Mac's loopback endpoint. Do not tunnel it publicly or forward HomeKit information to cloud services. Apple's restrictions on transferring HomeKit data off-device and the signing/distribution limitations in [Distribution](DISTRIBUTION.md) remain unresolved release considerations.

References: [MCP Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports), [MCP tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).
