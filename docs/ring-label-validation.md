# Ring label correction: local validation

The correction retains the existing SwiftUI `MenuBarExtra`, window-style quota popover, model, collector, and refresh schedule. The label now supplies an original-color `Image` with non-template 20×18-point native bitmaps at 1x/2x. The hollow three-point stroke fits within both representations. Accessibility/help descriptions still come from the changing model headline; no text was added to the ring.

## Results

- `swift test`: 23 tests passed, including four palette colors, transparent center/edges at both scales, threshold boundaries, unknown/auth-required exclusion, and stale cached known quota remaining neutral.
- `./scripts/test-native-label.sh`: passed with the real scene and synthetic dependencies. The native button has an image with nonempty ring pixels while the three-second collector is still running. Pixel bytes change after refresh; invoking the native button action constructs the actual quota popover.
- Negative control: temporarily restored the original unconditional `Circle().stroke(...)` label and ran the same native script. It failed with `native button image=nil`. Restored the image label and reran successfully.
- `./scripts/build-app.sh`: release packaging, plist validation, and strict/deep ad-hoc signature verification passed. Release artifact: `build/QuotaBar.app`.
- `git diff --check`: passed.

The first raster test caught double scaling of the 2x bitmap context; removing the redundant transform fixed it. Both scales now pass the pixel/color/bounds assertions.

## Evidence limits and safety

Only newly built, uniquely identified probe bundles were launched. Each automated launch used a synthetic collector, its own cache, and a separate volatile defaults suite distinct from its bundle ID. The automated probe self-terminates and has an independent process watchdog. No installed application, production preferences, permissions, display configuration, or live quota data were changed. No notifications were introduced.

These results establish native button content and action behavior, not physical-screen visibility, contrast, Retina appearance, or pointer interaction. The diagnosis reported unavailable Screen Recording/Accessibility access; no grants were requested and no physical-display approval is claimed. Follow the isolated `--manual` procedure in [README](../README.md#test-build-and-package) for remaining visual/pointer acceptance. Do not launch or install the production-identity release bundle over a running user installation during automated verification.
