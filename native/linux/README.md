# Linux native bridge

Runner integration (GTK main thread, one bridge per engine):

```cpp
#include "bridge.h"
// After FlView/FlEngine creation, before Dart starts invoking platform channels:
bridge = fqapp_linux_bridge_new(
    fl_engine_get_binary_messenger(fl_view_get_engine(view)), window);
// Before destroying window/view/engine:
fqapp_linux_bridge_free(bridge);
bridge = nullptr;
```

Keep the pointer on the runner instance. A second registration returns null. Free it
while the parent GtkWindow and engine still exist. TTS cleanup joins its worker;
runner shutdown must therefore retain the engine until cleanup completes.

After creating the runner `flutter` target, add:

```cmake
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../native/linux"
                 "${CMAKE_CURRENT_BINARY_DIR}/fqapp_native")
target_link_libraries(${BINARY_NAME} PRIVATE fqapp_linux_bridge)
```

The source path above assumes the caller is `linux/CMakeLists.txt`; adjust the
relative prefix if called from `linux/runner/CMakeLists.txt`.

Required pkg-config modules: `gtk+-3.0`, `webkit2gtk-4.1`,
`speech-dispatcher` (Arch package **libspeechd**, separate from the daemon).
Runtime TTS additionally requires Speech Dispatcher and an engine with a Chinese
voice, such as espeak-ng. The bridge does not install, spawn or configure them.
Library license: libspeechd LGPL-2.1-or-later, distinct from daemon GPL license;
packaging must retain the system library notices. WebKitGTK and its runtime
subprocess resources must remain installed. No libraries are vendored here.

Standalone build:

```sh
cmake -S native/linux -B /tmp/fqapp-native-build \
  -DFLUTTER_LINUX_DIR=/path/to/flutter/bin/cache/artifacts/engine/linux-x64 \
  -DFQAPP_NATIVE_TESTS=ON
cmake --build /tmp/fqapp-native-build
ctest --test-dir /tmp/fqapp-native-build --output-on-failure
```

The test fully links all bridge objects and exercises synthetic cookie/URI
boundaries. It never opens a real login, keyring, audio output or system service.

## Dart contract

- `fqapp/system_tts`: `engines`, `initialize({engine,rate}) -> 4000`,
  `speak({text,id,queue})`, `pause`, `stop`, `shutdown`, `settings`.
  Events on `fqapp/system_tts_events`: `{type:start|done|error,id}` and
  `{type:engine_stopped}`. Stop/pause cancel only this client, discard queued IDs
  and suppress stale callbacks. Pause is cancellation because Dart reissues the
  current sentence on resume. No `stop_all`/`cancel_all` affects other apps.
  Initialize requires a listed zh/cmn voice. Rate maps logarithmically into the
  SSIP -100..100 scale; this is a relative setting requiring voice calibration.
  Settings returns an actionable error because there is no universal graphical
  settings application. Runtime engine failures require real daemon validation.
- `fqapp/fanqie_account`: `login -> String?`, `cancelLogin`, `clearSession`.
  Every login uses a new ephemeral WebKit context, fixed HTTPS navigation domains,
  denied popups/permissions/downloads, native CookieManager reads and 12 KiB cap.
  Cookie must include a nonempty, unexpired sessionid/sessionid_ss/sid_tt scoped
  to fanqienovel.com. HttpOnly is preserved. No JavaScript credential extraction,
  cookie logs, credential files or persistent browser profile. Closing cancels;
  clearSession closes the isolated context. Dart owns secure persistence and must
  delete its saved cookie on logout. Session-cookie shape is validated here;
  official server authentication/revocation remains the account service's check.
- `fqapp/desktop_session.setKeepScreenOn({on})`: aggregate demand in Dart; GTK
  session idle inhibitor is acquired once and released on off/free. Failure is
  `INHIBIT_UNAVAILABLE`, not success. GTK session manager/compositor support needs
  W/XW/X acceptance. This is not a global backlight write.
- `fqapp/desktop_session.capabilities`: reports subscriptions. `lockEvents=false`
  deliberately: logind LockedHint alone cannot prove a compositor reports locks.
  `logindLockedHintSubscription` indicates a hint subscription, `suspendEvents`
  indicates a current login1 owner plus PrepareForSleep subscription.
  `fqapp/desktop_session_events` emits `{type:locked|suspend,value:bool}`.
  Dart must wire these to generation-aware lifecycle handling before acceptance.
  No lock inference from focus/window geometry. The runner now queries initial
  LockedHint and watches login1 disappearance/reappearance to resubscribe. Dart
  combines lock/suspend hints with window visibility and per-media generations.
  Compositor reliability and full system-bus reconnection remain unverified.
- `fqapp/native_player`: existing `startListenForeground`/`stopListenForeground`
  maps. One D-Bus name `org.mpris.MediaPlayer2.fqapp`, DO_NOT_QUEUE, no replacement
  of another process. Metadata exports title/episode/duration/track ID, never
  cover URLs that may contain credentials. Position is monotonic extrapolation
  of supplied position/rate, in microseconds on D-Bus. Dart must refresh metadata
  on actual pause/play/seek and chapter changes.
  Legacy actions: `onNotificationAction({action:playPause|prev|next|stop})`.
  Optional merger extensions: pass `transportV2:true` only after supporting
  explicit `play`/`pause` actions; pass `seekSupported:true` only after supporting
  `seekTo` plus `positionMs`. Then Seek/SetPosition route to Dart, bound to current
  track ID and duration. Send `seeked:true` on the resulting metadata update to
  emit Seeked after actual completion. Dart now wires explicit play/pause and
  seek payloads for timed audio/video; TTS keeps CanSeek=false. `owner` string is echoed in
  callbacks and an owner-bearing stop cannot stop a different owner; merger must
  allocate unique media generations and reject stale callbacks/updates. These
  owner fences are now integrated; real four-media D-Bus acceptance is pending.

## Primary API references

- https://webkitgtk.org/reference/webkit2gtk/stable/method.CookieManager.get_cookies.html
- https://webkitgtk.org/reference/webkit2gtk/stable/ctor.WebContext.new_ephemeral.html
- https://raw.githubusercontent.com/brailcom/speechd/0.12.1/src/api/c/libspeechd.h
- https://archlinux.org/packages/extra/x86_64/speech-dispatcher/
- https://docs.gtk.org/gtk3/method.Application.inhibit.html
- https://specifications.freedesktop.org/mpris/latest/Player_Interface.html
- https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html

Build and synthetic checks do not establish T31/T40/T41/T42 runtime acceptance.
