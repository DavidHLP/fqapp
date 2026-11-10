// Real WebKit ephemeral cookie store, using production extraction/domain rules.
// Build alongside native/linux/login.cc; run only in a disposable desktop/bus.
#include "common.h"
#include <webkit2/webkit2.h>
struct Pending {
  GMainLoop *loop = g_main_loop_new(nullptr, FALSE);
  GAsyncResult *result = nullptr;
  ~Pending() { if (result) g_object_unref(result); g_main_loop_unref(loop); }
  static void done(GObject *, GAsyncResult *result, gpointer data) {
    auto *p = static_cast<Pending *>(data);
    p->result = G_ASYNC_RESULT(g_object_ref(result));
    g_main_loop_quit(p->loop);
  }
  void wait() { g_main_loop_run(loop); }
};
int main(int argc, char **argv) {
  gtk_init(&argc, &argv);
  g_autoptr(WebKitWebContext) context = webkit_web_context_new_ephemeral();
  auto *manager = webkit_web_context_get_cookie_manager(context);
  g_autoptr(SoupCookie) cookie = soup_cookie_new("sessionid", "synthetic", ".fanqienovel.com", "/", -1);
  soup_cookie_set_http_only(cookie, TRUE);
  soup_cookie_set_secure(cookie, TRUE);
  GError *error = nullptr;
  Pending add;
  webkit_cookie_manager_add_cookie(manager, cookie, nullptr, Pending::done, &add);
  add.wait();
  g_assert_true(webkit_cookie_manager_add_cookie_finish(manager, add.result, &error));
  g_assert_no_error(error);
  Pending get;
  webkit_cookie_manager_get_cookies(manager, "https://fanqienovel.com/", nullptr, Pending::done, &get);
  get.wait();
  auto *cookies = webkit_cookie_manager_get_cookies_finish(manager, get.result, &error);
  g_assert_no_error(error);
  g_assert_cmpuint(g_list_length(cookies), ==, 1);
  g_assert_true(soup_cookie_get_http_only(static_cast<SoupCookie *>(cookies->data)));
  g_assert_true(fqapp::session_header(cookies) == "sessionid=synthetic");
  g_list_free_full(cookies, reinterpret_cast<GDestroyNotify>(soup_cookie_free));
  Pending foreign;
  webkit_cookie_manager_get_cookies(manager, "https://evil.test/", nullptr, Pending::done, &foreign);
  foreign.wait();
  cookies = webkit_cookie_manager_get_cookies_finish(manager, foreign.result, &error);
  g_assert_no_error(error);
  g_assert_null(cookies);
  g_assert_false(fqapp::official_uri("https://fanqienovel.com.evil.test/"));
  Pending remove;
  webkit_cookie_manager_delete_cookie(manager, cookie, nullptr, Pending::done, &remove);
  remove.wait();
  g_assert_true(webkit_cookie_manager_delete_cookie_finish(manager, remove.result, &error));
  g_assert_no_error(error);
  Pending empty;
  webkit_cookie_manager_get_cookies(manager, "https://fanqienovel.com/", nullptr, Pending::done, &empty);
  empty.wait();
  cookies = webkit_cookie_manager_get_cookies_finish(manager, empty.result, &error);
  g_assert_no_error(error);
  g_assert_null(cookies);
  g_print("PASS real WebKit HttpOnly add/read, foreign domain exclusion, delete/read-empty; synthetic only\n");
}
