# Quota Bar

Quota Bar is a native, menu-bar-only macOS app for seeing local AI-service quota without running a terminal command. Its ring shows the tightest **known effective** quota; click it for exact percentages, limiting windows, resets, pace, runway, and collection/authentication state for every service reported by [Quota AXI](https://www.npmjs.com/package/quota-axi).

- Green: 50% remaining or more
- Yellow: 20–49% remaining
- Red: below 20%
- Gray: unavailable, unknown, authentication-required, or stale

Unknown values are never treated as zero. Quota Bar sends no notifications or alerts.

## Requirements and setup

- macOS 13 Ventura or newer. macOS 13 is the deployment target because it is the oldest release with SwiftUI `MenuBarExtra`.
- Swift 6.0 or newer and the macOS Command Line Tools for building.
- [`quota-axi`](https://www.npmjs.com/package/quota-axi) installed locally (Node.js 22.19 or newer is required by Quota AXI).

Quota Bar discovers `quota-axi` in this order:

1. A path selected in Quota Bar
2. The inherited `PATH`
3. Homebrew, MacPorts, `~/.local/bin`, `~/bin`, npm-global, and pnpm locations
4. NVM Node installations under `~/.nvm/versions/node`, newest version first

Every candidate must resolve to a regular executable file. If discovery fails, click the ring, then **Choose quota-axi…** in the setup card or gear menu. The selected location is stored in app preferences; credentials are not.

## Test, build, and package

No Xcode UI steps are needed:

```sh
swift test
./scripts/build-app.sh
```

The packaging script makes an ad-hoc-signed app at `build/QuotaBar.app` and verifies its property list and signature. Set `CONFIGURATION=debug` to package a debug build; release is the default.

## Install and launch

```sh
./scripts/install.sh
```

This builds, installs, and opens `~/Applications/QuotaBar.app`. After that, launch **Quota Bar** normally from Finder or Applications; all quota checks and refreshes happen inside the app. Use `./scripts/install.sh --no-launch` to install without opening it. To install elsewhere:

```sh
QUOTABAR_INSTALL_DIR=/Applications ./scripts/install.sh
```

The app has no Dock icon. Its menu-bar ring refreshes at launch, on **⌘R** or the refresh button, and every 15 minutes while running.

## How it works

- **Native shell:** `Sources/QuotaBar` uses the SwiftUI app lifecycle and a window-style `MenuBarExtra`.
- **Data and policy:** `Sources/QuotaBarCore` owns Quota AXI schema v3 decoding, effective-quota selection, thresholds, executable discovery, bounded process execution, and snapshot state.
- **Collection:** Quota Bar launches the discovered executable directly with the single argument `--json`; it never invokes a shell. The executable's directory and deterministic local binary locations are added to the child `PATH` so Finder launches can run NVM/npm installations.
- **Bounds:** a collector run has a 45-second deadline and a combined 2 MiB stdout/stderr limit. Nonzero exits, malformed JSON, unsupported schemas, timeouts, and excess output become in-app collection failures.
- **Truthful fallback:** only current, known `effectiveAvailability` values contribute to the ring. Unresolved relationships remain unknown and cards show each reported window separately. A transient failure retains the last successful snapshot, turns the ring gray, and labels the data stale with its timestamp.

## Data source and privacy

`quota-axi --json` is the only quota source. Quota AXI continues to read the user's existing provider credential sources and contact provider endpoints; Quota Bar does not read, store, copy, import, or log provider credentials.

Quota Bar does not request Quota AXI's `--full` output, so account identity is omitted. The last decoded report (quota percentages, provider state, and collection-source labels, not credentials) is stored with user-only permissions at `~/Library/Application Support/QuotaBar/snapshot-v3.json`. No live quota output, machine path, token, or credential is committed in this repository's tests or fixtures.

There are no first-release notifications, alerts, analytics, or third-party relays.

## Troubleshooting

### The ring is gray and setup says Quota AXI was not found

Open the popover, choose **Choose quota-axi…**, and select the installed executable. This is especially useful when Finder's restricted `PATH` differs from a terminal's environment. The gear menu can return to automatic discovery later.

### A service says authentication or Keychain access is required

Quota Bar intentionally uses existing Quota AXI/provider credential sources and does not perform provider sign-in. Follow the provider state shown in the card. For Claude, Quota AXI may require its documented one-time `quota-axi --allow-keychain-prompt` approval before unattended reads can use an existing Keychain credential.

### The last snapshot is stale

The previous successful values remain visible but are excluded from the colored headline. Try the refresh button. Quota Bar reports whether the executable is missing, timed out, exited unsuccessfully, emitted too much output, or returned incompatible data without erasing the snapshot.

### The app will not open after a local build

Rebuild with `./scripts/build-app.sh` and verify macOS 13 or later is in use. The script runs `plutil`, ad-hoc signs the bundle, and verifies the signature before it succeeds.
