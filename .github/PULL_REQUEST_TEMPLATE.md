## What this changes

<!-- One subject per PR. What did you change, and why? -->

## How you verified it

<!-- Say what you actually ran. "838 tests pass" and "measured maximized at 4K"
     are the useful kind; a rendering change is worth a screenshot. -->

- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `flutter analyze --fatal-infos` (a lint **info** fails CI)
- [ ] `flutter test`
- [ ] Ran the app on: <!-- windows / macos / linux -->

## Checklist

- [ ] New libraries sit in their feature's folder, with the test at the mirrored
      path under `test/` ([CLAUDE.md § Source layout](https://github.com/Joycai/Jellyfin-Media-Management-Tool/blob/main/CLAUDE.md#source-layout))
- [ ] New user-facing strings are in **both** `app_en.arb` and `app_zh.arb`
- [ ] No literal colours, radii, sizes, font sizes or durations in a widget —
      a deliberate one-off names the spec section it came from
- [ ] Anything writing to disk goes through `applyOrganizeAction` or
      `MetadataWriter`, and validates with `PathSafety.isWithin`
- [ ] CLAUDE.md updated if this invalidates something it asserts
- [ ] User-facing change noted in `CHANGELOG.md` under `Unreleased`
