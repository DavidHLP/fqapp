#include "common.h"
#include <cstring>
#include <webkit2/webkit2.h>
namespace fqapp {
bool official_uri(const char *text) {
  g_autoptr(GUri) uri = g_uri_parse(text, G_URI_FLAGS_NONE, nullptr);
  if (!uri || g_strcmp0(g_uri_get_scheme(uri), "https") ||
      g_uri_get_userinfo(uri) ||
      (g_uri_get_port(uri) != -1 && g_uri_get_port(uri) != 443))
    return false;
  const char *host = g_uri_get_host(uri);
  if (!host)
    return false;
  std::string h = host;
  for (auto &c : h)
    c = g_ascii_tolower(c);
  for (const char *root :
       {"fanqienovel.com", "snssdk.com", "bytedance.com", "zijieapi.com"}) {
    std::string suffix = std::string(".") + root;
    if (h == root ||
        (h.size() > suffix.size() &&
         h.compare(h.size() - suffix.size(), suffix.size(), suffix) == 0))
      return true;
  }
  return false;
}
std::string session_header(GList *cookies) {
  std::string result;
  bool session = false;
  for (GList *n = cookies; n; n = n->next) {
    auto *c = static_cast<SoupCookie *>(n->data);
    const char *name = soup_cookie_get_name(c);
    const char *value = soup_cookie_get_value(c);
    const char *domain = soup_cookie_get_domain(c);
    if (!name || !*name || !value || !domain || !*domain)
      continue;
    std::string d = domain;
    if (d[0] == '.')
      d.erase(0, 1);
    if (d != "fanqienovel.com" &&
        !(d.size() > 16 &&
          d.compare(d.size() - 16, 16, ".fanqienovel.com") == 0))
      continue;
    if (strpbrk(name, ";=\r\n") || strpbrk(value, ";\r\n"))
      return {};
    GDateTime *expires = soup_cookie_get_expires(c);
    g_autoptr(GDateTime) now = g_date_time_new_now_utc();
    if (expires && g_date_time_compare(expires, now) <= 0)
      continue;
    if (*value && (!strcmp(name, "sessionid") ||
                   !strcmp(name, "sessionid_ss") || !strcmp(name, "sid_tt")))
      session = true;
    if (!result.empty())
      result += "; ";
    result += std::string(name) + "=" + value;
    if (result.size() > 12 * 1024)
      return {};
  }
  return session ? result : "";
}
class WebLogin final : public Login {
  struct State {
    GtkWidget *window = nullptr;
    GtkWidget *hint = nullptr;
    FlMethodCall *pending = nullptr;
    GCancellable *cancel = g_cancellable_new();
    unsigned generation = 0;
    ~State() { g_object_unref(cancel); }
  };
  std::shared_ptr<State> s = std::make_shared<State>();
  GtkWindow *parent;
  static void finish(State &s, const std::string &cookie = {}) {
    ++s.generation;
    g_cancellable_cancel(s.cancel);
    if (s.pending) {
      g_autoptr(FlValue) v = cookie.empty()
                                 ? fl_value_new_null()
                                 : fl_value_new_string(cookie.c_str());
      reply(s.pending, v);
      g_clear_object(&s.pending);
    }
    if (s.window) {
      auto *w = s.window;
      s.window = nullptr;
      gtk_widget_destroy(w);
    }
  }

public:
  explicit WebLogin(GtkWindow *w) : parent(w) {}
  ~WebLogin() override { finish(*s); }
  void call(FlMethodCall *call) override {
    std::string method = fl_method_call_get_name(call);
    if (method == "cancelLogin" || method == "clearSession") {
      finish(*s);
      reply(call);
      return;
    }
    if (method != "login") {
      fl_method_call_respond_not_implemented(call, nullptr);
      return;
    }
    if (s->pending) {
      fail(call, "LOGIN_BUSY", "登录窗口正在处理");
      return;
    }
    g_cancellable_reset(s->cancel);
    s->pending = FL_METHOD_CALL(g_object_ref(call));
    s->window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(s->window), "番茄官方登录");
    gtk_window_set_default_size(GTK_WINDOW(s->window), 960, 760);
    gtk_window_set_transient_for(GTK_WINDOW(s->window), parent);
    auto *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_container_add(GTK_CONTAINER(s->window), box);
    s->hint =
        gtk_label_new("请完成官方登录，再点击读取书架。关闭窗口取消登录。");
    gtk_box_pack_start(GTK_BOX(box), s->hint, FALSE, FALSE, 0);
    auto *button = gtk_button_new_with_label("读取书架");
    gtk_box_pack_start(GTK_BOX(box), button, FALSE, FALSE, 0);
    g_autoptr(WebKitWebContext) ctx = webkit_web_context_new_ephemeral();
    auto *web = webkit_web_view_new_with_context(ctx);
    gtk_box_pack_start(GTK_BOX(box), web, TRUE, TRUE, 0);
    webkit_settings_set_enable_html5_database(
        webkit_web_view_get_settings(WEBKIT_WEB_VIEW(web)), FALSE);
    g_signal_connect(
        web, "permission-request",
        G_CALLBACK(+[](WebKitWebView *, WebKitPermissionRequest *request,
                       gpointer) -> gboolean {
          webkit_permission_request_deny(request);
          return TRUE;
        }),
        nullptr);
    g_signal_connect(
        ctx, "download-started",
        G_CALLBACK(+[](WebKitWebContext *, WebKitDownload *download, gpointer) {
          webkit_download_cancel(download);
        }),
        nullptr);
    auto *manager = webkit_web_context_get_cookie_manager(ctx);
    webkit_cookie_manager_set_accept_policy(
        manager, WEBKIT_COOKIE_POLICY_ACCEPT_NO_THIRD_PARTY);
    g_signal_connect(
        web, "decide-policy",
        G_CALLBACK(+[](WebKitWebView *, WebKitPolicyDecision *d,
                       WebKitPolicyDecisionType type, gpointer) -> gboolean {
          if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
            webkit_policy_decision_ignore(d);
            return TRUE;
          }
          const char *uri = nullptr;
          if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION)
            uri =
                webkit_uri_request_get_uri(webkit_navigation_action_get_request(
                    webkit_navigation_policy_decision_get_navigation_action(
                        WEBKIT_NAVIGATION_POLICY_DECISION(d))));
          if (type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE)
            uri = webkit_uri_response_get_uri(
                webkit_response_policy_decision_get_response(
                    WEBKIT_RESPONSE_POLICY_DECISION(d)));
          if (uri && !official_uri(uri)) {
            webkit_policy_decision_ignore(d);
            return TRUE;
          }
          return FALSE;
        }),
        nullptr);
    g_object_set_data_full(
        G_OBJECT(button), "state", new std::shared_ptr<State>(s),
        [](gpointer p) { delete static_cast<std::shared_ptr<State> *>(p); });
    g_object_set_data_full(G_OBJECT(button), "manager", g_object_ref(manager),
                           g_object_unref);
    g_signal_connect(
        button, "clicked", G_CALLBACK((+[](GtkButton *b, gpointer) {
          auto state = *static_cast<std::shared_ptr<State> *>(
              g_object_get_data(G_OBJECT(b), "state"));
          using Request = std::pair<std::shared_ptr<State>, unsigned>;
          auto *request = new Request(state, state->generation);
          auto *cm =
              WEBKIT_COOKIE_MANAGER(g_object_get_data(G_OBJECT(b), "manager"));
          webkit_cookie_manager_get_cookies(
              cm, "https://fanqienovel.com/", state->cancel,
              [](GObject *src, GAsyncResult *r, gpointer data) {
                std::unique_ptr<Request> req(static_cast<Request *>(data));
                g_autoptr(GError) error = nullptr;
                GList *cookies = webkit_cookie_manager_get_cookies_finish(
                    WEBKIT_COOKIE_MANAGER(src), r, &error);
                auto header = session_header(cookies);
                g_list_free_full(cookies, reinterpret_cast<GDestroyNotify>(
                                              soup_cookie_free));
                auto &state = *req->first;
                if (req->second != state.generation || !state.pending)
                  return;
                if (!header.empty())
                  finish(state, header);
                else
                  gtk_label_set_text(GTK_LABEL(state.hint),
                                     "未发现有效官方会话，或 Cookie "
                                     "超出安全限制，请完成登录后重试。");
              },
              request);
        })),
        nullptr);
    g_signal_connect(
        s->window, "delete-event",
        G_CALLBACK(+[](GtkWidget *, GdkEvent *, gpointer data) -> gboolean {
          finish(*static_cast<State *>(data));
          return TRUE;
        }),
        s.get());
    webkit_web_view_load_uri(WEBKIT_WEB_VIEW(web),
                             "https://fanqienovel.com/main/writer/login");
    gtk_widget_show_all(s->window);
  }
};
std::unique_ptr<Login> make_login(GtkWindow *w) {
  return std::make_unique<WebLogin>(w);
}
} // namespace fqapp
