# Arch dependency and redistribution contract (draft)

The complete Flutter bundle is installed under `/usr/lib/fqapp`; the launcher
executes its absolute executable path without changing cwd or XDG directories.
No install script, service, keyring read, app startup or data cleanup hook exists.

- ELF NEEDED: GTK3, GLib/GIO, Pango, Cairo, gdk-pixbuf, ATK (at-spi2-core),
  HarfBuzz, zlib, glibc/libgcc/libstdc++, libsecret, fontconfig, epoxy, GL/EGL,
  X11 and mpv. Transitive codec, audio, display and TLS libraries come from the
  Arch packages' dependency closure. `elf-report.txt` records every bundle ELF
  and its actual ldd resolution, including plugins, with missing libraries fatal.
- dlopen: media_kit uses system `libmpv.so*` provided by **mpv**, not a package
  named libmpv. FRB/media load bundle `lib/libfqapi_core.so`. `libdartjni.so`
  is retained and needs `java-runtime>=17`; its RUNPATH uses Arch's
  `/usr/lib/jvm/default-runtime/lib/server`. A configured default runtime is
  required. No host SDK path is retained in loader search paths.
- Services: D-Bus session bus, a working `org.freedesktop.secrets` provider for
  encrypted storage, desktop portal plus a backend matching the desktop where
  needed, URL opener via xdg-utils. Provider/backend selection belongs to the
  user; installation never replaces the desktop's keyring. Service availability
  is separate from ELF resolution and cannot be proven by packaging.
- Pending native bridge integration: GTK3/WebKitGTK 4.1 (`webkit2gtk-4.1`),
  SSIP client/server (`libspeechd`, `speech-dispatcher`), and a Chinese voice.
  The build-foundation bundle does not yet contain this bridge, so these are
  not falsely declared current runtime dependencies. When integrating its
  CMake/implementation, add its actual NEEDED/dlopen/SSIP dependencies to
  `depends`, rebuild the report and verify Chinese speech. CI prepares these
  libraries so the merged bridge can build; this does not certify integration.

Redistribution inventory: root GPL-3.0 text; Rust/FRB and all locked Cargo/pub
sources; Flutter/Dart/engine notices (copied from exact SDK); Flutter-generated
asset NOTICES; Noto and Roboto OFL notices; vendored WebViews and liquid glass;
C crypto/tiny_aes/kissfft/tempo headers; mpv/FFmpeg system package source and
build options; original icon SVG (covered by repository license). Existing
APK-derived images/animations and other third-party assets still need a complete
rights audit. Root GPL does not grant rights to all assets. Local archives carry
available notices, not a completed license audit. Preserve corresponding source,
locks and build inputs before any redistribution; no AUR or formal release until
source provision, signing, accounts, licensing and final product gates close.

Official references:
- https://docs.flutter.dev/platform-integration/linux/building
- https://man.archlinux.org/man/PKGBUILD.5.en
- https://wiki.archlinux.org/title/Arch_package_guidelines
- https://archlinux.org/packages/extra/x86_64/mpv/
- https://archlinux.org/packages/extra/x86_64/webkit2gtk-4.1/
- https://archlinux.org/packages/extra/x86_64/speech-dispatcher/
