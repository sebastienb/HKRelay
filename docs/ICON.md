# App icon

HomeKitLink uses an original white house with Wi-Fi cutouts on an orange background. The artwork was made with the built-in image-generation tool, then resized to a 1024 × 1024 opaque PNG for the asset catalog. It does not use an exported SF Symbol.

The source asset is `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`. Xcode produces the macOS icon from this asset. Keep the source square and opaque; the operating system applies the icon mask.

## Generation prompt

```text
Use case: logo-brand. Create ONE production app-icon asset, square 1024 by 1024, full-bleed opaque solid warm orange background (#FF9500). Center one extremely simple, original white house-and-Wi-Fi glyph, taking about 56% of the width, with generous even margins. The house is a custom, compact rounded geometric house silhouette, symmetric pitched roof, no chimney. Three broad, clean orange Wi-Fi arcs and a round dot are cut into the white house body as negative space, with enough thickness and spacing to read at 32 pixels. The Wi-Fi motif is integrated within the house, not attached as an external circle badge. Flat vector-like design with precise smooth edges. No text, no letters, no watermark, no border, no gradients, no shadow, no 3D, no glass, no texture, no extraneous ornaments. Do NOT reproduce an Apple SF Symbol, Apple's Home app icon, or HomeKit logo; this must be a distinct original house/wireless mark. The orange must extend to all four square corners: do not pre-round or mask the outside edges; the operating system adds its app-icon mask. Render the actual icon only, not a mockup, on the entire canvas.
```

