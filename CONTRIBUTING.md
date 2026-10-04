# Development

This is an experimental open-source project. Contributors must treat privacy and physical-device safety as higher priorities than convenience. Contributions are licensed under the project’s MIT license.

## Never contribute real Home data

Use only fictional names such as `Mock Lamp`, `Test Room`, and identifiers beginning with `mock-`. Remove device names, room names, Home identifiers, tokens, signing-team identifiers, Apple Account details, provisioning files, local paths, and screenshots before sharing anything.

Do not commit generated diagnostic output or request-history files. If a bug requires device-specific structure, reduce it to a small hand-written mock that contains no original values.

## Development workflow

1. Build and test the shared library and CLI with `swift test`.
2. If `App/project.yml` changed, regenerate `App/HKRelay.xcodeproj` with XcodeGen.
3. Compile the unsigned Catalyst target with the command in `scripts/check.sh`.
4. Run `scripts/check-secrets.sh`.
5. Inspect every changed file before committing.

Real HomeKit testing requires your own locally configured development team, bundle identifier, provisioning profile, Mac, Home, and consent. None of those values belongs in a pull request.

## Design rules

- Default to denied access.
- Enforce policy in the app, not only in the CLI or UI.
- Keep the HTTP listener loopback-only by default and require an explicit user setting for LAN binding.
- Require bearer authentication for all REST and MCP data endpoints; do not add an off switch.
- Keep stdout machine-readable for CLI commands; send human diagnostics to stderr.
- Do not add analytics or remote error collection.
- Avoid dependencies unless they materially improve safety or maintainability.
- Never make a write retry automatically; the first write may have succeeded even if its response was lost.

The committed Xcode project is generated. Treat `App/project.yml` as its source of truth and include the regenerated project in the same change.
