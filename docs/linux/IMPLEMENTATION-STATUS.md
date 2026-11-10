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
