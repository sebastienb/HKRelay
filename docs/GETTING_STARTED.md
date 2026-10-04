# Getting Started

HKRelay accepts API requests from the same Mac by default. Local-network access is available as an opt-in setting for clients on other devices.

## Before you begin

- Use macOS 14 or later.
- Sign in to the Mac with the Apple Account that can already see the intended Home in Apple's Home app.
- Confirm that the Home app can see and control at least one accessory before starting the bridge.

If you are building the app from source for testing, you also need Xcode with Swift 6.1 or later, an Apple Developer Program team, and an explicit bundle identifier with the HomeKit capability enabled. See the source-build steps in the main [README](../README.md#build-a-signed-development-copy).

## First launch

1. Open **HKRelay**.
2. Approve Home access when macOS asks.
3. In **Overview**, wait for **Home data** to show that accessories are loaded.
4. Open **Accessories** and select one non-critical accessory.
5. Start with **Read only** access. Keep all other accessories set to **Not allowed**.

The bridge denies every accessory by default. Only the app UI can expand an accessory's permissions.

## Make your first API request

Open the app's **CLI** tab and copy the bridge token. In Terminal, read it into a temporary shell variable without placing it in shell history:

```sh
printf 'Bridge token: '
read -rs HKRELAY_TOKEN
printf '\n'
```

Check the bridge status:

```sh
printf 'header = "Authorization: Bearer %s"\n' "$HKRELAY_TOKEN" | \
  curl --silent --show-error --config - \
  http://127.0.0.1:8765/v1/status
```

List the accessories you allowed:

```sh
printf 'header = "Authorization: Bearer %s"\n' "$HKRELAY_TOKEN" | \
  curl --silent --show-error --config - \
  http://127.0.0.1:8765/v1/accessories
```

Both responses are JSON. A successful response contains `"ok": true`.

When finished, remove the temporary token from the shell:

```sh
unset HKRELAY_TOKEN
```

## Experimental connection from another device

1. Open the app's **API and MCP** screen.
2. Turn on **Allow Local Network Connections** and approve the macOS local-network prompt if it appears.
3. Set or copy the token from **Security & Logs**. Authentication is always required.
4. Use one of the displayed local-network URLs from a test client, such as `http://192.168.1.20:8765`.
5. Send the token in the `Authorization: Bearer TOKEN` header for protected endpoints.

Both devices must be on a network that permits peer-to-peer traffic. The API uses unencrypted HTTP, so do not use it on an untrusted network or expose port `8765` through a router.

## Optional command-line client

The `hkrelay` client wraps the same loopback API and emits stable JSON. A source checkout can build it with:

```sh
swift build -c release --product hkrelay
```

The CLI is built locally from source; this repository does not provide an approved end-user binary package.

### CLI credentials

Run `hkrelay config set-token` and enter the token at the private prompt. The CLI stores it in `~/.config/hkbridge/credentials.json` with user-only permissions. This location is retained for compatibility with earlier versions; existing credentials continue to work after the CLI rename.

For ephemeral automation, the CLI also accepts `HKRELAY_TOKEN` from the process environment. `HKRELAY_CONFIG_DIR` overrides the directory used for the credential file. The legacy `HKBRIDGE_TOKEN` and `HKBRIDGE_CONFIG_DIR` names remain supported; the corresponding `HKRELAY_` setting takes precedence when both are set. Keep tokens out of command arguments, repositories, prompts, issues, screenshots, and logs.

## Background operation

The bridge continues running after its main window closes. Both background conveniences are opt-in:

- **Show Menu Bar Item While Running** keeps a status item available while the bridge runs. macOS lists its helper under Login Items, and the bridge unregisters it when you quit.
- **Open at Login** asks macOS to start the main app when you sign in.

Quit the app to stop the API server.

## Troubleshooting

### Home access is not allowed

Open **System Settings > Privacy & Security > Home**, allow access for HKRelay, then use **Check Again** in the Accessories screen.

### Home data stays empty

Open Apple's Home app and verify that it can load the Home on the same Mac and Apple Account. Then choose **Reload HomeKit** in the bridge.

### The server cannot start

Another process may already be using port `8765`. Quit other copies of the bridge and relaunch it.

### Another device cannot connect

Confirm that **Allow Local Network Connections** is on, macOS has granted Local Network access to the app, both devices are on the same network, and the network does not isolate wireless clients. Test `GET /health` before debugging authentication.

### Requests return `unauthorized`

Copy the current token from the **CLI** tab. If you generated a new token, all previously configured clients must be updated.

### The menu bar item needs approval

Open **System Settings > General > Login Items** and approve the helper. The Overview screen changes from **Needs approval** to **On** once macOS enables it.

## Safety

Grant read-and-write access only when necessary. Never use this prototype for emergency, medical, life-safety, or unattended security operations.

## Upgrading from an earlier name

The app is now **HKRelay**, the CLI is `hkrelay`, and the source repository is `sebastienb/HKRelay`. Build the app using `App/HKRelay.xcodeproj` and the **HKRelay** scheme. Replace your previous app with `HKRelay.app` in Applications; quit the older copy first so only one server owns port 8765. The MCP and REST URLs and MCP tool names are unchanged.

Keep your existing bundle identifier and developer team in `Local.xcconfig` when upgrading. Internal Keychain, preferences, log-directory, credential-file identifiers, and the hidden menu-helper bundle filename deliberately retain their earlier names so permissions and saved credentials continue to work. If login launch needs approval after moving the app, check **Open at Login** and **Show Menu Bar Item** in Overview.

Update scripts to call `hkrelay` and install the renamed `hkrelay-cli` or `hkrelay-api` skill. You can optionally keep a local `homekitlink` or `hkbridge` symlink pointing to `hkrelay` for older scripts; the package builds the canonical `hkrelay` executable.
