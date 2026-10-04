# App icon

HKRelay uses an original off-white house with two Wi-Fi cutouts and a dot, a subtle bevel and shadow, and a warm orange gradient. The artwork was refined with the built-in image-generation tool using the earlier icon and a comparison screenshot as visual references, then resized to a 1024 × 1024 opaque PNG for the asset catalog. Reference screenshots are not included in the repository. The icon does not use an exported SF Symbol.

The source asset is `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`. Xcode produces the macOS icon from this asset. Keep the source square and opaque; the operating system applies the icon mask.

## Refinement prompt

```text
Use case: precise-object-edit. Image 1 is the current HomeKitLink app icon to improve. Image 2 is a screenshot of neighboring Mac app icons; it is ONLY a style and scale reference, not an edit target. Return exactly ONE finished 1024x1024 app-icon asset, not a screenshot or grid. Retain the original custom white house with integrated Wi-Fi negative space and an orange background, but polish it to sit naturally alongside high-quality Mac apps. Enlarge the house modestly to about 72% of canvas width and optically center it. Simplify the Wi-Fi cutout to TWO broad smooth arcs and one generous round dot, clearly readable at 32px. Make the house a clean off-white porcelain-like shape with a very subtle shallow bevel, bright upper edge, and delicate short soft shadow beneath it, just enough depth to feel crafted. No exaggerated 3D or perspective. Use a smooth warm orange vertical gradient, luminous amber-orange #FFB02E at top to rich orange #F58200 at bottom; quiet saturation, no yellow spotlight or texture. Clean, confident geometric silhouette, rounded corners and harmonious negative space. Preserve a distinct ORIGINAL house design, not any exported Apple SF Symbol, existing app icon, or HomeKit logo. No text, letters, border, extra objects, watermark, long shadow, metallic sheen, or glass effects. IMPORTANT: background fills every pixel of the square canvas including all four corners; do not draw a rounded-square tile, transparent margin, or outer app-icon shadow. macOS applies that exterior mask. Only the house glyph has a subtle shadow. Match the refinement and strong visual presence of the screenshot's app icons while retaining the simplicity of Image 1.
```

## Menu bar icon

The helper uses `MenuBarHelper/Resources/Assets.xcassets/MenuBarTemplate.imageset`, an 18-point template with 1× and 2× PNGs. It preserves the app artwork’s house silhouette, two Wi-Fi cutouts, and dot inside the house. macOS supplies the foreground color; the icon dims when the bridge is unavailable.

The built-in image-generation tool extracted a flat black shape on transparency from the app icon. The result was cropped to its alpha bounds and resized for the menu bar using AppKit.

Extraction prompt: Preserve the existing house geometry and proportions, rounded corners, two broad Wi-Fi arch cutouts, and circular dot cutout inside the house. Render the house solid black with a fully transparent background and cutouts. Remove the orange background, shading, bevel, and shadows. Do not substitute an SF Symbol or move the Wi-Fi outside the house.
