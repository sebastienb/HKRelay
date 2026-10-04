# Architecture

The project separates the entitlement-bearing app from automation clients.

```text
HomeKit database
      |
Mac Catalyst app
  - HomeKit repository
  - deny-by-default policy
  - token in Keychain (signed builds)
  - HTTP server (loopback by default, LAN opt-in)
      |
127.0.0.1:8765 or local IPv4:8765
      |
MCP client, hkrelay CLI, or experimental LAN client
      |
OpenClaw or local scripts
```

## Trust boundaries

1. macOS and HomeKit decide whether the signed app may access the user's Home.
2. The app's policy decides which accessories may cross into the local API and whether writes are allowed.
3. A generated or user-defined bearer token is required for all REST and MCP data endpoints. Users may explicitly opt into experimental LAN binding; authentication cannot be disabled.
4. The CLI adds a deliberate `--yes` requirement for mutations and emits deterministic JSON for automation.
5. The OpenClaw skill provides safe operating instructions but receives no additional authority.

## Data storage

- HomeKit data is read through Apple's framework and is not exported to repository files.
- Access rules are encoded in the app's sandboxed user defaults.
- The server token is generated locally. Signed builds store it in Keychain. To permit unsigned development smoke tests, debug builds fall back only when Keychain reports a missing entitlement and write the token to the app's Application Support container with mode `0600`.
- Network scope is stored in the app's sandboxed user defaults. Loopback-only binding is the default; old authentication-off preferences are ignored.
- The CLI credential is stored separately with mode `0600` so a native command-line process can authenticate without embedding the token in arguments.

The current implementation has no analytics, cloud synchronization, webhooks, or remote logging. It uses local system logs for startup/network status and optional bounded request history.

## HTTP resource lifecycle

All descriptor I/O and connection state are confined to one dispatch queue. Reads and writes are nonblocking; response writes use a write source rather than sleeping on the queue. At most 32 connections or outstanding handlers are retained. Timers bound request reading, upstream work, and response delivery. Stopping cancels the listener and closes existing sockets before completing. Cancellation-resistant upstream tasks retain a slot until they finish, preventing unlimited replacement tasks. Cancellation never promises that a physical action has been undone.
