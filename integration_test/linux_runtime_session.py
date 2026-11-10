"""Task-local Arch acceptance session; no system install or daily desktop access.

Run from the repository: python integration_test/linux_runtime_session.py x11
Modes: x11 (Xvfb/Openbox), wayland (headless Weston), xwayland (Weston XWM).
Requires the signature-verified task prefixes recorded in runtime-acceptance-handoff.md.
FQAPP_RUN_COMMAND may select the standalone cookie test instead of Flutter.
The password below is a fixed SYNTHETIC fixture password for a new keyring.
"""
import os,pathlib,tempfile,subprocess,time,sys
base=pathlib.Path(tempfile.mkdtemp(prefix='fqapp-acceptance-')); (base/'home').mkdir(); (base/'runtime').mkdir(mode=0o700); (base/'config').mkdir(); (base/'log').mkdir()
mode=sys.argv[1]; assert mode in ('x11','wayland','xwayland'); evidence=pathlib.Path(tempfile.gettempdir())/'fqapp-runtime-evidence'/base.name; evidence.mkdir(parents=True); (evidence/'session.txt').write_text(str(base)+'\n'+mode+'\n')
env=os.environ.copy(); env.update(HOME=str(base/'home'),XDG_RUNTIME_DIR=str(base/'runtime'),XDG_CONFIG_HOME=str(base/'config'),XDG_DATA_HOME=str(base/'data'),XDG_CACHE_HOME=str(base/'cache'),PUB_CACHE='/home/david/.pub-cache',FQAPP_EVIDENCE=str(evidence),LD_LIBRARY_PATH='/tmp/fqapp-native-deps/usr/lib:/tmp/fqapp-runtime-tools/usr/lib:/tmp/fqapp-runtime-tools/usr/lib/weston',PKG_CONFIG_PATH='/tmp/fqapp-native-deps/usr/lib/pkgconfig',PATH='/tmp/fqapp-runtime-tools/usr/bin:'+env['PATH'],SPEECHD_PLUGIN_DIR='/tmp/fqapp-native-deps/usr/lib/speech-dispatcher',ESPEAK_DATA_PATH='/tmp/fqapp-native-deps/usr/share/espeak-ng-data',SPEECHD_ADDRESS='unix_socket:'+str(base/'speechd.sock'),XDG_DATA_DIRS='/tmp/fqapp-runtime-tools/usr/share:/usr/local/share:/usr/share',XDG_CURRENT_DESKTOP='GNOME',PULSE_SERVER='unix:'+str(base/'no-pulse'),GDK_BACKEND='x11' if mode!='wayland' else 'wayland',LIBGL_ALWAYS_SOFTWARE='1')
env.pop('DBUS_SESSION_BUS_ADDRESS',None);env.pop('DISPLAY',None);env.pop('WAYLAND_DISPLAY',None)
for name in ['GNOME_KEYRING_CONTROL','XAUTHORITY','SSH_AUTH_SOCK','DBUS_STARTER_ADDRESS','DBUS_STARTER_BUS_TYPE','HYPRLAND_INSTANCE_SIGNATURE','SWAYSOCK','I3SOCK']: env.pop(name,None)
env['CARGO_HOME']=os.environ.get('FQAPP_CARGO_HOME', '/tmp/fqapp-acceptance-swo6yayo/home/.cargo')
(base/'alsa.conf').write_text('pcm.null { type null }\npcm.!default { type null }\nctl.!default { type hw card 999 }\n'); env['ALSA_CONFIG_PATH']=str(base/'alsa.conf')
(base/'speechd.conf').write_text(f'''CommunicationMethod "unix_socket"
SocketPath "{base}/speechd.sock"
LogLevel 3
LogDir "{base}/log"
AddModule "espeak-ng" "sd_espeak-ng" "/tmp/fqapp-native-deps/etc/speech-dispatcher/modules/espeak-ng.conf"
DefaultModule espeak-ng
AudioOutputMethod "alsa"
AudioALSADevice "null"
''')
# Every child is owned by this fresh private session; no inherited session bus.
script='''set -eu
children=""
trap 'for child in $children; do kill "$child" 2>/dev/null || true; done; wait || true' EXIT
printf 'fqapp-synthetic-disposable' | gnome-keyring-daemon --foreground --unlock --components=secrets --control-directory="$XDG_RUNTIME_DIR/keyring" > "$FQAPP_EVIDENCE/keyring.log" 2>&1 &
children="$children $!"
sleep .3
/tmp/fqapp-native-deps/usr/bin/speech-dispatcher -s -t 0 -C "BASE" -c unix_socket -m /tmp/fqapp-native-deps/usr/lib/speech-dispatcher/speech-dispatcher-modules -S "BASE/speechd.sock" -P "BASE/speechd.pid" > "$FQAPP_EVIDENCE/speech.log" 2>&1 &
children="$children $!"
speech_pid=$!
export FQAPP_SPEECH_PID=$speech_pid
(while kill -0 "$speech_pid" 2>/dev/null; do
  if test -f "$FQAPP_EVIDENCE/disconnect.request"; then kill "$speech_pid"; break; fi
  sleep .1
done) &
children="$children $!"
'''.replace('BASE',str(base))
if mode=='x11':
 script+='''Xvfb -displayfd 3 -screen 0 1280x800x24 -nolisten tcp -noreset 3>"BASE/display" > "$FQAPP_EVIDENCE/display.log" 2>&1 &
children="$children $!"
for i in $(seq 1 100); do test -s "BASE/display" && break; sleep .1; done
export DISPLAY=:$(cat "BASE/display")
openbox --config-file /tmp/fqapp-runtime-tools/etc/xdg/openbox/rc.xml > "$FQAPP_EVIDENCE/openbox.log" 2>&1 &
children="$children $!"
'''.replace('BASE',str(base))
else:
 env['WESTON_MODULE_MAP']=';'.join(f'{x.name}={x}' for d in ['libweston-15','weston'] for x in pathlib.Path('/tmp/fqapp-runtime-tools/usr/lib',d).glob('*.so')); env['WESTON_DATA_DIR']='/tmp/fqapp-runtime-tools/usr/share/weston'
 script+='''weston --backend=headless --renderer=gl --no-config --shell=kiosk-shell.so --socket=fqapp-wayland --idle-time=0 XWAYLAND > "$FQAPP_EVIDENCE/weston.log" 2>&1 &
children="$children $!"
export WAYLAND_DISPLAY=fqapp-wayland
for i in $(seq 1 100); do test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" && break; sleep .1; done
'''.replace('XWAYLAND','--xwayland' if mode=='xwayland' else '')
 if mode=='xwayland': script+=r'''for i in $(seq 1 100); do grep -q 'xserver listening on display' "$FQAPP_EVIDENCE/weston.log" && break; sleep .1; done
export DISPLAY=$(sed -n 's/.*xserver listening on display \(:[0-9][0-9]*\).*/\1/p' "$FQAPP_EVIDENCE/weston.log" | tail -1)
test -n "$DISPLAY"
'''
script+='''dbus-update-activation-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP 2>/dev/null || true
/home/david/.local/share/fqapp-toolchains/flutter-3.47.9/bin/flutter test integration_test/linux_runtime_test.dart -d linux --no-pub > "$FQAPP_EVIDENCE/flutter.log" 2>&1
'''
script=script.replace('/home/david/.local/share/fqapp-toolchains/flutter-3.47.9/bin/flutter test integration_test/linux_runtime_test.dart -d linux --no-pub', os.environ.get('FQAPP_RUN_COMMAND', '/home/david/.local/share/fqapp-toolchains/flutter-3.47.9/bin/flutter test integration_test/linux_runtime_test.dart -d linux --no-pub'))
(base/'run.sh').write_text(script)
print('EVIDENCE',evidence,flush=True)
r=subprocess.run(['dbus-run-session','--','bash',str(base/'run.sh')],env=env); print('EXIT',r.returncode,flush=True)

sys.exit(r.returncode)
