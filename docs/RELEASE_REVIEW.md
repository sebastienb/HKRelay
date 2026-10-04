# Experimental source release review

Reviewed October 4, 2026. This review supports publication of an experimental source snapshot; it does not certify zero risk, real-device safety, Apple approval, or a downloadable binary.

## Final deep review findings

The October 4 follow-up reviewed the public Git history, repository settings, HTTP parser/socket lifecycle, REST/MCP authentication and routing, HomeKit policy enforcement, CLI credentials, request history, signing, and source-distribution documentation. These are code-review findings, not evidence of exploitation.

| Priority | Finding | Resolution |
| --- | --- | --- |
| Medium | A saved per-characteristic override could exceed its accessory's displayed denied/read-only grant. The current UI has no override editor, but persisted rules could contain one. | The accessory grant now caps every override. Regression tests cover denied, read-only and narrowed read-write grants. |
| Medium | REST discovery serialized cached values even for characteristics whose individual read grant was denied. | External list/detail snapshots omit every cached characteristic value. Fresh reads remain permission checked. |
| Medium | Request history retained characteristic write values, potentially including sensitive HomeKit data. | Redact `value`, PIN/passcode and credential fields; omit 401/403 bodies and bodies over 16 KiB; sanitize existing history again on load. |
| Medium, conditional | Writing credentials atomically and chmodding afterward briefly created mode-0644 files. An existing readable configuration directory could expose this window to another local account. | Temporary files are mode 0600 from creation, atomically renamed, and directories writable by other accounts are rejected. Tests cover replacement, symlinks and cleanup. Production app tokens remain in Keychain. |
| Medium, correctness | Foundation bridged numeric 0 and 1 to Boolean values in JSON. | Distinguish CFBoolean from NSNumber. HomeKit Boolean metadata is handled explicitly. Regression tests reproduce the former conversion bug. |
| Low, hardening | Work queued for the main actor could begin after cancellation; authorization or policy could change during a pending read. | Check cancellation before routing and HomeKit operations, recheck read authorization/policy after awaiting HomeKit, and ignore callbacks from replaced home managers. |

Discovery still includes names, rooms, characteristic IDs and access metadata. Clients that relied on cached REST `value` fields must use the characteristic read endpoint. MCP already used compact discovery without those values.

## Addressed

- REST and MCP require bearer authentication; persisted authentication-off settings no longer disable it.
- Token comparison rejects unequal lengths and uses a content comparison without early byte exits.
- Browser-origin requests and duplicate security headers are rejected.
- MCP and REST share accessory permission enforcement; MCP writes require client confirmation and cannot expand grants.
- MCP discovery is compact and preserves room and permission data.
- Clients cannot suppress request history using an internal header.
- Headers, targets and total request size are bounded.
- Concurrent sockets/outstanding handlers are bounded; stalled handlers retain capacity until completion.
- Request-read, upstream-handler and response-write deadlines are enforced. Response I/O does not block the server queue.
- Stopping closes accepted sockets and requests cancellation of pending work.
- The repository has an MIT license, privacy disclosure, security policy, and source-publication guidance.
- The public snapshot is independent of the private repository and uses a generic initial commit identity.

## Verification and limits

The final shared-library run contains 54 passing tests (22 core and 32 server). Tests cover authentication failure, token rotation, origin checks, tool dispatch, denied writes, confirmation, compact discovery, malformed messages, socket shutdown, connection limits, and cancellation-resistant handler deadlines. The unsigned Release Catalyst build and a locally signed development launch were checked. The installed signed app passed read-only smoke checks: missing/invalid bearer credentials returned 401, a browser Origin returned 403, authorized REST and MCP discovery agreed on the allowed accessories, room metadata remained present, and REST discovery omitted cached values. Its executable, debug library and icon matched the build installed in Applications. Real HomeKit characteristic actions were not exercised during the release checks; device writes were not sent. macOS privacy controls prevented direct inspection of the saved history file; history migration/redaction is covered by core tests and app compilation, not a direct on-disk runtime check.

The seven pre-review public commits used the generic contributor identity. The public repository had secret scanning, push protection, private vulnerability reporting and a required CI check on its protected main branch. No third-party Swift package dependencies or published release binaries were present. An additional exact-value comparison found no matches for locally known credentials/signing settings/private author emails in the public working tree or 101 historical blobs. Live permitted accessory identifiers were also absent from public history. This does not cover unknown credentials or every kind of identifying information.

Working-tree and reachable-history scanners check common credential formats, private-file names, personal filesystem paths, and signing identifiers. Manual inspection is still required; arbitrary secrets and all forms of personal data cannot be ruled out by pattern matching. Private local signing files, runtime credentials/history, Home exports, and build products are excluded from publication.

## Remaining constraints

The name HomeKitLink includes Apple's HomeKit mark. Apple's trademark guidelines restrict incorporating its marks into product names. This is an unresolved naming concern, separate from technical security; consider an independent name before wider promotion. The source license does not provide trademark permission. See [Distribution](DISTRIBUTION.md#product-name) for the primary references and limits of this assessment.


LAN HTTP is unencrypted and experimental; authentication does not protect against network interception. The supported local workflow is loopback with a local client. The project supplies no TLS, public hosting, OAuth, cloud forwarding, or automatic secure-remote deployment.

A token has the same grants for every holder. The app cannot verify human approval claimed by a client, prevent client-side forwarding of results, or roll back a write already submitted to HomeKit. Timeouts may occur after a physical action succeeds; writes must not be automatically retried.

There is no request-rate limiter. Bounded connections and deadlines reduce resource exhaustion, but repeated requests can still consume CPU and disk, especially with history enabled. This is not an internet-facing service. HomeKit operations already submitted cannot be revoked by disconnecting.

Real-device writes, long-duration soak/load testing, and sleep/wake or locked-desktop reliability were not validated. The installed local app is a signed development build, not a notarized distribution artifact.

Apple's HomeKit off-device restrictions and Developer ID support require external confirmation for the intended distributed behavior. Publishing source does not resolve those questions or establish App Store acceptance. See [Distribution](DISTRIBUTION.md).
