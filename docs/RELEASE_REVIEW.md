# Experimental source release review

Reviewed October 4, 2026. This review supports publication of an experimental source snapshot; it does not certify zero risk, real-device safety, Apple approval, or a downloadable binary.

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

Shared-library tests cover authentication failure, token rotation, origin checks, tool dispatch, denied writes, confirmation, compact discovery, malformed messages, socket shutdown, connection limits, and cancellation-resistant handler deadlines. The unsigned Release Catalyst build and a locally signed development launch were checked. Real HomeKit actions were not exercised during the release checks; device writes were not sent.

Working-tree and reachable-history scanners check common credential formats, private-file names, personal filesystem paths, and signing identifiers. Manual inspection is still required; arbitrary secrets and all forms of personal data cannot be ruled out by pattern matching. Private local signing files, runtime credentials/history, Home exports, and build products are excluded from publication.

## Remaining constraints

LAN HTTP is unencrypted and experimental; authentication does not protect against network interception. The supported local workflow is loopback with a local client. The project supplies no TLS, public hosting, OAuth, cloud forwarding, or automatic secure-remote deployment.

A token has the same grants for every holder. The app cannot verify human approval claimed by a client, prevent client-side forwarding of results, or roll back a write already submitted to HomeKit. Timeouts may occur after a physical action succeeds; writes must not be automatically retried.

Apple's HomeKit off-device restrictions and Developer ID support require external confirmation for the intended distributed behavior. Publishing source does not resolve those questions or establish App Store acceptance. See [Distribution](DISTRIBUTION.md).
