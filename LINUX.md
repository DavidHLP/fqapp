# Linux / Arch x86_64 (draft)

This is a local validation package, not an approved full Linux release. Do not
publish it to AUR or a formal release until actual
Wayland/XWayland/X11 product tests, account acceptance, clean install/upgrade/
downgrade/data-preserving uninstall, recovery, source licensing and signing are
complete on the same final head. Compilation or a headless CI pass proves none
of these. Existing ignored upstream tests are not counted as passed.

Use official unmodified Flutter 3.47.9 (revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`, Dart 3.13.7), Rust 1.99.1 and locked
FRB 2.13.0. Use a neutral SDK location such as `/tmp/fqapp-release/sdk`.
No global SDK/PATH or system package changes are needed by the packaging script.
Build prerequisites must already exist: base-devel, clang, cmake, ninja, pkgconf,
GTK3, Rust and the runtime libraries in packaging/arch/PKGBUILD. Packaging also
needs Python, patchelf, binutils, zstd and desktop-file-utils.

```bash
export FLUTTER_ROOT=/tmp/fqapp-release/sdk
export PUB_CACHE=/tmp/fqapp-release/pub-cache
export HOME=/tmp/fqapp-release/home
export DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent
export PATH="$FLUTTER_ROOT/bin:$PATH"
flutter precache --linux
flutter pub get --enforce-lockfile
# On a disposable clean checkout, undo only the SDK analysis-options migration:
git restore --source=HEAD -- analysis_options.yaml
cargo fetch --manifest-path rust/Cargo.toml --locked
flutter analyze --no-pub
cargo test --manifest-path rust/Cargo.toml --locked
cargo build --manifest-path rust/Cargo.toml --release --locked
export FQAPP_RUST_HOST_LIB="$PWD/rust/target/release/libfqapi_core.so"
flutter test --no-pub test/rust_host_integration_test.dart
flutter test --no-pub
node --test test/verify_audio_cenc_test.cjs
python scripts/verify_windows_media.py
bash packaging/arch/build_release.sh
bash scripts/build_linux_package.sh build/linux/x64/release/bundle build/arch-package HEAD
```

The script requires a **new output directory**, leaves its input bundle intact,
normalizes ELF RUNPATH only in a staging copy, validates all bundle ELF closure
and desktop metadata, then runs makepkg without installing dependencies or
starting the app. Never pass untrusted binaries (ldd inspects trusted builds).
The supplied commit must equal the clean checkout HEAD and the successful build's
`source-commit.txt` marker. This catches accidental old-bundle packaging; it is
not cryptographic attestation of an arbitrary caller-supplied bundle. Build from
a fresh neutral checkout with dependency sources only (no restored build/target).
The script isolates HOME/config/cache/GPG and disables the session bus; it neither
starts the application nor connects to the user's keyring.

Outputs: `.pkg.tar.zst`, populated binary `PKGBUILD`, `.SRCINFO`, checksum-pinned
local `fqapp-bundle.tar.zst`, ELF report, build manifest, license inventory, exact HEAD `fqapp-source.tar.zst`,
checksum-bound `source-PKGBUILD`, and package `.BUILDINFO`. Source integrity is
checked with `makepkg --verifysource`.
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
CI uses a digest-pinned Arch container and 2026-11-09 repository snapshot,
checks the exact SDK checksum and compiler version, caches only dependency
sources, and uploads draft packages with automatic test evidence. Its Ubuntu
host is not Ubuntu-native build evidence or GUI acceptance. No release publish
permission or release action is present. Other platform regressions run in their
existing workflows and must also pass before release.

`packaging/arch/build_release.sh` sets Rust remap-path-prefix and C/C++
ffile-prefix-map, preserving paths with spaces and existing encoded Rust flags.
Both release and packaging reject untracked inputs in code, native, dependency,
and asset directories, including ignored assets; generated Linux ephemeral files
are excluded. Move local inputs aside or build an exact Git export; these checks
never delete local files. Build in a neutral source/SDK/PUB_CACHE/HOME directory to reduce
Dart AOT file URIs too. The pinned Flutter Linux command has no general source
prefix remapping flag; filesystem-root is a compiler input overlay, not a promise
to redact diagnostics. Do not rewrite binary strings or drop notices. ELF report
separately flags residual /home/ diagnostic strings and validates loader paths;
only relocatable $ORIGIN and the system Java server path are published. A residual
diagnostic URI is not an executable loader search path. No bit reproducibility or
complete asset rights audit is claimed.
