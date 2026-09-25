import Foundation

/// 问卷 WebView 的 URL 重写 / 拦截规则。
///
/// 与 Android `ui/SurveyWebView.kt` 中的同名纯函数逐条对齐（原实现另有单测
/// `SurveyUrlRulesTest`，此处保持完全相同的语义）。
///
/// 重写（仅替换域名/路径前缀，其余原样保留，包含全部 query 参数）：
///   google.com/recaptcha   -> recaptcha.net/recaptcha
///   ajax.googleapis.com    -> ajax.loli.net
///   api.ipify.org          -> api64.ipify.org
///
/// 拦截（直接阻止加载）：
///   firebase.googleapis.com/*  analytics.tiktok.com/*  connect.facebook.net/*
///   www.google.com/jsapi       accounts.google.com/gsi/client
enum SurveyUrlRules {

    static let RECAPTCHA_FROM = "google.com/recaptcha"
    static let RECAPTCHA_TO = "recaptcha.net/recaptcha"
    static let AJAX_FROM = "ajax.googleapis.com"
    static let AJAX_TO = "ajax.loli.net"
    static let IPIFY_FROM = "api.ipify.org"
    static let IPIFY_TO = "api64.ipify.org"

    /// 命中则直接拦截。
    static func isBlockedHostPath(_ host: String, _ path: String) -> Bool {
        let h = host.lowercased()
        let p = path.isEmpty ? "/" : path
        if h == "firebase.googleapis.com" || h == "analytics.tiktok.com" || h == "connect.facebook.net" {
            return true
        }
        // 精确路径（允许其子路径），避免误伤同前缀的其它路径
        if h == "www.google.com" && (p == "/jsapi" || p.hasPrefix("/jsapi/")) { return true }
        if h == "accounts.google.com" && (p == "/gsi/client" || p.hasPrefix("/gsi/client/")) { return true }
        return false
    }

    /// 命中则直接拦截。
    static func isBlocked(_ url: String) -> Bool {
        guard let u = URL(string: url), let host = u.host, !host.isEmpty else { return false }
        return isBlockedHostPath(host, u.path)
    }

    /// 按规则重写 URL；参数与其余部分保持不变。
    static func rewrite(_ url: String) -> String {
        var out = url
        if out.contains(RECAPTCHA_FROM) {
            out = out.replacingOccurrences(of: RECAPTCHA_FROM, with: RECAPTCHA_TO)
        }
        if out.contains(AJAX_FROM) {
            out = out.replacingOccurrences(of: AJAX_FROM, with: AJAX_TO)
        }
        if out.contains(IPIFY_FROM) {
            out = out.replacingOccurrences(of: IPIFY_FROM, with: IPIFY_TO)
        }
        return out
    }

    /// 供 `WKContentRuleList` 使用的拦截规则（iOS 侧原生阻止子资源加载）。
    static var contentRuleListJSON: String {
        let rules: [JObj] = [
            blockRule(#"^https?://firebase\.googleapis\.com/.*"#),
            blockRule(#"^https?://analytics\.tiktok\.com/.*"#),
            blockRule(#"^https?://connect\.facebook\.net/.*"#),
            blockRule(#"^https?://www\.google\.com/jsapi(/.*)?$"#),
            blockRule(#"^https?://accounts\.google\.com/gsi/client(/.*)?$"#)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private static func blockRule(_ filter: String) -> JObj {
        ["trigger": ["url-filter": filter], "action": ["type": "block"]]
    }

    /// 注入页面的重写脚本（document start）：把被墙域名替换为可达镜像，
    /// 保留原路径与全部 query。
    static var rewriteUserScript: String {
        """
        (function(){
          var RULES = [
            ["google.com/recaptcha", "recaptcha.net/recaptcha"],
            ["ajax.googleapis.com", "ajax.loli.net"],
            ["api.ipify.org", "api64.ipify.org"]
          ];
          function rw(u){
            if (!u) return u;
            var s = String(u);
            for (var i = 0; i < RULES.length; i++) {
              if (s.indexOf(RULES[i][0]) >= 0) { s = s.split(RULES[i][0]).join(RULES[i][1]); }
            }
            return s;
          }
          try {
            var of = window.fetch;
            if (of) {
              window.fetch = function(input, init){
                try {
                  if (typeof input === 'string') return of.call(this, rw(input), init);
                  if (input && input.url) return of.call(this, new Request(rw(input.url), input), init);
                } catch (e) {}
                return of.apply(this, arguments);
              };
            }
          } catch (e) {}
          try {
            var oo = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(m, u){
              try { arguments[1] = rw(u); } catch (e) {}
              return oo.apply(this, arguments);
            };
          } catch (e) {}
          try {
            var ATTRS = ['src', 'href'];
            var proto = Element.prototype;
            var osa = proto.setAttribute;
            proto.setAttribute = function(name, value){
              try {
                if (ATTRS.indexOf(String(name).toLowerCase()) >= 0) { value = rw(value); }
              } catch (e) {}
              return osa.call(this, name, value);
            };
          } catch (e) {}
          try {
            new MutationObserver(function(muts){
              muts.forEach(function(m){
                m.addedNodes && m.addedNodes.forEach(function(n){
                  if (!n || n.nodeType !== 1) return;
                  ['src','href'].forEach(function(a){
                    var v = n.getAttribute && n.getAttribute(a);
                    if (v) { n.setAttribute(a, rw(v)); }
                  });
                  n.querySelectorAll && n.querySelectorAll('[src],[href]').forEach(function(el){
                    ['src','href'].forEach(function(a){
                      var v = el.getAttribute && el.getAttribute(a);
                      if (v) { el.setAttribute(a, rw(v)); }
                    });
                  });
                });
              });
            }).observe(document.documentElement || document, { childList: true, subtree: true });
          } catch (e) {}
        })();
        """
    }
}