# Source publication

This is an experimental, MIT-licensed source release. Publish the audited source snapshot, not a ZIP of a local development directory or a signed/ad-hoc app bundle.

## Snapshot contents

The publication snapshot should include source, tests, public build configuration, CI, the MIT license, privacy documentation, and the security policy. It must exclude old private Git history, developer identity/email metadata, local signing configuration, credentials, request history, Home exports, screenshots of real devices, and build products. Its initial commit can use a generic project author identity; contributors should select their own public or GitHub-provided no-reply identity for future commits.

Run these from the clean repository before pushing:

```sh
./scripts/check-secrets.sh --history
./scripts/check.sh
```

Inspect the files and commit metadata manually. The scanner checks common credential formats and reachable commits; it is not a proof that all private information is absent. Ignored files must never be force-added. Do not reuse the private repository's history or change its visibility if the goal is to avoid publishing its author identities.

## Hosting settings

Create a separate public repository for the clean snapshot. Preserve the original private repository as the development backup. Use the source-only snapshot when making the first public commit; do not push other private branches or tags.

Enable GitHub private vulnerability reporting and available secret scanning/push protection. Require passing CI for changes to the default branch. Review issue/PR attachments for real Home information before posting. CI builds an unsigned app for compilation only and has no HomeKit database or signing secrets.

The snapshot is intended for developers who can configure their own HomeKit signing. Do not attach a binary, provisioning profile, certificate, or signing key to the source release. Developer ID/HomeKit support, Apple review of the intended features, and off-device HomeKit data use remain external distribution questions described in [Distribution](DISTRIBUTION.md).

## Limits that must remain visible

- REST and MCP require a bearer token; grants are shared across all clients holding that token.
- Loopback is the supported local workflow. LAN HTTP is experimental and unencrypted; no public hosting, port forwarding, or cloud forwarding is supported.
- The server has connection and time limits; stalled upstream handlers consume capacity until they finish.
- Writes may already have reached a physical device when a connection times out or closes. Never automatically retry.
- Software tests and signing checks do not certify real-device safety or App Store approval.
