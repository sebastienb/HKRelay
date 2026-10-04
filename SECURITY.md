# Security policy

This application can control physical devices. Treat vulnerabilities involving authorization, writes, token disclosure, or unintended network exposure as high impact.

## Reporting

Do not open a public issue containing a token, signing identity, HomeKit identifier, device or room name, screenshot of a real Home, or diagnostic export. Once the repository is hosted on GitHub, use GitHub's private vulnerability-reporting feature. If that feature is unavailable, open a minimal issue asking the maintainers for a private contact without including sensitive details.

If a token may have been exposed, immediately use **Generate a new token** in the app and remove the CLI credential file from the affected machine.

## Supported security boundary

- The REST server must default to `127.0.0.1`; binding all IPv4 interfaces requires an explicit persisted user setting.
- REST and MCP data endpoints always require bearer-token authentication. Old persisted settings that disabled REST authentication are ignored.
- REST and MCP reject browser-origin requests. Only the minimal health endpoints are unauthenticated.
- MCP tools use the same permission-enforcing routes as REST; writes require `confirm: true`. This flag is client-supplied and does not establish human approval.
- Unknown accessories are denied by default.
- Only the UI may expand accessory permissions.
- The CLI must require explicit confirmation for writes.
- Tokens and response data must never enter logs, analytics, crash reports, fixtures, or source control.
- The user-controlled request history may retain paths and JSON request values only inside the app's private container. It must redact authentication material, remain bounded, and provide pause and clear controls.
- The unsigned-debug token fallback must remain debug-only, inside the app's Application Support container, and mode `0600`; signed builds must use Keychain.

The listener limits simultaneous connections/outstanding handlers to 32. Requests have bounded headers (16 KiB), targets (2 KiB), and total size (1 MiB). Incomplete requests expire after 10 seconds, upstream handlers after 30 seconds, and response writes after 5 seconds. Excess connections are closed. Cancellation-resistant handlers retain their capacity slot until they finish. Stopping closes client sockets; cancellation cannot roll back physical operations already submitted to HomeKit.

LAN mode remains experimental, uses unencrypted HTTP on all IPv4 interfaces, and requires an isolated trusted network or operator-provided private encryption. Bearer authentication alone does not protect against interception. Public exposure, remote tunneling, router port forwarding, and forwarding HomeKit data to a cloud service are not supported by this project.

## Contributor checklist

Before sharing a branch or patch:

```sh
./scripts/check-secrets.sh
swift test
```

Inspect the complete diff manually. Automated scanning reduces risk but cannot prove that a repository contains no private information.
