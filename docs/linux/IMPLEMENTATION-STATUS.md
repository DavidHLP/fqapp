# Arch Linux implementation status

Specification: [MIGRATION-SPEC.md](MIGRATION-SPEC.md). Task IDs and dependencies in section 6 are the implementation tickets. GitHub Issues are disabled for this repository; this tracked task graph replaces issue links.

Implementation batches are integrated below; full runtime acceptance remains pending. Planning reviews do not establish runtime readiness.

- [ ] T00/T01: baseline and matching SDK
- [ ] T09/T13: single writer, durable key consistency and strict storage
- [ ] T10/T11: Linux runner, Rust/C and controlled library loading
- [ ] T12/T20–T24: desktop wiring, reading, files, backup and AI/LAN
- [ ] T29–T32: media integration and lifecycle
- [ ] T40–T42: TTS, login, media controls and idle inhibition
- [ ] T50/T51: Arch package and Linux CI
- [ ] T52: clean install, upgrade/recovery and session acceptance
- [ ] T60: independent code review and release gates

No real user data or keyring may be reset for validation. Record skipped/unavailable checks explicitly.

## Native/build integration batch (2026-11-10)

Build foundation and both native commits are merged after the strict storage/bootstrap batch. Runner registers/frees the bridge; Dart preserves owner and seek payloads, explicit transport, and per-owner visibility/suspend intent. login1 initial hints and service name reconnection are wired; `lockEvents=false` remains intentional. Linux video capability stays closed pending T29/D02b.

Full analyze: no issues. Six focused Flutter test files: 62 passed. Native strict whole-object compilation/link and synthetic Cookie test: 1/1 passed. Linux release bundle built with task-local libspeechd; installed RUNPATH is `$ORIGIN/lib`. Task-prefix official Arch packages were signature-verified, with Chinese offline WAV and isolated Speech Dispatcher null-ALSA completion; no audible quality or Flutter native TTS acceptance inferred.

No safe isolated graphical compositor is available on this host: homepage, actual textures/audio/seek/close, Wayland/XWayland/X11, real Secret Service restart, official account login, full media exclusivity and dependable lock/suspend/device reconnection remain unverified. System package installation still requires the main agent/user; no sudo, daily keyring access or user service changes were performed. Packaging/CI remain owned by their workers. Detailed commands and evidence: external `arch-linux-2026-11-10/merge-native-build-handoff.md`.

## Packaging integration batch (2026-11-10): partial

T50/T51 remain partial. Both packaging commits are integrated; native runtime
dependencies now include WebKitGTK 4.1, libspeechd, Speech Dispatcher, espeak-ng
and portal. CI snapshot moved to the available 2026-11-09 set (Rust 1.99.1); OCI
digest and snapshot package metadata were checked, remote CI has not run.
Clean-HEAD build markers, exact source archive, available license inventory and
isolated packaging HOME are implemented. Rust/C/C++ diagnostic remapping and a
neutral source/SDK/cache build reduce personal paths; opaque residual diagnostics
are distinct from loader paths. No string patching or license removal.

Historical packaging-head evidence: full analyze passed; full Flutter suite had
3111 passed, 3 skipped, 370 failed. This is not the current integrated-head result;
see the regression integration batch below.
A neutral-path release rebuild and local binary makepkg completed; source recipe
verification was corrected to allow validation alongside the existing binary pkg.
The complete Flutter suite exposes existing Linux profile
ownership setup failures in storage callers; assertions and the ownership gate
are retained. Fix requires per-test temporary LinuxProfileOwnership acquisition
and release in the affected fixtures, outside packaging ownership. Do not bypass
requireCurrent or call these tests passed. Detailed final-head build/package/FFI
results, failures and concrete artifact paths are recorded externally in
`arch-linux-2026-11-10/merge-packaging-handoff.md` and `merge-packaging-logs/`.
Clean install, remote CI, rights audit and all real session/recovery gates remain
open; makepkg --nodeps is only local package construction.


## Recovery + regression integration batch (2026-11-10)

Started clean at `8f8c9ec8a94f810789772277fc66e9e9189a1a18` on
`feat/arch-linux-desktop`, including `c44c0af` recovery close-drain and
`04a1376` shared-directory permissions. Complete cherry-pick of
`1064618252b72200e2197ddde04d8eac36789589` produced `89e1e9c` without conflicts.
The three previously integrated backup fixtures, production ownership/key guards,
and pubspec.lock are unchanged by this batch. Business fixtures use isolated
ownership and synthetic per-fixture key storage, never the daily keyring.
Security counterexamples retain their own providers and assertions.

Cargo initially failed three core lifecycle tests because their fixtures lacked
a confirmed Linux pool key. Test-only preparation now provisions a synthetic key
through the public API (`9637945`). Because that process-wide key also encrypts
legacy persistence fixture saves, their JSON inspection now decrypts encrypted
files (`eab386e`). Existing field/count/order and raw replacement-marker assertions
remain intact. No production branch, assertion or skip was removed or weakened.
Runtime worker changes in a separate checkout are not included or superseded.

Executed evidence (external directory
`arch-linux-2026-11-10/merge-regression-logs/`; final SHA, exact commands and
same-HEAD confirmation are in `merge-regression-handoff.md`):

- Full Flutter analyze: no issues.
- Full Flutter suite: **3510 passed, 0 failed, 3 original skips**, 3513 unique
  behavioral tests (suite path + test name), no unfinished tests; full run included
  the real FFI and recovery fixtures. Historical worker totals are not summed.
- Real FFI: 9 unique behavioral tests passed, 0 failed, 0 skipped; the host library
  was explicitly `/home/david/Projects/fqapp/build/linux/x64/release/bundle/lib/libfqapi_core.so`.
  FFI counts overlap the full suite and must not be added to it.
- Cargo locked full suite: 262 passed, 0 failed, 2 existing live-upstream ignored;
  doc tests contained 0 tests. Strict no-key/wrong-key integration remained enabled.
- Native AES/CENC/real encoded media/audio diagnostics: 102 passed, 0 failed,
  0 skipped across the existing four CENC-related Node files.
- Linux release rebuild: succeeded, producing `build/linux/x64/release/bundle/fqapp`
  with the inherited task-local libspeechd dependency prefix. No package/install
  or clean-machine acceptance inferred.

Original Flutter skips remain separate from passed tests: Windows SDK semantics
backport requires the patched SDK define; pagination preview requires
`READER_PREVIEW_FONT`; real-home parsing requires `build/home_raw.json` captured
sample. Cargo `live_search_then_titlepage` / `live_toc_then_chapter` are not run
against the live upstream.

All test scratch files use the new task-only external `merge-regression-tmp`
directory to avoid the known /tmp quota issue. No other temporary files, user
artifacts, worktrees or profile/keyring data were deleted or moved. Earlier Cargo
failures remain in the logs and are not counted as passes.

T52/T60 and runtime gates remain open: no real Wayland/XWayland/X11 GUI,
account/Secret Service acceptance, VM power loss, physical ENOSPC/EACCES,
clean install/upgrade/rollback, remote CI or release approval was performed.
Automated regression/build success does not establish those gates or complete
the migration task graph. No push, PR, watch or delegation in this batch.
