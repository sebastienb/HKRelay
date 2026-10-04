# HomeKitLink

A Mac app that lets approved local software view and control only the HomeKit accessories you choose.

> [!IMPORTANT]
> This project is an early, security-sensitive prototype. Do not rely on it for emergency, life-safety, medical, or unattended security operations.

## What it includes

- A Mac Catalyst app that requests access to the HomeKit database.
- A deny-by-default UI for granting each accessory no access, read-only access, or read-and-write access.
- An HTTP API bound to `127.0.0.1:8765` by default, with opt-in local-network access.
- Bearer authentication required for every data request, with a user-defined or generated token.
- A Streamable HTTP MCP endpoint at `/mcp`, always protected by the API bearer token, with six HomeKit tools.
- The `homekitlink` CLI with stable JSON output for scripts and agents.
- Camera motion reads through `GET /v1/accessories/{id}/camera/motion` or `homekitlink camera motion ACCESSORY_ID`; camera images and video are not supported.
- A private, filterable request history for API and CLI activity, with logging that can be paused at any time.
- An optional native menu-bar helper that keeps the bridge visible when its main window is closed.
- Separate OpenClaw skills for the REST API and CLI workflows.

Apple grants HomeKit access to the application as a whole. The per-accessory permissions in this project are an additional boundary enforced by the bridge on every API request.

## Network access

HomeKit is available on a Mac through Mac Catalyst, not through an ordinary native macOS command-line process. The bridge listens only on the loopback address by default. In the app's **API and MCP** screen, **Allow Local Network Connections** makes the server listen on all IPv4 interfaces so another device on the same network can connect.

LAN mode is experimental and uses unencrypted HTTP on all IPv4 interfaces, including VPN interfaces. A bearer token does not encrypt traffic. Use loopback for the supported local workflow; LAN testing requires an isolated trusted network or a private encrypted connection supplied by the operator. Never port-forward or publicly expose port `8765`. Apple restricts exporting or remotely accessing information obtained from HomeKit, so review Apple's current developer terms before distributing the app; this repository does not provide legal advice.

## Requirements

- macOS 14 or later.
- A Mac signed into the Apple Account that has access to the intended Home.
- A recent Xcode release with Swift 6.1 or later.
- An Apple developer team and provisioning profile that can sign the HomeKit entitlement.
- XcodeGen if you change `App/project.yml` and need to regenerate the Xcode project.

The project-local run and check scripts prefer `/Applications/Xcode-beta.app` when it is installed. Contributors can select another toolchain by setting `DEVELOPER_DIR`.

For the first-run walkthrough, see [Getting Started](docs/GETTING_STARTED.md).

## Build a signed development copy

1. Open `App/HomeKitRESTBridge.xcodeproj` in Xcode.
2. Copy `App/Config/Local.xcconfig.example` to `App/Config/Local.xcconfig`.
3. Set your private development-team identifier and a bundle identifier owned by that team in `Local.xcconfig`.
4. Confirm that HomeKit and App Sandbox network server/client capabilities are enabled.
5. Select **My Mac (Mac Catalyst)** and run the app.
6. Allow Home access when macOS asks.

The committed Xcode project is generated from `App/project.yml`. After changing that specification, regenerate it with:

```sh
xcodegen generate --spec App/project.yml --project App
```

`Local.xcconfig` is ignored by Git and included after the public defaults. Never commit your development-team identifier, signing certificates, provisioning profiles, tokens, device exports, or local configuration.

To build and launch a signed development copy after configuring `Local.xcconfig`, use the project-local runner:

```sh
./script/build_and_run.sh --verify
```

This is also wired to the Codex **Run** action. Without local signing configuration, the runner creates an unsigned UI and API smoke-test build. Unsigned builds cannot reliably load real HomeKit data. You can explicitly request an unsigned smoke test with `HKBRIDGE_CODE_SIGNING=NO ./script/build_and_run.sh --verify`.

## Build and configure the CLI

Build the command-line client:

```sh
swift build -c release --product homekitlink
```

The executable is produced at `.build/release/homekitlink`. Put it in a directory on your `PATH` if OpenClaw or other automation should invoke it.

In the app's CLI screen, reveal and copy the API token. Then store it through the CLI's private prompt:

```sh
homekitlink config set-token
```

The token is stored in `~/.config/hkbridge/credentials.json` with user-only permissions. This existing location is retained for compatibility with earlier versions of the CLI. For ephemeral automation, `HKBRIDGE_TOKEN` can be supplied in the process environment instead. Do not place either form in a repository, prompt, issue, screenshot, or log.

## CLI examples

All output is JSON on standard output. A successful response has `"ok": true`; errors have `"ok": false` and a stable error code.

```sh
homekitlink status
homekitlink accessories list
homekitlink accessories get ACCESSORY_ID
homekitlink read ACCESSORY_ID CHARACTERISTIC_ID
homekitlink write ACCESSORY_ID CHARACTERISTIC_ID true --yes
```

The app process must be running. Closing its main window leaves the bridge active; the optional menu-bar item and **Open at Login** behavior are controlled from Overview. Quitting the app stops the API and menu-bar helper. Writes require read-and-write permission for that accessory in the UI. See [the API reference](docs/API.md) for the underlying endpoints and LAN configuration.

## Distribution

This repository is an experimental source release. Contributors build signed development copies using their own Apple signing configuration. It is not an approved or notarized end-user binary release. TestFlight/App Store distribution requires Apple review; Developer ID distribution and off-device HomeKit use require clarification from Apple. See the [distribution guide](docs/DISTRIBUTION.md) for the signing, validation, and review checklist.

## MCP

Connect a native MCP client to `http://127.0.0.1:8765/mcp` and configure an `Authorization: Bearer` header using the token from Security & Logs. REST and MCP always require authentication. Tools expose the same allowed accessories and permission checks as REST; writes additionally require `confirm: true`.

See [MCP connection](docs/MCP.md) for setup, tools, protocol details, and supported-client limitations. This is preconfigured bearer authentication; OAuth sign-in and browser clients are not supported.

## OpenClaw

Two OpenClaw skills are included. Install the CLI skill when `homekitlink` is on the host `PATH` and its token has been configured locally:

```sh
openclaw skills install ./integrations/openclaw/homekit-rest-cli
```

Or install the direct REST API skill and provide `HKBRIDGE_TOKEN` through OpenClaw's secret configuration rather than a prompt or skill file:

```sh
openclaw skills install ./integrations/openclaw/homekit-rest-api
```

Both skills are visible, copyable, and downloadable from their matching tabs in the app. Neither skill can expand an accessory's permissions; only the bridge UI can do that.

## Privacy and operational limits

See [Privacy](docs/PRIVACY.md) for what stays on this Mac and what connected clients receive. The server admits at most 32 concurrent connections or outstanding handlers, rejects excess connections, and uses time limits while reading requests, awaiting HomeKit, and sending responses. Stopping the server closes accepted sockets and requests cancellation of handlers. An action already handed to HomeKit may still complete; writes are never automatically retried.

## Repository hygiene

- All examples and tests use obviously fictional `mock-*` identifiers and device names.
- Runtime policies remain in the app sandbox. Signed builds keep the server token in Keychain; unsigned debug builds use a mode-`0600` file in the app's Application Support container. The CLI uses its separate user-only credential file.
- Authentication headers, tokens, response bodies, and arbitrary non-JSON bodies are never written to request history. Query strings and sensitive JSON fields are redacted.
- Request history is limited to 500 entries in the app's private container, can be disabled or cleared from Security & Logs, and is never part of this repository.
- `.gitignore` excludes common signing files, credentials, local configuration, exports, logs, and build products.
- `scripts/check-secrets.sh` checks the working tree for common accidental disclosures; `--history` also checks reachable Git history.
- No automated workflow has access to a HomeKit database or signing credentials.

Read [SECURITY.md](SECURITY.md) before reporting a vulnerability and [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## License

This project is open source under the [MIT License](LICENSE). The source license does not grant Apple entitlements or override Apple’s developer terms.

HomeKit is a trademark of Apple Inc.; this independent project is not affiliated with or endorsed by Apple.
