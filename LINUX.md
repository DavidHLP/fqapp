# Linux / Arch x86_64 (draft)

This is a local validation package, not an approved full Linux release. Do not
publish it to AUR or a formal release until native bridge integration, actual
Wayland/XWayland/X11 product tests, account acceptance, clean install/upgrade/
downgrade/data-preserving uninstall, recovery, source licensing and signing are
complete on the same final head. Compilation or a headless CI pass proves none
of these. Existing ignored upstream tests are not counted as passed.

Use official unmodified Flutter 3.47.9 (revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`, Dart 3.13.7), Rust 1.99.1 and locked
FRB 2.13.0. Local SDK: `/home/david/.local/share/fqapp-toolchains/flutter-3.47.9`.
No global SDK/PATH or system package changes are needed by the packaging script.
Build prerequisites must already exist: base-devel, clang, cmake, ninja, pkgconf,
GTK3, Rust and the runtime libraries in packaging/arch/PKGBUILD. Packaging also
needs Python, patchelf, binutils, zstd and desktop-file-utils.

```bash
export FLUTTER_ROOT=/home/david/.local/share/fqapp-toolchains/flutter-3.47.9
export PATH="$FLUTTER_ROOT/bin:$PATH"
flutter precache --linux
flutter pub get --enforce-lockfile
cargo fetch --manifest-path rust/Cargo.toml --locked
flutter analyze --no-pub
cargo test --manifest-path rust/Cargo.toml --locked
cargo build --manifest-path rust/Cargo.toml --release --locked
export FQAPP_RUST_HOST_LIB="$PWD/rust/target/release/libfqapi_core.so"
flutter test --no-pub test/rust_host_integration_test.dart
flutter test --no-pub
node --test test/verify_audio_cenc_test.cjs
python scripts/verify_windows_media.py
CARGO_NET_OFFLINE=true flutter build linux --release --no-pub
bash scripts/build_linux_package.sh build/linux/x64/release/bundle build/arch-package HEAD
```

The script requires a **new output directory**, leaves its input bundle intact,
normalizes ELF RUNPATH only in a staging copy, validates all bundle ELF closure
and desktop metadata, then runs makepkg without installing dependencies or
starting the app. Never pass untrusted binaries (ldd inspects trusted builds).
The supplied commit identifies the bundle's source; the script records it but
cannot establish provenance of a caller-supplied bundle. Use the actual build
commit; CI always builds the checked-out head with no restored binary cache.

Outputs: `.pkg.tar.zst`, populated binary `PKGBUILD`, `.SRCINFO`, checksum-pinned
local `fqapp-bundle.tar.zst`, ELF report, build manifest and package `.BUILDINFO`.
To repeat binary packaging, retain the archive and generated PKGBUILD, and run
`makepkg` in that directory on the recorded Arch snapshot. `--nodeps` used by the
script only permits local packaging; it is not a clean install test.

For a **source rebuild**, use `packaging/arch/PKGBUILD` with a local
`git archive --format=tar --prefix=fqapp/ COMMIT | zstd -o fqapp-source.tar.zst`,
replace its all-zero checksum placeholder with that archive's SHA256, and run makepkg
with `FLUTTER_ROOT` exported. The archive must include the Linux build foundation
and this packaging change. Pre-fetch the exact pub/Cargo/Flutter engine caches
using the commands above; `build()` enforces offline locked dependency use.
SDK is an externally verified toolchain, not an unversioned AUR Flutter package.
Source and binary recipes share the same install layout. Two independent clean
builds have not been compared: no bit-for-bit reproducibility claim.

Install only in a disposable Arch acceptance environment with pacman, after
reviewing `pacman -Qip` / `pacman -Qlp`. The package installs under `/usr/lib/fqapp`
and `/usr/share`; it never stores user data there. `/usr/bin/fqapp` works from
any cwd and forwards arguments unchanged. No unsupported file/URL association is
registered. Encryption requires a working Secret Service provider; configure a
portal backend and Chinese speech engine as appropriate for the final native
bridge. Missing services must remain application errors, not plaintext fallback.

See [dependency and license inventory](packaging/arch/DEPENDENCIES.md).
CI uses a digest-pinned Arch container and 2026-11-10 repository snapshot,
checks the exact SDK checksum and compiler version, caches only dependency
sources, and uploads draft packages with automatic test evidence. Its Ubuntu
host is not Ubuntu-native build evidence or GUI acceptance. No release publish
permission or release action is present. Other platform regressions run in their
existing workflows and must also pass before release.

The supplied foundation bundle still embeds developer source paths in Rust panic,
C++ assertion and Dart AOT diagnostics. RUNPATH normalization does not remove
these strings. They are a draft artifact limitation: rebuild in a neutral clean
source/cache path, remap Rust/C++ diagnostics, and re-scan before final delivery.
