#include "common.h"

#include <webkit2/webkit2.h>
int main() {
  for (auto *uri : {"https://fanqienovel.com/main/writer/login",
                    "https://sso.bytedance.com/", "https://a.zijieapi.com/"})
    g_assert_true(fqapp::official_uri(uri));
  for (auto *uri :
       {"http://fanqienovel.com/", "https://fanqienovel.com.evil.test/",
        "https://evilfanqienovel.com/", "https://user@fanqienovel.com/",
        "file:///tmp/x", "https://fanqienovel.com:444/"})
    g_assert_true(!fqapp::official_uri(uri));
  auto *cookie =
      soup_cookie_new("sessionid", "synthetic", ".fanqienovel.com", "/", -1);
  soup_cookie_set_http_only(cookie, TRUE);
  GList *list = g_list_append(nullptr, cookie);
  g_assert_true(fqapp::session_header(list) == "sessionid=synthetic");
  g_autoptr(GDateTime) expired = g_date_time_new_from_unix_utc(1);
  soup_cookie_set_expires(cookie, expired);
  g_assert_true(fqapp::session_header(list).empty());
  soup_cookie_set_expires(cookie, nullptr);
  soup_cookie_set_value(cookie, std::string(12 * 1024, 'x').c_str());
  g_assert_true(fqapp::session_header(list).empty());
  soup_cookie_set_value(cookie, "synthetic");
  soup_cookie_set_domain(cookie, "evil.test");
  g_assert_true(fqapp::session_header(list).empty());
  g_list_free_full(list, reinterpret_cast<GDestroyNotify>(soup_cookie_free));
}
