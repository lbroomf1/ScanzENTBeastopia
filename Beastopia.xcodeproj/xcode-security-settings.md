# Xcode Security Settings

Security build settings and app-hardening decisions for Beastopia. Last reviewed 2026-11-14.

## Enabled settings

Already active before this review (Xcode defaults kept):

- `GCC_WARN_ABOUT_RETURN_TYPE` to `YES_ERROR`
- `GCC_WARN_UNINITIALIZED_AUTOS` to `YES_AGGRESSIVE`
- `GCC_WARN_64_TO_32_BIT_CONVERSION`
- `ENABLE_USER_SCRIPT_SANDBOXING`
- `SWIFT_DISABLE_SAFETY_CHECKS` stays `NO` (Swift bounds and overflow checks on in every build)
- App Transport Security at its defaults (no arbitrary-load exceptions)

## Disabled settings

None.

## Deferred

Settings considered but not yet enabled. Revisit them later.

- `ENABLE_ENHANCED_SECURITY`:
  The project is signed by a personal development team, and Apple doesn't provide the Enhanced Security
  capability to personal teams ("Personal development teams ... do not support the Enhanced Security capability").
  Adding it broke signing, so it was reverted. Enable it at the project level after moving to a paid
  Apple Developer Program team. It brings pointer authentication (arm64e), stack zero-initialization,
  typed allocators and security compiler warnings.
- `com.apple.security.hardened-process` entitlements (`enhanced-security-version-string` 2, `hardened-heap`,
  `dyld-ro`, `platform-restrictions-string` 2):
  Same reason. Add them with the capability above.
- `com.apple.security.hardened-process.checked-allocations` (hardware memory tagging, with `soft-mode`):
  Needs the Enhanced Security capability. Start in soft mode once it's available.
- `ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE` and
  `com.apple.security.hardened-process.checked-allocations.enforce-checked-pointer-arithmetic-overflow`:
  Needs Enhanced Security and hardware memory tagging. Test on A20 Pro or later hardware before shipping,
  because a latent pointer-arithmetic bug terminates the app.
- `com.apple.developer.nfc.readersession.formats` (`TAG`):
  Also unavailable to personal teams. NFC Challenge Cards are switched off with `ChallengeCardNFC.isEntitled = false`.
- C and Objective-C warnings, static analyzer and clang-tidy checks:
  Not applicable. Beastopia is pure Swift. Revisit if C, C++ or Objective-C code is added.

## App code hardening

Changes made in code during this review:

- Beasts from other players (Game Center, Nearby, Challenge Cards) go through `MultiplayerManager.sanitized`.
  It gives them a fresh ID; clamps stats (1–999), level (1–99), XP, bond, fatigue, wins and losses; replaces
  a non-finite hue; and caps the nickname (20 characters) and origin tag (24). The battle engine only reads
  species, stats and level, so lockstep battles stay deterministic.
- Peers sending more than 60 messages a second are disconnected (`MultiplayerManager.maxMessagesPerSecond`).
  Messages over 16 KB are dropped.
- The save file is written atomically with `completeFileProtectionUntilFirstUserAuthentication`
  (encrypted while the device is locked after a restart).
- Errors go to `Logger` with private details instead of `print`.

Reviewed and fine: no web views, URL schemes or pasteboard access; Nearby sessions require encryption and only pair
with the same build and match type; Challenge Card text is length-capped and validated; scanned codes are hashed
and never opened; the privacy manifest declares UserDefaults (CA92.1) and no tracking.

## Accepted risks

- Draft YouTube episode codes are in plain text in a public GitHub repository, by choice. Anyone can claim those
  beasts early. Replace them with final codes kept out of the public repo before episodes air.
- The local save file can be edited on a jailbroken device or by restoring a modified backup. Single-player only;
  online beasts are still clamped.
- Claimed-code fingerprints are unsalted SHA-256, so short barcodes in a copied save could be guessed. Salting now
  would let every code be claimed again.
- Nearby peers aren't authenticated. Anyone nearby on the same build and match type can join, by design.
- Online and Challenge Card stats are only range-clamped. A modified client can send strong but in-range stats.
  Real protection needs server validation or level-normalized Versus.
