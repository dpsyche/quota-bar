# Provider ordering and visibility

See the [README](../README.md) for arrow controls and default visibility. Both arrow buttons call the same model-owned move operation; attempts to move beyond a boundary or move an absent provider are no-ops.

`ProviderPresentation` stores the complete order as stable provider IDs, never transient indices or a filtered list. Hidden and absent IDs remain saved; returning providers resume their place. New IDs append in collector order and duplicates are removed. Ordering and filtering are presentation-only: `QuotaSummary`, the image-backed ring and quota thresholds do not consume the filtered list.

## Sign-in evidence

Mapping was checked against Quota AXI 0.1.21's help, published “Provider state” contract and shipped adapters, without live quota/auth collection or credential reads:

- `providers/common.js` maps authenticated successful fetches to `fresh`. Fresh, non-stale success is positive evidence even when no quota window is reported.
- `authStatus: usable` and `expired_refreshable` are positive existing-session evidence, independent of numeric quota.
- `status: auth_required` and `reason: keychain_access_required` override local/cached usability and hide the tile.
- `authStatus: unusable` alone is not definitive logout. The Grok adapter can wrap both sign-out and credential-resolution failures as stale/unusable. **Accepted policy:** previously confirmed providers remain visible with **Sign-in unconfirmed** when current evidence is ambiguous. Ambiguity never admits a never-confirmed provider. Definitive auth-required evidence clears remembered sign-in; later uncertainty cannot restore it without new positive evidence.
- A stale report without explicit auth usability needs prior positive evidence. Provider labels, error prose, quota values and window presence are not auth evidence.

For the collector's failure and fallback behavior, see [How it works](../README.md#how-it-works). The exit-1 exception follows Quota AXI's `commands.js` (`loadQuota`/`isFailed`): the report must be nonempty, use a supported schema (v3 or v5), and contain no provider with `fresh` or `stale` status.

Default schema-v5 JSON omits provider labels, sources, and `sourcesTried`. Display-name fallbacks do not establish sign-in; the same structured state rules above apply without that metadata. New or unknown provenance never establishes auth by itself.

No visibility preference previously existed. Setup and refresh controls remain available when the signed-in list is empty.

## Verification

Use the commands in [Test, build, and package](../README.md#test-build-and-package).

Focused executable tests in `ProviderPresentationTests`, `ProviderTileTests`, and `QuotaCollectorFailureTests` cover both move directions, boundary/missing-ID no-ops, duplicate removal, complete-order persistence through new model/preferences instances, filtering/missing-result reconciliation, sign-in transitions, ambiguous auth with and without prior confirmation, empty-state selection, process failures, and separation from headline calculations. Tests use synthetic collectors and disposable preference domains. See the README procedure above for native ring regression and packaging checks.

The user previously observed arrow reordering working. That is evidence of the tested arrow route, not a claim that VoiceOver or app-relaunch acceptance was performed. Automated persistence tests and native image checks are reported as such. No standalone on-screen accessibility approval is claimed.

Optional safe spot checks use `./scripts/test-native-label.sh --manual`, which prints a unique app/lab path. Identify the synthetic popover by Codex 47%, Cursor combined unknown with a 65% window, and hidden auth-required Claude. Test the arrow buttons, scrolling, refresh and boundary states. To check persistence, quit only that synthetic probe and reopen the same bundle and lab:

```sh
open -n "$APP" --args "$LAB" --manual
```

Only the synthetic lab's `fixture.json` should be edited for sign-in/ambiguity checks; never modify production data or preferences. Keep its unique preference suite until any relaunch check is finished. After quitting the probe, its disposable suite can be removed with `defaults delete "$ID.volatile-inputs"`, where `ID` is read from that probe's plist and verified to start with `local.QuotaBar.NativeTest.`. Do not change macOS permissions or display settings.

Absent CI is a separate delivery fact, not a green check or merge authorization.
