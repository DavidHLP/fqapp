# Arch Linux implementation status

Specification: [MIGRATION-SPEC.md](MIGRATION-SPEC.md). Task IDs and dependencies in section 6 are the implementation tickets. GitHub Issues are disabled for this repository; this tracked task graph replaces issue links.

All implementation and runtime acceptance is pending. Planning reviews do not establish runtime readiness.

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
