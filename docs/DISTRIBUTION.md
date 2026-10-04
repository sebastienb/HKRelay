# Distribution

HKRelay is being released as experimental MIT-licensed source. A public source repository does not mean a binary is approved for App Store or direct distribution. Developers need their own local HomeKit signing configuration.

## Product name

The project is named HKRelay. HomeKit is used descriptively to identify the technology it supports. The former name incorporated Apple's HomeKit mark directly; the rename avoids that wording. No formal trademark clearance has been performed for HKRelay, and the MIT license does not grant rights to Apple's trademarks. Apple's third-party trademark guidelines distinguish descriptive compatibility references from product branding.

## HomeKit data and off-device use

Apple Developer Program License Agreement section 3.3.3(I) restricts exporting, remotely accessing, or transferring HomeKit information off the applicable product unless Apple expressly permits it in documentation. LAN clients and cloud-connected agents raise an unresolved distribution/compliance question. Do not advertise those workflows as Apple-approved or submit a binary claiming they are approved. Obtain confirmation from Apple for the intended behavior; user consent and an open-source license alone do not establish an exception.

These constraints were checked against Apple's published agreement and capability matrix on October 4, 2026. The agreement accepted in your developer account is authoritative for your use.

## App Store and TestFlight

1. Register an explicit App ID for the release bundle identifier in the Apple Developer portal.
2. Enable HomeKit for that identifier and let Xcode manage the Mac Catalyst provisioning profile.
3. Copy `App/Config/Local.xcconfig.example` to the ignored `App/Config/Local.xcconfig` and set the release bundle identifier and developer team.
4. Run the repository checks:

   ```sh
   ./scripts/check.sh
   ```

5. In Xcode, select the HKRelay scheme and **My Mac (Mac Catalyst)**, then choose **Product > Archive**.
6. In Organizer, generate and review the privacy report, validate the archive, and confirm that the main app and embedded menu-bar helper are signed by the intended distribution team.
7. Distribute the first build through TestFlight before submitting it to App Review.

The App Store listing still needs a public privacy policy URL, support URL, screenshots, description, category, age rating, and App Review notes explaining the local API, opt-in LAN access, and deny-by-default accessory permissions.

## Direct website distribution

Normal direct Mac distribution requires a Developer ID signature, hardened runtime, notarization, and a stapled notarization ticket. However, Apple's current macOS capability matrix lists HomeKit for Apple Developer Program profiles and not for Developer ID profiles.

Do not sell or publish a direct-download build until Apple Developer Support confirms a supported way to preserve the HomeKit entitlement outside the Mac App Store. An unsigned or ad-hoc-signed build is not a substitute: Gatekeeper rejects it and HomeKit authorization is not available as a reliable customer experience.

If Apple approves a direct-distribution path, validate the exported artifact before release:

```sh
codesign --verify --deep --strict --verbose=2 "HKRelay.app"
codesign -dvvv --entitlements :- "HKRelay.app"
spctl --assess --type execute --verbose=4 "HKRelay.app"
xcrun stapler validate "HKRelay.app"
```

Inspect the nested helper separately and verify that neither executable contains the development-only `com.apple.security.get-task-allow` entitlement.

## Private signing material

Never commit developer-team identifiers, certificates, provisioning profiles, App Store Connect keys, notarization credentials, or `Local.xcconfig`. Automated release signing should use protected CI secrets and a dedicated distribution identity.

## Apple references

- [Supported capabilities for macOS](https://developer.apple.com/help/account/reference/supported-capabilities-macos)
- [Distributing apps for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)

- [Apple trademark guidelines](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)
- [Apple trademark list](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html)
