# MoonBazaar For iOS

MoonBazaar Developer API v1 的非官方 **iOS** 客户端（Swift + SwiftUI 原生重写）。App 自身**不持有** API Key 与用户令牌，所有请求都发往自建的 **Cloudflare Worker 中转服务**，由 Worker 注入 `X-API-Key`、注入用户 `Authorization: Bearer`，并通过 **Session Token** 把每个请求绑定到真实登录用户。

> 仓库同时保留了原始 Android 工程（`app/`，Kotlin + Jetpack Compose）作为移植参考，其说明见 [附录](#附录android-版)。

---

## 目录

- [功能特性](#功能特性)
- [界面结构](#界面结构)
- [鉴权与会话机制](#鉴权与会话机制)
- [技术栈](#技术栈)
- [项目结构](#项目结构)
- [调用的接口](#调用的接口)
- [构建与运行](#构建与运行)
- [配置项](#配置项)
- [设计约定与实现细节](#设计约定与实现细节)
- [安全说明](#安全说明)
- [已知限制](#已知限制)

---

## 功能特性

| 模块 | 说明 |
|---|---|
| **首页** | 顶部渐变大卡片展示**可用 GC**（整数显示）；账户信息卡（用户名 / UID / 绑定邮箱 / 状态 / 注册时间）；被 Ban 时顶部红色横幅并展示原因；支持下拉刷新 |
| **问卷** | `主要问卷`：显示**质量分**与地区，列出当前可做问卷（提供商 / 问卷 ID / 奖励 GC / 时长），`provider_status` 为 `false` 的提供商其问卷自动隐藏，可一键在 App 内打开问卷 |
| **交易** | 交易流水列表（时间 / 标题 / 详情 / 金额），金额**保留原始小数**，正数绿色、负数红色；动态分页（先探测总数再拉取），滑到底自动加载更多 |
| **兑换** | 兑换码提交，返回官方确认页时可直接唤起浏览器完成确认 |
| **邀请** | 邀请人数与累计佣金统计、专属邀请链接与自定义链接（未设置时优雅降级）、邀请明细列表、一键复制 |
| **提现** | 提现商品以卡片展示（中文名称 / 计价方式 / 接收字段），选择后填写表单提交，展示处理结果 |
| **多账号** | 侧边栏可保存多个已登录账号并**随时切换**，账号各自持有独立 session，互不串数据 |
| **封禁管控** | 账号被 Ban 时：首页提示原因，问卷/兑换/邀请/提现整页禁用，网络层亦拦截请求 |

## 界面结构

采用**自绘侧边抽屉（Side Drawer）**而非底部导航，对应 Android 版的 Material 3 `ModalNavigationDrawer`；抽屉内容支持滚动。

```
☰ 菜单
├── 功能导航：首页 · 问卷 · 交易 · 兑换 · 邀请 · 提现
└── 账户    ：账号列表（点击切换） · ＋ 添加账号 · 退出当前账号
```

- 从左缘向右滑动可拉开侧边栏，在侧边栏上向左滑动可收起，点击遮罩同样关闭。
- 每次启动侧边栏默认**关闭**，不自动展开。

## 鉴权与会话机制

MoonBazaar 不提供密码登录 API，登录必须发生在官方页面。本项目的完整链路：

```
① 点击「登录 / ＋ 添加账号」
        ↓
② App 内嵌 WKWebView 打开  {BASE_URL}/auth/login
   （使用 WKWebsiteDataStore.nonPersistent()，每次都是全新的无 Cookie 会话，
     避免复用上一个账号的登录态）
        ↓
③ 用户在 MoonBazaar 官方页完成授权
        ↓
④ Worker 回调 → 兑换 token → 加密存入 Cloudflare KV → 下发 session token
        ↓
⑤ 浏览器落在  {BASE_URL}/auth/done?auth=ok&uid=<UID>&session_token=<token>
        ↓
⑥ WKNavigationDelegate 拦截该 URL，提取 session_token，保存账号并关闭
        ↓
⑦ 之后所有请求携带  X-Client-Session: <token>
```

**为什么用 App 内 WebView 而不是系统浏览器？**
系统浏览器无法把 `<token>` 送回 App（Worker 的落地页是一次性 HTML 页面，不会跳回自定义 scheme）。因此登录流程完全在 App 内完成，由 `WKNavigationDelegate` 监视地址并在 `/auth/done` 落地瞬间截获令牌。

**会话存储**：支持多账号，账号列表与当前选中项持久化在 `UserDefaults`（`accounts_json` / `current_key`），并自动迁移旧版本的单账号 token（`session_token`）。`mnb://` 深链入口仍然保留，作为携带 `session_token` 回跳时的兜底通道。

## 技术栈

| 项 | 版本 / 说明 |
|---|---|
| 语言 | Swift 5（`SWIFT_VERSION = 5.0`） |
| UI | SwiftUI（iOS 原生，无第三方 UI 库） |
| 最低系统 | **iOS 15.0**，支持 iPhone / iPad（`TARGETED_DEVICE_FAMILY = 1,2`） |
| 工程 | Xcode 16（`objectVersion 77`，使用 File System Synchronized Groups，新增 `.swift` 文件无需手动加进工程） |
| 网络 | `URLSession`（`async/await`） |
| WebView | `WKWebView` + `WKContentRuleList` + 注入脚本 |
| 外链浏览器 | `SafariServices`（`SFSafariViewController`） |
| 状态管理 | `ObservableObject` / `@Published` + `Combine` |
| 持久化 | `UserDefaults` |
| 包名 | `top.witzzz.moonbazaar` |
| 版本 | `MARKETING_VERSION = 2.1.0` |

JSON 解析使用 Foundation 内置的 `JSONSerialization`，未引入额外序列化框架。

## 项目结构

```
ios/
├── MoonBazaar.xcodeproj/             Xcode 工程（含共享 Scheme）
│   └── xcshareddata/xcschemes/MoonBazaar.xcscheme
├── Config/
│   └── Info.plist                    ATS(WebView 放宽) / mnb:// 深链 / 启动屏 / 方向
├── MoonBazaar/
│   ├── MoonBazaarApp.swift            @main 入口 + 根视图 + 全屏登录页 + 外链浏览器
│   ├── AppConfig.swift                全局常量（BASE_URL / CALLBACK_URI / ...）
│   ├── Session.swift                  多账号 session 存储（UserDefaults 持久化）
│   ├── JSONSupport.swift              JSON 取值工具（对齐 Android 的 optXxx 语义）
│   ├── MoonWorkerApi.swift            URLSession 客户端：注入 X-Client-Session / 幂等键
│   ├── MoonRepository.swift           Worker 各接口封装与幂等键生成
│   ├── MainViewModel.swift            全部界面状态与数据加载逻辑
│   ├── Theme.swift                    配色与主题注入（对应 Android ui/theme）
│   ├── CommonViews.swift              卡片 / 字段行 / 标签 / 封禁页 / Toast / 剪贴板
│   ├── WebViewTopBar.swift            内嵌 WebView 共用顶栏
│   ├── LoginWebView.swift             登录 WebView（拦截 /auth/done）+ 登录页
│   ├── SurveyUrlRules.swift           问卷 URL 重写 / 拦截规则（纯函数）
│   ├── SurveyWebView.swift            问卷 WebView（内容规则 + 注入脚本）+ 问卷页
│   ├── MoonAppView.swift              侧边抽屉 + 六个功能页
│   ├── HomeView.swift                 首页
│   ├── SurveysView.swift              主要问卷
│   ├── TransactionsView.swift         交易流水
│   ├── RedeemView.swift               兑换
│   ├── ReferralView.swift             邀请
│   ├── WithdrawView.swift             提现
│   └── Assets.xcassets/               AppIcon / AccentColor
├── build_ipa.sh                      本地一键打包脚本（macOS）
└── dist/                             打包产物（已 gitignore）
```

## 调用的接口

所有业务请求都发往自建 Worker，由 Worker 转发到 `https://moonbazaar.xyz/dev/api/v1`。

| 界面 | 方法 | 路径 | 说明 |
|---|---|---|---|
| 会话 | `GET` | `/status` | Worker 会话与令牌状态（`session_valid` / `has_tokens`） |
| 首页 | `GET` | `/proxy/account/status` | 用户名、UID、打码邮箱、状态、注册时间、封禁信息 |
| 首页 | `GET` | `/proxy/account/balance` | 可用 Gascoin（主页 GC） |
| 问卷 | `GET` | `/proxy/surveys` | 质量分、地区、提供商开关、可做问卷列表 |
| 交易 | `GET` | `/proxy/transactions?limit=&offset=` | 交易流水（分页） |
| 兑换 | `POST` | `/proxy/codes/redeem` | 兑换码（幂等，常返回 `confirmation_url`） |
| 邀请 | `GET` | `/proxy/referrals` | 邀请统计与明细 |
| 邀请 | `GET` | `/proxy/referrals/link` | 邀请链接与自定义链接 |
| 提现 | `GET` | `/proxy/products` | 提现方式与商品 |
| 提现 | `POST` | `/proxy/withdrawals` | 提交提现（幂等） |
| 登出 | `DELETE` | `/user/tokens` | 吊销 Worker session |

写操作统一携带 `Idempotency-Key`（格式 `{op}-{timestamp}-{seq}-{sessionPrefix}`）。

## 构建与运行

前置条件：**macOS + Xcode 16**（工程使用了 Xcode 16 的 `PBXFileSystemSynchronizedRootGroup`，Xcode 15 无法打开）。用 Xcode 直接打开 `ios/MoonBazaar.xcodeproj` 后 Run 即可。

### 方式一：GitHub Actions 自动打包 IPA（推荐，无需本地 Mac）

仓库内置两条工作流：

| 工作流 | 触发条件 | 产物 |
|---|---|---|
| [ios-build.yml](.github/workflows/ios-build.yml) | push / PR（改动 `ios/**`）· 手动 `workflow_dispatch` | **未签名 IPA** artifact（`MoonBazaar-ipa`）+ 模拟器编译冒烟测试 |
| [ios-release.yml](.github/workflows/ios-release.yml) | 推送 `v*` / `ios-v*` tag · 手动 `workflow_dispatch` | **IPA** artifact（`MoonBazaar-ipa-release`）+ 自动创建 GitHub Release 并附上 IPA |

两者都运行在 `macos-15` runner（自带 Xcode 16），构建步骤：

```bash
xcodebuild -project MoonBazaar.xcodeproj -scheme MoonBazaar \
  -configuration Release -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" build

# 组装成 IPA：Payload/MoonBazaar.app -> zip
mkdir -p dist/Payload && cp -R build/Build/Products/Release-iphoneos/MoonBazaar.app dist/Payload/
(cd dist && zip -qry MoonBazaar-v<版本>-<构建号>-unsigned.ipa Payload)
```

**产物为未签名 IPA**，需要 TrollStore / AltStore / Sideloadly 等工具重签后安装（要求 iOS ≥ 15.0、arm64 设备）。

> ⚠️ **不要把 `IPHONEOS_DEPLOYMENT_TARGET` 调回 16.0 以上。** Xcode 16 的 iOS 18 SDK 会把 Foundation 的 Swift 符号（`URL` / `Data` / `Date` / `JSONDecoder` / `URLRequest` 的访问器等共 76 个）绑定到 `Foundation.framework` —— 那是 iOS 18 起 swift-foundation 才提供的实现。目标为 15.0 时链接器会改为链接 `/usr/lib/swift/libswiftFoundation.dylib`，这些符号在 iOS 15 上才解析得到；调回 16.0 会让 IPA 在 iOS 15 设备上以 dyld `Symbol missing` 启动即闪退。

**可选：产出已签名 IPA。** 在仓库 `Settings → Secrets and variables → Actions` 配置以下 Secrets，`ios-release.yml` 会自动切换到“归档 + 导出”流程：

| Secret | 说明 |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | 开发者证书 `.p12` 的 base64（`base64 -i cert.p12 \| pbcopy`） |
| `P12_PASSWORD` | `.p12` 密码 |
| `PROVISIONING_PROFILE_BASE64` | `.mobileprovision` 的 base64 |
| `KEYCHAIN_PASSWORD` | 临时钥匙串密码（任意值） |
| `DEVELOPMENT_TEAM` | Apple Team ID |

未配置上述 Secrets 时走未签名分支，无需任何证书即可跑通。

发布一个版本：

```bash
git tag ios-v2.1.0 && git push origin ios-v2.1.0
# 或在 Actions 页面手动触发 iOS Release 并填写 tag
```

### 方式二：本地 macOS 打包

```bash
cd ios
./build_ipa.sh                 # Release 未签名 IPA -> ios/dist/
./build_ipa.sh --simulator     # 只编译模拟器版本（快速校验，不产出 IPA）
./build_ipa.sh --signed --team ABCDE12345   # 已签名 IPA（需本机已装证书/描述文件）
```

常用参数：`-c Debug|Release`、`--method development|ad-hoc|app-store`、`--clean`。

### 方式三：Xcode 直接构建

```bash
open ios/MoonBazaar.xcodeproj
# Product > Archive / Run；或命令行快速校验编译：
xcodebuild -project ios/MoonBazaar.xcodeproj -scheme MoonBazaar \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

## 配置项

所有可调参数集中在 [AppConfig.swift](ios/MoonBazaar/AppConfig.swift)：

| 常量 | 默认值 | 说明 |
|---|---|---|
| `BASE_URL` | `https://mnb.witzzz.top` | **必须改成你自己部署的 Worker 域名** |
| `BASE_HOST` | `mnb.witzzz.top` | 用于识别登录落地页 `/auth/done`，需与 `BASE_URL` 的 host 一致 |
| `CALLBACK_URI` | `mnb://auth/callback` | 深链回调，需与 `Config/Info.plist` 的 `CFBundleURLSchemes` 一致 |
| `CALLBACK_SCHEME` | `mnb` | 深链 scheme |
| `SOURCE_APP` | `ios` | 请求头 `X-Source-App`，便于 Worker 端日志追踪 |

服务端需保证：Worker 已完成部署、已绑定 KV、已配置 `API_KEY` 与 `ENCRYPTION_KEY`，且 `REDIRECT_URI` 与开发者面板登记一致。

## 设计约定与实现细节

**GC 数值显示**
- 首页大号 GC 取整显示；交易金额、问卷奖励、邀请佣金**保留原始小数**（如 `52.8 GC`），不做四舍五入。

**交易分页（动态 limit）**
1. 先发一次探测请求 `limit=1` 取回 `total`；
2. 再按 `limit = min(total, 500)` 拉取；
3. 若总数超过 500，则回退为多页加载，滑到列表底部自动请求下一页。

**问卷过滤**
- `provider_status` 中为 `false` 的提供商，其问卷不展示（键名大小写不敏感匹配）；未列出的提供商不隐藏。

**问卷 WebView 的重写与拦截（iOS 实现方式与 Android 不同）**
WKWebView 没有 `shouldInterceptRequest` 的等价钩子，因此拆成三层，规则集与 Android **完全一致**（见 [SurveyUrlRules.swift](ios/MoonBazaar/SurveyUrlRules.swift)）：

| 场景 | iOS 手段 |
|---|---|
| 子资源拦截 | `WKContentRuleList`（`firebase.googleapis.com` / `analytics.tiktok.com` / `connect.facebook.net` / `www.google.com/jsapi` / `accounts.google.com/gsi/client`） |
| 子资源重写 | `atDocumentStart` 注入脚本，改写 `fetch` / `XHR.open` / `setAttribute` / `MutationObserver` 新增节点 |
| 主框架导航 | `WKNavigationDelegate.decidePolicyFor` 直接拦截与重写 |

重写规则：`google.com/recaptcha → recaptcha.net/recaptcha`、`ajax.googleapis.com → ajax.loli.net`、`api.ipify.org → api64.ipify.org`，仅替换域名前缀，**完整保留路径与全部 query 参数**。

**封禁管控（三层）**
1. 首页红色横幅展示 `ban_reason`；
2. 问卷 / 兑换 / 邀请 / 提现被替换为只读禁用页；
3. ViewModel 层在发起请求前拦截，不会向上游发送写操作。

**账号切换**
- 切换账号时会先清空界面状态（首页 / 交易 / 问卷 / 邀请 / 提现）再重新拉取，避免两个账号的数据串台；
- 退出当前账号会尽力吊销 Worker session，并从本地账号列表移除；若仍有其它账号则自动切换过去。

## 安全说明

- **API Key 永不进入 App**：客户端只与自建 Worker 通信，`X-API-Key` 由 Worker 在服务端注入。
- **用户令牌不下发到 App**：Worker 只回传 session token，用户 `access_token` / `refresh_token` 始终加密保存在 Cloudflare KV。
- **登录前清理浏览器数据**：每次打开登录页都使用 `WKWebsiteDataStore.nonPersistent()`，从根源上避免账号串号。
- **不要提交真实密钥**：iOS 的签名证书 / 描述文件、Worker 的 `.dev.vars`、开发者面板的 API Key 均不应进入版本库。

## 已知限制

- session token 目前以明文存于 `UserDefaults`，后续可替换为 Keychain 提升本地安全性。
- 未配置签名 Secrets 时只能产出**未签名 IPA**，需自行重签；签名 IPA 还要求目标设备 UDID 已加入对应 Provisioning Profile。
- 提现需要账号满足商品的可见性条件（如注册天数、累计收益），不满足时接口会返回业务错误，界面直接展示原始返回。
- 部分接口（交易、邀请、问卷）的字段名以**线上真实返回**为准做了兼容处理（如问卷为 `id` / `payout` / `link`，而非文档示例中的 `survey_id` / `reward` / `url`）；若上游调整字段，需同步更新 `MoonRepository` / `MainViewModel` 中的解析逻辑。

---

## 附录：Android 版

原始 Android 工程保留在 `app/`（Kotlin + Jetpack Compose + Material 3，`minSdk 29` / `targetSdk 37`），构建方式：

```powershell
.\gradlew.bat assembleDebug            # 产物：app/build/outputs/apk/debug/app-debug.apk
.\gradlew.bat :app:assembleDemoArm64Release   # 使用 signature/example.jks 的演示签名包
```

打包参数：`-PsignMode=demo|custom|none`、`-PversionCode=`、`-PversionName=`。产物可用 `gradlew collectDist` 统一收集到 `build/dist`。

iOS 版与 Android 版共用同一套 Worker 协议与会话模型，界面结构、分页策略、封禁管控与问卷重写/拦截规则均保持一致。