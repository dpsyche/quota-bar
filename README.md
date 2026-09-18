# Quota Bar

Quota Bar is a native, menu-bar-only macOS app for seeing local AI-service quota without running a terminal command. Its ring shows the tightest **known effective** quota; click it for exact percentages, limiting windows, resets, pace, runway, and collection/authentication state for signed-in services reported by [Quota AXI](https://www.npmjs.com/package/quota-axi).

- Green: 50% remaining or more
- Yellow: 20–49% remaining
- Red: below 20%
- Gray: unavailable, unknown, authentication-required, or stale

Unknown values are never treated as zero. Quota Bar sends no notifications or alerts.

Use the **up/down arrow buttons** on each provider tile to move it earlier or later. The buttons have keyboard-accessible actions and provider-specific accessibility labels; boundary moves are disabled. Order is saved locally across popover reopening, refresh, and app relaunch. Hidden or temporarily absent providers keep their place, and new providers append in collector order.

Only providers with structured evidence of sign-in are shown by default. Confirmed authentication-required or Keychain-access-required providers are hidden. Previously confirmed providers with ambiguous evidence remain visible as **Sign-in unconfirmed**, with quota uncertainty/staleness still explicit. Ambiguity alone never admits a never-confirmed provider, and refreshable credentials are not treated as sign-out. If none qualify, the popover explains how to sign in and refresh. Filtering and ordering do not change the ring's quota calculation.

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
# In a logged-in macOS desktop session:
./scripts/test-native-label.sh
```

The packaging script makes an ad-hoc-signed app at `build/QuotaBar.app` and verifies its property list and signature. Set `CONFIGURATION=debug` to package a debug build; release is the default.

The native regression launches a uniquely identified, signed disposable app under `build/native-label.*`, using the real scene/label/popover with a delayed synthetic collector, isolated cache, and disposable test preferences (the executable path is a volatile input). It asserts a nonempty native ring image during loading, changed pixels after refresh, and popover appearance after invoking the button action. It exits within a bounded deadline and never launches the live collector or modifies the installed app. Test instrumentation is excluded from normal builds. `swift test` also checks ring colors and stroke bounds at 1x/2x, headline policy, and core behavior.

The native script uses the legacy fixture by default. To exercise the current format, run `QUOTABAR_TEST_FIXTURE=Tests/QuotaBarCoreTests/Fixtures/quota-v5.json ./scripts/test-native-label.sh` from the repository root. Use only synthetic fixtures with this override.

Native button/pixel/action checks are **not physical-screen acceptance**. For safe manual acceptance, run `./scripts/test-native-label.sh --manual` (the synthetic probe remains open):

1. Observe a gray loading ring, then yellow after collection, with no adjacent text.
2. Click that ring with the pointer; verify quota cards, dismissal/reopening, and the refresh button. Refresh must stay responsive during the three-second synthetic delay.
3. Check visibility and contrast on light/dark menu bars and available 1x/2x displays, including an uncrowded menu bar near the notch. Do not change permissions or display configuration for automation.
4. Quit only the synthetic probe from its popover. Its printed bundle/cache directory is disposable.

See [Provider ordering and visibility](docs/provider-ordering.md) for the structured auth mapping, focused tests, and optional safe arrow/persistence checks.

This script requests no Screen Recording or Accessibility grants. Real pointer interaction, display compositing, and visual approval remain manual; passing native checks or screenshots alone do not establish them.

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
- **Data and policy:** `Sources/QuotaBarCore` owns Quota AXI schema v3 and v5 decoding, effective-quota selection, thresholds, executable discovery, bounded process execution, and snapshot state.
- **Collection:** Quota Bar launches the discovered executable directly with the single argument `--json`; it never invokes a shell. The executable's directory and deterministic local binary locations are added to the child `PATH` so Finder launches can run NVM/npm installations.
- **Bounds:** a collector run has a 45-second deadline and a combined 2 MiB stdout/stderr limit. Nonzero exits, malformed JSON, unsupported schemas, timeouts, and excess output become in-app collection failures. The exception is Quota AXI's all-providers-failed exit 1 with a valid supported-schema report that is nonempty and contains no provider with `fresh` or `stale` status: Quota Bar consumes its structured states so signing out of the last provider does not retain an obsolete signed-in snapshot.
- **Format compatibility:** current default JSON (schema v5) omits some display and provenance metadata, including provider labels, sources, and `sourcesTried`. Quota Bar supplies display names from provider IDs and leaves missing provenance and quota values unknown. Unsupported versions are reported before attempting to decode their provider data.
- **Truthful fallback:** only current, known `effectiveAvailability` values contribute to the ring. Unresolved relationships remain unknown and cards show each reported window separately. A transient failure retains the last successful snapshot, turns the ring gray, and labels the data stale with its timestamp.

## Data source and privacy

`quota-axi --json` is the only quota source. Quota AXI continues to read the user's existing provider credential sources and contact provider endpoints; Quota Bar does not read, store, copy, import, or log provider credentials.

Quota Bar does not request Quota AXI's `--full` output, so account identity is omitted. App preferences store stable provider IDs for tile order and previous positive sign-in evidence, not credentials or identities. The last decoded report (quota percentages, provider state, and collection-source labels, not credentials) is stored with user-only permissions at `~/Library/Application Support/QuotaBar/snapshot-v3.json`. The filename is retained for upgrade compatibility: existing v3 snapshots still load, and current v5 snapshots round-trip at the same path. Either starts stale until a successful refresh. No live quota output, machine path, token, or credential is committed in this repository's tests or fixtures.

There are no first-release notifications, alerts, analytics, or third-party relays.

## Troubleshooting

### The ring is gray and setup says Quota AXI was not found

Open the popover, choose **Choose quota-axi…**, and select the installed executable. This is especially useful when Finder's restricted `PATH` differs from a terminal's environment. The gear menu can return to automatic discovery later.

### A service says authentication or Keychain access is required

Quota Bar intentionally uses existing Quota AXI/provider credential sources and does not perform provider sign-in. Authentication-required providers are hidden by default. Sign in through the provider's existing app or CLI, then refresh Quota Bar. For Claude, Quota AXI may require its documented one-time `quota-axi --allow-keychain-prompt` approval before unattended reads can use an existing Keychain credential.

### The last snapshot is stale

The previous successful values remain visible but are excluded from the colored headline. Try the refresh button. Quota Bar reports whether the executable is missing, timed out, exited unsuccessfully, emitted too much output, or returned incompatible data without erasing the snapshot.

### The app will not open after a local build

Rebuild with `./scripts/build-app.sh` and verify macOS 13 or later is in use. The script runs `plutil`, ad-hoc signs the bundle, and verifies the signature before it succeeds.
