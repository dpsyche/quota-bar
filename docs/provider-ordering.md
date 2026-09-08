# Provider ordering and visibility

Each tile has up/down arrow buttons that call the same model-owned move operation. Buttons at the boundaries are disabled; attempts to move beyond a boundary or move an absent provider are no-ops. The buttons use standard SwiftUI actions, keyboard focus, help text and provider-specific accessibility labels.

`ProviderPresentation` stores the complete order as stable provider IDs, never transient indices or a filtered list. Hidden and absent IDs remain saved; returning providers resume their place. New IDs append in collector order and duplicates are removed. Ordering and filtering are presentation-only: `QuotaSummary`, the image-backed ring and quota thresholds do not consume the filtered list.

## Sign-in evidence

Mapping was checked against Quota AXI 0.1.21's help, published “Provider state” contract and shipped adapters, without live quota/auth collection or credential reads:

- `providers/common.js` maps authenticated successful fetches to `fresh`. Fresh, non-stale success is positive evidence even when no quota window is reported.
- `authStatus: usable` and `expired_refreshable` are positive existing-session evidence, independent of numeric quota.
- `status: auth_required` and `reason: keychain_access_required` override local/cached usability and hide the tile.
- `authStatus: unusable` alone is not definitive logout. The Grok adapter can wrap both sign-out and credential-resolution failures as stale/unusable. **Accepted policy:** previously confirmed providers remain visible with **Sign-in unconfirmed** when current evidence is ambiguous. Ambiguity never admits a never-confirmed provider. Definitive auth-required evidence clears remembered sign-in; later uncertainty cannot restore it without new positive evidence.
- A stale report without explicit auth usability needs prior positive evidence. Provider labels, error prose, quota values and window presence are not auth evidence.

Quota AXI's `commands.js` (`loadQuota`/`isFailed`) exits 1 while emitting a structured report when all providers are neither fresh nor stale. The collector accepts this specific valid schema-v3 report to observe last-provider sign-out and show the empty state. Invalid output, other exit codes and exit-1 reports containing successful providers remain collection failures. Whole-process failures retain the last snapshot with explicit staleness; provider failures do not invent zero quota.

No visibility preference previously existed. Setup and refresh controls remain available when the signed-in list is empty.

## Verification

Run:

```sh
swift test
./scripts/test-native-label.sh
./scripts/build-app.sh
```

Focused executable tests cover both move directions, boundary/missing-ID no-ops, duplicate removal, complete-order persistence through new model/preferences instances, filtering/missing-result reconciliation, sign-in transitions, ambiguous auth with and without prior confirmation, empty-state selection, process failures, and separation from headline calculations. Tests use synthetic collectors and disposable preference domains. The existing native ring regression checks image pixels and opening the real popover; packaging checks the release bundle's plist and signature.

The user previously observed arrow reordering working. That is evidence of the tested arrow route, not a claim that VoiceOver or app-relaunch acceptance was performed. Automated persistence tests and native image checks are reported as such. No standalone on-screen accessibility approval is claimed.

Optional safe spot checks use `./scripts/test-native-label.sh --manual`, which prints a unique app/lab path. Identify the synthetic popover by Codex 47%, Cursor combined unknown with a 65% window, and hidden auth-required Claude. Test the arrow buttons, scrolling, refresh and boundary states. To check persistence, quit only that synthetic probe and reopen the same bundle and lab:

```sh
open -n "$APP" --args "$LAB" --manual
```

Only the synthetic lab's `fixture.json` should be edited for sign-in/ambiguity checks; never modify production data or preferences. Keep its unique preference suite until any relaunch check is finished. After quitting the probe, its disposable suite can be removed with `defaults delete "$ID.volatile-inputs"`, where `ID` is read from that probe's plist and verified to start with `local.QuotaBar.NativeTest.`. Do not change macOS permissions or display settings.

GitHub currently reports no workflows/check runs/statuses on the default branch. Absent CI is a separate delivery fact, not a green check or merge authorization.
