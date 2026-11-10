#include "common.h"
#include <cmath>
#include <unistd.h>
using namespace fqapp;
struct FqappLinuxBridge {
  GtkWindow *window;
  FlMethodChannel *tts_channel, *login_channel, *session_channel,
      *player_channel;
  FlEventChannel *tts_events, *session_events;
  std::unique_ptr<Login> login;
  std::unique_ptr<Tts> tts;
  guint inhibit = 0;
  GDBusConnection *bus = nullptr;
  GDBusConnection *system_bus = nullptr;
  guint registrations[2] = {0, 0};
  guint suspend_subscription = 0;
  guint lock_subscription = 0;
  bool owner = false;
  FlValue *media = nullptr;
  gint64 updated = 0;
  unsigned track = 0;
  GDBusNodeInfo *info = nullptr;
  void event(const char *type, bool value) {
    g_autoptr(FlValue) v = fl_value_new_map();
    put(v, "type", fl_value_new_string(type));
    put(v, "value", fl_value_new_bool(value));
    fl_event_channel_send(session_events, v, nullptr, nullptr);
  }
  void action(const char *action, gint64 position = -1) {
    g_autoptr(FlValue) v = fl_value_new_map();
    put(v, "action", fl_value_new_string(action));
    if (auto *id = field(media, "owner"))
      put(v, "owner", fl_value_ref(id));
    if (position >= 0)
      put(v, "positionMs", fl_value_new_int(position / 1000));
    fl_method_channel_invoke_method(player_channel, "onNotificationAction", v,
                                    nullptr, nullptr, nullptr);
  }
  gint64 position() const {
    gint64 p = number(field(media, "positionMs")) * 1000;
    if (flag(field(media, "playing")))
      p +=
          (g_get_monotonic_time() - updated) * number(field(media, "speed"), 1);
    gint64 length = number(field(media, "durationMs")) * 1000;
    return std::max<gint64>(0, length > 0 ? std::min(p, length) : p);
  }
  std::string track_path() const {
    return "/org/mpris/MediaPlayer2/track/" + std::to_string(track);
  }
  GVariant *property(const char *name) {
    std::string n = name;
    if (n == "Identity")
      return g_variant_new_string("fqapp");
    if (n == "SupportedUriSchemes" || n == "SupportedMimeTypes")
      return g_variant_new_strv(nullptr, 0);
    if (n == "PlaybackStatus")
      return g_variant_new_string(!media                          ? "Stopped"
                                  : flag(field(media, "playing")) ? "Playing"
                                                                  : "Paused");
    if (n == "Position")
      return g_variant_new_int64(position());
    if (n == "Rate" || n == "MinimumRate" || n == "MaximumRate")
      return g_variant_new_double(number(field(media, "speed"), 1));
    if (n == "Volume")
      return g_variant_new_double(1);
    if (n == "Metadata") {
      GVariantBuilder b;
      g_variant_builder_init(&b, G_VARIANT_TYPE_VARDICT);
      if (media) {
        g_variant_builder_add(&b, "{sv}", "mpris:trackid",
                              g_variant_new_object_path(track_path().c_str()));
        g_variant_builder_add(
            &b, "{sv}", "mpris:length",
            g_variant_new_int64(number(field(media, "durationMs")) * 1000));
        g_variant_builder_add(
            &b, "{sv}", "xesam:title",
            g_variant_new_string(str(field(media, "episode")).c_str()));
        g_variant_builder_add(
            &b, "{sv}", "xesam:album",
            g_variant_new_string(str(field(media, "title")).c_str()));
      }
      return g_variant_builder_end(&b);
    }
    if (n == "CanControl" || n == "CanPlay" || n == "CanPause")
      return g_variant_new_boolean(media != nullptr);
    if (n == "CanGoNext")
      return g_variant_new_boolean(flag(field(media, "hasNext")));
    if (n == "CanGoPrevious")
      return g_variant_new_boolean(flag(field(media, "hasPrev")));
    // Merger enables this only after wiring the seekTo callback in Dart.
    if (n == "CanSeek")
      return g_variant_new_boolean(flag(field(media, "seekSupported")));
    return g_variant_new_boolean(false);
  }
  void changed() {
    if (!owner)
      return;
    GVariantBuilder b;
    g_variant_builder_init(&b, G_VARIANT_TYPE_VARDICT);
    for (auto *n : {"PlaybackStatus", "Metadata", "Rate", "MinimumRate",
                    "MaximumRate", "CanControl", "CanPlay", "CanPause",
                    "CanGoNext", "CanGoPrevious", "CanSeek"})
      g_variant_builder_add(&b, "{sv}", n, property(n));
    g_dbus_connection_emit_signal(
        bus, nullptr, "/org/mpris/MediaPlayer2",
        "org.freedesktop.DBus.Properties", "PropertiesChanged",
        g_variant_new("(sa{sv}as)", "org.mpris.MediaPlayer2.Player", &b,
                      nullptr),
        nullptr);
  }
  bool acquire() {
    if (owner)
      return true;
    if (!bus || !registrations[0] || !registrations[1])
      return false;
    g_autoptr(GVariant) r = g_dbus_connection_call_sync(
        bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", "RequestName",
        g_variant_new("(su)", "org.mpris.MediaPlayer2.fqapp", 4u),
        G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, nullptr);
    guint result = 0;
    if (r)
      g_variant_get(r, "(u)", &result);
    owner = result == 1 || result == 4;
    return owner;
  }
  void release() {
    if (media) {
      fl_value_unref(media);
      media = nullptr;
    }
    changed();
    if (owner) {
      g_dbus_connection_call(
          bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
          "org.freedesktop.DBus", "ReleaseName",
          g_variant_new("(s)", "org.mpris.MediaPlayer2.fqapp"), nullptr,
          G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, nullptr, nullptr);
      owner = false;
    }
  }
  void session(FlMethodCall *c) {
    std::string method = fl_method_call_get_name(c);
    if (method == "capabilities") {
      g_autoptr(FlValue) v = fl_value_new_map();
      put(v, "lockEvents", fl_value_new_bool(false));
      put(v, "logindLockedHintSubscription",
          fl_value_new_bool(lock_subscription != 0));
      put(v, "suspendEvents", fl_value_new_bool(suspend_subscription != 0));
      put(v, "source",
          fl_value_new_string("logind; subscription does not prove compositor "
                              "lock integration"));
      reply(c, v);
      return;
    }
    if (method != "setKeepScreenOn") {
      fl_method_call_respond_not_implemented(c, nullptr);
      return;
    }
    auto *on = field(fl_method_call_get_args(c), "on");
    if (!on || fl_value_get_type(on) != FL_VALUE_TYPE_BOOL) {
      fail(c, "INVALID_ARGUMENT", "on must be boolean");
      return;
    }
    GtkApplication *app = gtk_window_get_application(window);
    if (flag(on) && !inhibit && app)
      inhibit = gtk_application_inhibit(
          app, window, GTK_APPLICATION_INHIBIT_IDLE, "阅读或播放");
    if (!flag(on) && inhibit) {
      if (app)
        gtk_application_uninhibit(app, inhibit);
      inhibit = 0;
    }
    if (flag(on) && !inhibit)
      fail(c, "INHIBIT_UNAVAILABLE", "桌面会话未提供 Idle inhibit");
    else
      reply(c);
  }
  void player(FlMethodCall *c) {
    std::string method = fl_method_call_get_name(c);
    if (method == "stopListenForeground") {
      auto incoming = str(field(fl_method_call_get_args(c), "owner"));
      if (!incoming.empty() && incoming != str(field(media, "owner"))) {
        reply(c);
        return;
      }
      release();
      reply(c);
      return;
    }
    if (method != "startListenForeground") {
      fl_method_call_respond_not_implemented(c, nullptr);
      return;
    }
    auto *args = fl_method_call_get_args(c);
    if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fail(c, "INVALID_ARGUMENT", "metadata must be a map");
      return;
    }
    for (const char *k : {"positionMs", "durationMs", "speed"}) {
      double value = number(field(args, k), k == std::string("speed") ? 1 : 0);
      if (!std::isfinite(value) || value < 0 || value > 1e12 ||
          (std::string(k) == "speed" && (value < 0.1 || value > 10))) {
        fail(c, "INVALID_ARGUMENT", "Invalid playback position or rate");
        return;
      }
    }
    if (!acquire()) {
      fail(c, "MPRIS_OWNER_BUSY", "媒体会话不可用或已被另一实例占用");
      return;
    }
    if (str(field(media, "title")) != str(field(args, "title")) ||
        str(field(media, "episode")) != str(field(args, "episode")))
      ++track;
    if (media)
      fl_value_unref(media);
    media = fl_value_ref(args);
    updated = g_get_monotonic_time();
    changed();
    if (flag(field(args, "seeked")))
      g_dbus_connection_emit_signal(bus, nullptr, "/org/mpris/MediaPlayer2",
                                    "org.mpris.MediaPlayer2.Player", "Seeked",
                                    g_variant_new("(x)", position()), nullptr);
    reply(c);
  }
};
static const char *xml = R"(<node>
<interface name="org.mpris.MediaPlayer2">
<method name="Raise"/><method name="Quit"/>
<property name="CanQuit" type="b" access="read"/><property name="CanRaise" type="b" access="read"/><property name="HasTrackList" type="b" access="read"/>
<property name="Identity" type="s" access="read"/><property name="SupportedUriSchemes" type="as" access="read"/><property name="SupportedMimeTypes" type="as" access="read"/>
</interface><interface name="org.mpris.MediaPlayer2.Player">
<method name="Next"/><method name="Previous"/><method name="Pause"/><method name="PlayPause"/><method name="Stop"/><method name="Play"/>
<method name="Seek"><arg direction="in" type="x" name="Offset"/></method><method name="SetPosition"><arg direction="in" type="o" name="TrackId"/><arg direction="in" type="x" name="Position"/></method><method name="OpenUri"><arg direction="in" type="s" name="Uri"/></method>
<signal name="Seeked"><arg type="x" name="Position"/></signal>
<property name="PlaybackStatus" type="s" access="read"/><property name="Rate" type="d" access="readwrite"/><property name="Volume" type="d" access="readwrite"/><property name="Metadata" type="a{sv}" access="read"/><property name="Position" type="x" access="read"/>
<property name="MinimumRate" type="d" access="read"/><property name="MaximumRate" type="d" access="read"/>
<property name="CanGoNext" type="b" access="read"/><property name="CanGoPrevious" type="b" access="read"/><property name="CanPlay" type="b" access="read"/><property name="CanPause" type="b" access="read"/><property name="CanSeek" type="b" access="read"/><property name="CanControl" type="b" access="read"/>
</interface></node>)";
static const GDBusInterfaceVTable vtable = {
    [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
       const gchar *method, GVariant *parameters, GDBusMethodInvocation *inv,
       gpointer data) {
      auto *b = static_cast<FqappLinuxBridge *>(data);
      std::string m = method;
      if (!b->owner || !b->media) {
        g_dbus_method_invocation_return_error_literal(
            inv, G_DBUS_ERROR, G_DBUS_ERROR_NOT_SUPPORTED, "No active media");
        return;
      }
      if (m == "PlayPause")
        b->action("playPause");
      else if (m == "Play") {
        if (flag(field(b->media, "transportV2")))
          b->action("play");
        else if (!flag(field(b->media, "playing")))
          b->action("playPause");
      } else if (m == "Pause") {
        if (flag(field(b->media, "transportV2")))
          b->action("pause");
        else if (flag(field(b->media, "playing")))
          b->action("playPause");
      } else if (m == "Stop")
        b->action("stop");
      else if (m == "Next") {
        if (flag(field(b->media, "hasNext")))
          b->action("next");
      } else if (m == "Previous") {
        if (flag(field(b->media, "hasPrev")))
          b->action("prev");
      } else if ((m == "Seek" || m == "SetPosition") &&
                 flag(field(b->media, "seekSupported"))) {
        gint64 position = 0;
        if (m == "Seek") {
          gint64 offset;
          g_variant_get(parameters, "(x)", &offset);
          position = b->position();
          if (offset > 0 && position > G_MAXINT64 - offset)
            position = G_MAXINT64;
          else if (offset < 0 && offset < -position)
            position = 0;
          else
            position += offset;
        } else {
          const char *track;
          g_variant_get(parameters, "(&ox)", &track, &position);
          if (b->track_path() != track || position < 0) {
            g_dbus_method_invocation_return_value(inv, nullptr);
            return;
          }
        }
        gint64 length = number(field(b->media, "durationMs")) * 1000;
        if (length > 0)
          position = std::min(position, length);
        b->action("seekTo", position);
      } else {
        g_dbus_method_invocation_return_error_literal(
            inv, G_DBUS_ERROR, G_DBUS_ERROR_NOT_SUPPORTED,
            "Operation unavailable in current Dart contract");
        return;
      }
      g_dbus_method_invocation_return_value(inv, nullptr);
    },
    [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
       const gchar *property, GError **, gpointer data) -> GVariant * {
      return static_cast<FqappLinuxBridge *>(data)->property(property);
    },
    [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
       const gchar *, GVariant *, GError **error, gpointer) -> gboolean {
      g_set_error_literal(error, G_DBUS_ERROR, G_DBUS_ERROR_NOT_SUPPORTED,
                          "Playback settings managed in app");
      return FALSE;
    },
    {nullptr}};
static FlMethodChannel *channel(FlBinaryMessenger *m, const char *name,
                                FqappLinuxBridge *b,
                                FlMethodChannelMethodCallHandler cb) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto *c = fl_method_channel_new(m, name, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(c, cb, b, nullptr);
  return c;
}
static FlEventChannel *events(FlBinaryMessenger *m, const char *name) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto *e = fl_event_channel_new(m, name, FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(
      e,
      [](FlEventChannel *, FlValue *, gpointer) -> FlMethodErrorResponse * {
        return nullptr;
      },
      [](FlEventChannel *, FlValue *, gpointer) -> FlMethodErrorResponse * {
        return nullptr;
      },
      nullptr, nullptr);
  return e;
}
static FqappLinuxBridge *instance = nullptr;
FqappLinuxBridge *fqapp_linux_bridge_new(FlBinaryMessenger *m, GtkWindow *w) {
  if (instance || !m || !w)
    return nullptr;
  auto *b = new FqappLinuxBridge();
  b->window = w;
  b->tts_events = events(m, "fqapp/system_tts_events");
  b->session_events = events(m, "fqapp/desktop_session_events");
  b->tts = make_tts(b->tts_events);
  b->login = make_login(w);
  b->tts_channel = channel(m, "fqapp/system_tts", b,
                           [](FlMethodChannel *, FlMethodCall *c, gpointer d) {
                             static_cast<FqappLinuxBridge *>(d)->tts->call(c);
                           });
  b->login_channel =
      channel(m, "fqapp/fanqie_account", b,
              [](FlMethodChannel *, FlMethodCall *c, gpointer d) {
                static_cast<FqappLinuxBridge *>(d)->login->call(c);
              });
  b->session_channel =
      channel(m, "fqapp/desktop_session", b,
              [](FlMethodChannel *, FlMethodCall *c, gpointer d) {
                static_cast<FqappLinuxBridge *>(d)->session(c);
              });
  b->player_channel =
      channel(m, "fqapp/native_player", b,
              [](FlMethodChannel *, FlMethodCall *c, gpointer d) {
                static_cast<FqappLinuxBridge *>(d)->player(c);
              });
  b->bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  b->info = g_dbus_node_info_new_for_xml(xml, nullptr);
  if (b->bus)
    for (int i = 0; i < 2; ++i)
      b->registrations[i] = g_dbus_connection_register_object(
          b->bus, "/org/mpris/MediaPlayer2", b->info->interfaces[i], &vtable, b,
          nullptr, nullptr);
  b->system_bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, nullptr);
  if (b->system_bus) {
    b->suspend_subscription = g_dbus_connection_signal_subscribe(
        b->system_bus, "org.freedesktop.login1",
        "org.freedesktop.login1.Manager", "PrepareForSleep",
        "/org/freedesktop/login1", nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
           const gchar *, GVariant *p, gpointer data) {
          gboolean sleeping;
          g_variant_get(p, "(b)", &sleeping);
          static_cast<FqappLinuxBridge *>(data)->event("suspend", sleeping);
        },
        b, nullptr);
    g_autoptr(GVariant) r = g_dbus_connection_call_sync(
        b->system_bus, "org.freedesktop.login1", "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager", "GetSessionByPID",
        g_variant_new("(u)", static_cast<guint>(getpid())),
        G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, nullptr);
    if (r) {
      const char *path;
      g_variant_get(r, "(&o)", &path);
      b->lock_subscription = g_dbus_connection_signal_subscribe(
          b->system_bus, "org.freedesktop.login1",
          "org.freedesktop.DBus.Properties", "PropertiesChanged", path,
          "org.freedesktop.login1.Session", G_DBUS_SIGNAL_FLAGS_NONE,
          [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
             const gchar *, GVariant *p, gpointer data) {
            GVariant *changed = g_variant_get_child_value(p, 1);
            gboolean locked;
            if (g_variant_lookup(changed, "LockedHint", "b", &locked))
              static_cast<FqappLinuxBridge *>(data)->event("locked", locked);
            g_variant_unref(changed);
          },
          b, nullptr);
    }
  }
  instance = b;
  return b;
}
void fqapp_linux_bridge_free(FqappLinuxBridge *b) {
  if (!b)
    return;
  for (auto *c : {b->tts_channel, b->login_channel, b->session_channel,
                  b->player_channel})
    fl_method_channel_set_method_call_handler(c, nullptr, nullptr, nullptr);
  b->login.reset();
  b->tts.reset();
  b->release();
  auto *app = gtk_window_get_application(b->window);
  if (app && b->inhibit)
    gtk_application_uninhibit(app, b->inhibit);
  if (b->bus)
    for (auto id : b->registrations)
      if (id)
        g_dbus_connection_unregister_object(b->bus, id);
  if (b->system_bus) {
    if (b->lock_subscription)
      g_dbus_connection_signal_unsubscribe(b->system_bus, b->lock_subscription);
    if (b->suspend_subscription)
      g_dbus_connection_signal_unsubscribe(b->system_bus,
                                           b->suspend_subscription);
  }
  g_clear_object(&b->bus);
  g_clear_object(&b->system_bus);
  g_dbus_node_info_unref(b->info);
  for (auto *c : {b->tts_channel, b->login_channel, b->session_channel,
                  b->player_channel})
    g_object_unref(c);
  g_object_unref(b->tts_events);
  g_object_unref(b->session_events);
  instance = nullptr;
  delete b;
}
