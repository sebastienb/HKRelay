# Privacy

HKRelay is a local, experimental app. It contains no advertising, analytics, remote error reporting, developer-operated backend, or automatic upload of HomeKit information.

## On this Mac

The signed app uses Apple's HomeKit APIs with the user's consent. Apple grants access to the Home database to the app as a whole; the bridge applies an additional per-accessory policy to REST, MCP, and CLI operations. New accessories are denied until enabled in the UI. HomeKit and the Home database remain subject to Apple's services and privacy practices.

The API token is stored in Keychain in signed builds. Unsigned debug builds may use a development token file with user-only permissions. The CLI uses a separate mode-0600 credential file or a process environment variable. Access policies and settings are stored locally in the app container.

Request history is optional and can be paused or cleared. It retains up to 500 entries inside the app's private container: timestamps, paths (which may include device IDs), method, status, client classification, duration, and sanitized JSON request bodies (with characteristic values omitted). Query strings, characteristic values and recognized credential fields are redacted. Bodies of rejected authentication/authorization requests and bodies over 16 KiB are omitted. Existing history is sanitized again on load. Authentication headers, arbitrary raw user-agent strings, and response bodies are not retained. Redaction cannot recognize arbitrary secrets entered under unrelated JSON fields; never send credentials as characteristic values.

## Connected clients

A client holding the token can receive permitted accessory names, room names, IDs, device types, characteristics and values, and can operate devices granted read-write access. Tokens are not scoped per client. Permissions apply equally to every client holding the token. Revoke a credential by generating a new token; all clients must then be reconfigured.

Client-side storage and further use are controlled by that client. If an AI client sends tool results to a model service, data can leave the Mac even when the bridge listens on loopback. The bridge cannot enforce a client's data retention or prevent that forwarding. Use locally running clients/models for the local workflow; cloud forwarding is not supported by this project.

## Network and diagnostics

Loopback networking is the default. Experimental LAN mode binds all IPv4 interfaces and uses plain HTTP. Authentication does not encrypt tokens or device data. Keep port 8765 off the public internet and use an isolated trusted network or operator-provided private encryption for testing. The project does not provide TLS, OAuth, or a public hosting service.

System logs contain startup/network status; the bridge does not intentionally log tokens or HomeKit responses. Do not attach tokens, real device exports, room names, identifiers, personal signing configuration, or screenshots of a real Home to public issues. Report security concerns as described in [Security](../SECURITY.md).
