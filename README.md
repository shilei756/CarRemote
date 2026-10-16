# 长安控车 · CarRemote（原生 iOS App）

把你的「远程控车系统」网站（长安逸动PLUS / UNI-V / CS75PLUS 控车面板）做成**纯原生 SwiftUI App**：不是套壳网页，拥有独立的代码编制，完整保留**白名单 / 封禁检查**与**卡密（CH-XXXX-XXXX）体验系统**，并新增**桌面小组件**与**Siri 语音控车**。

- 站主后端：`https://a9db267525c1cf6b2.app.workbuddy.host`
- 控车链路与长安官方 App / 网页版完全一致（inCall OAuth → access_token → car/data → 四步控制指令）
- 最低系统：iOS 18.0（小组件交互按钮、锁屏小组件需要 iOS 17+）

---

## 一、功能一览

| 模块 | 说明 |
| --- | --- |
| 车况仪表盘 | 剩余续航 / 油量 / 总里程 / 电瓶电压 / 车外温度 / 空调温度 / 四轮胎压 / 车辆示意图 / 状态旗标（车门、车窗、天窗、发动机） |
| 快捷控车 | 闪灯、开锁、闭锁、鸣笛；更多控车：寻车、点火、熄火、开/关窗、留缝、天窗、空调 |
| 防误触 | 开锁 / 闭锁 / 点火 / 熄火默认弹二次确认，可在「我的」逐条开关 |
| 白名单 + 卡密 | 登录后按 `/api/card/status` 判定：正式用户直接进入；未授权用户进入卡密网关兑换当天体验（CH-XXXX-XXXX）；封禁手机号被拦截并提示联系站主 |
| 玩车圈子 | 动态流、点赞、评论、图文发布（与网页版同一套接口） |
| 油耗统计 | 本地记录每次加油，自动估算分段 / 平均油耗、累计油费 |
| 维保提醒 | 本地记录保养项目，按里程 / 日期到期提醒 |
| 桌面小组件 | 小/中/大三围 + 锁屏圆型/矩形；车况一览，按钮免打开 App 直接控车（闪灯/开锁/闭锁/鸣笛） |
| Siri 语音 | 「嘿 Siri，用长安控车解锁车辆」「车况怎么样」等 11 条短语，可在设置里逐条关闭 |

---

## 二、工程结构（三目标 + 共享框架）

```
CarRemote/
├── project.yml                  # XcodeGen 主 spec（App + CarCore，手动签名）
├── project.widget.yml           # 小组件 spec（条件加载，见下）
├── ExportOptions.plist          # Ad Hoc 导出配置（UUID 由 CI 动态替换）
├── CarCore/                     # 共享框架（App 与小组件都链接它）
│   ├── Config/APIConfig.swift   # 站点地址、client_id、App Group、Keychain 组
│   ├── Models/                  # 车况/指令/圈子/本地记录模型（多字段名容错解析）
│   ├── Services/                # 网络、登录、卡密、控车、圈子、用量上报
│   ├── Storage/                 # Keychain + App Group 共享存储（凭据/设置/快照/油耗/维保）
│   └── Intents/                 # Siri App Intents（10 控车 + 1 车况查询）
├── CarRemote/                   # 主 App（SwiftUI）
│   ├── AppState.swift           # 登录 → 卡密网关 → 主界面 状态机
│   ├── Views/                   # 仪表盘/圈子/油耗/维保/设置/登录/卡密
│   ├── ViewModels/              # 仪表盘/圈子/油耗视图模型
│   ├── Intents/AppShortcutsProvider.swift   # Siri 快捷短语
│   └── Assets.xcassets/         # App 图标 + 主题色
├── CarWidget/                   # WidgetKit 扩展（小组件）
└── .github/workflows/build-ipa.yml   # 云端构建流水线（无 Mac 出 IPA）
```

数据共享方式：App 把车况快照写入 **App Group**（`group.6cd6b6c14418f98a.1`）供小组件读取；登录凭据存放在 App 与 CarCore 共享的 **Keychain 共享组**（`7NSH43RT4Z.carremote`）中。小组件上的交互按钮（开锁、闪灯等）其 App Intent 由系统拉到主 App 进程执行，因此小组件自身不需要钥匙串权限。

### 为什么小组件是「条件加载」的

iOS 规定：**每个扩展目标必须有自己独立的 App ID 和描述文件**。小组件的 Bundle ID（`app.copper1249.chipmunk6639.CarWidget`）与主 App 不同，所以需要单独注册并生成第二个描述文件（见「三、3」）。因此：

- `xcodegen`（本地/默认）：只生成 **App + CarCore**，不包含小组件；
- `INCLUDE_WIDGET=true xcodegen`：生成含小组件的三目标工程；
- CI 中：上传了小组件描述文件 Secret 就自动走完整版，否则自动降级为无小组件版（App / Siri / 车况等全部功能不受影响）。

---

## 三、无 Mac 云端构建 IPA（推荐，已配好流水线）

仓库已带 `.github/workflows/build-ipa.yml`：push 后 GitHub 的 macOS 构建机自动用你的证书编译、签名并导出 IPA，在运行记录底部 **Artifacts** 下载 `CarRemote-ipa`（保留 14 天）。

### 1. 把代码传到 GitHub

```bash
cd CarRemote
git init && git add . && git commit -m "CarRemote 1.0.0"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

### 2. 上传证书 Secret

仓库页面 → **Settings → Secrets and variables → Actions → New repository secret**：

| Secret 名称 | 值 | 生成方式 |
| --- | --- | --- |
| `CERT_P12_BASE64` | p12 证书的 base64 | `base64 -i 证书.p12 \| pbcopy`（Mac）或 `base64 -w0 证书.p12`（Linux） |
| `CERT_PASSWORD` | 证书密码（当前为 `1`） | 直接粘贴密码 |
| `PROVISIONING_PROFILE_BASE64` | 主 App 描述文件的 base64 | `base64 -w0 描述文件.mobileprovision` |

### 3. 创建小组件描述文件（想要桌面小组件就必做，约 2 分钟）

登录 [developer.apple.com](https://developer.apple.com/account) → Certificates, IDs & Profiles：

1. **Identifiers → + → App IDs → App**
   - Description：`CarRemote Widget`
   - Bundle ID（Explicit）：`app.copper1249.chipmunk6639.CarWidget`
2. 勾选能力 **App Groups**，只勾 `group.6cd6b6c14418f98a.1` → Continue → Register
   > 小组件只读 App Group 里的车况快照；桌面按钮的 App Intent 由系统拉到主 App 进程执行，凭据访问发生在 App 侧，因此小组件**不需要** Keychain Sharing，少勾一项少一个签名失败点。
3. **Profiles → + → Ad Hoc** → 选择刚建的 `CarRemote Widget` App ID → 选择你的分发证书 → 勾选同一台设备 → 生成 → 下载 `.mobileprovision`
4. 添加 Secret：`PROVISIONING_PROFILE_WIDGET_BASE64` = 该文件的 base64（`base64 -w0 小组件.mobileprovision`）

> 不添加这个 Secret 也能构建：流水线会自动降级输出**无小组件**的 IPA，其余功能完整。想要小组件就按上面 4 步补上。

### 4. 触发构建

- 自动：push 到 `main` 即触发；
- 手动：Actions → 「Build IPA」→ **Run workflow**。

构建成功后下载 Artifact 解压，得到 **CarRemote.ipa**。

> 免费额度：GitHub Actions 公开仓库 unlimited；私有仓库每月 2000 分钟，macOS 构建 10 倍扣费（本工程约 5–10 分钟/次，够用很久）。

---

## 四、安装 IPA 到 iPhone

当前主描述文件是 **Ad Hoc 类型，只登记了 1 台设备**（UDID `00008120-000438C92E31A01E`），所以 IPA 目前只能装到这一台上。安装方式任选：

1. **Apple Configurator 2**（Mac，免费）：连接 iPhone → 添加 → 选择 IPA；
2. **爱思助手等助手类工具**（Windows）：导入 IPA 一键安装；
3. **Sideloadly**（Win/Mac）：拖入 IPA，登录 Apple ID 安装（仍受描述文件设备限制，需该 Apple ID 对应设备已登记）。

装完后第一次打开如提示「不受信任的开发者」：设置 → 通用 → VPN与设备管理 → 选择该证书 → 信任。

### 想装到更多手机？

1. 收集新手机的 UDID（爱思助手/配置器都能读）；
2. developer.apple.com → Devices → 注册新 UDID；
3. **重新生成两个 Ad Hoc 描述文件**（主 App + 小组件各一个，都勾选新设备），下载新的 `.mobileprovision`；
4. 更新 GitHub 上对应的 Secret（`PROVISIONING_PROFILE_BASE64` / `PROVISIONING_PROFILE_WIDGET_BASE64`）——CI 会自动提取新 UUID，**无需改任何仓库文件**；
5. 重新触发构建。

---

## 五、本地开发（有 Mac 的话）

```bash
brew install xcodegen
cd CarRemote

# 完整版（含小组件）：先按「三、3」下载小组件描述文件，然后
export WIDGET_PROFILE_UUID=<小组件描述文件的 UUID，可用 security cms -D -i xxx.mobileprovision | plutil -extract UUID raw 查看>
INCLUDE_WIDGET=true xcodegen

# 或者无小组件版
xcodegen

open CarRemote.xcodeproj
```

打开后直接在 Xcode 里选择真机 Run。注意：本地跑需要 Mac 上已导入同一证书与描述文件，或在 Xcode 的 Signing & Capabilities 里换成自己的开发者账号（免费账号 7 天签名，功能不受影响，但小组件/推送能力以付费账号为准）。

---

## 六、使用说明

1. **登录**：手机号 + 控车码（与网页版一致）；新用户可短信注册；
2. **授权**：正式用户直接进主界面；未授权用户进入卡密网关，输入 `CH-XXXX-XXXX` 兑换当天体验；被封禁手机号会看到联系站主提示（QQ `2317665079`）；
3. **小组件**：长按桌面 → 「+」→ 搜索「长安控车」→ 选择尺寸；锁屏界面同样可添加；
4. **Siri**：安装 App 后直接说「嘿 Siri，用长安控车解锁车辆 / 闪灯 / 鸣笛 / 开空调 / 关车窗 / 车况怎么样」；
5. **油耗 / 维保**：本地记录，与网页版 localStorage 数据相互独立，不随换手机同步（后续可加服务端同步）。

---

## 七、常见问题

- **构建报「未找到 iPhone Distribution 签名身份」**：检查 `CERT_P12_BASE64` 是否正确（base64 单行无换行）、密码是否为 `1`；证书 2027-09-28 到期，过期需重新生成 p12。
- **构建报 `Provisioning profile ... doesn't match` / 小组件签名失败**：说明没配 `PROVISIONING_PROFILE_WIDGET_BASE64` 或小组件描述文件的 Bundle ID 不对，按「三、3」检查；此时流水线降级为无小组件版本。
- **小组件显示「暂无车况数据」**：先在 App 里登录并下拉刷新一次车况（快照写入 App Group 后小组件即可读）；若仍为空，检查小组件 App ID 是否勾了 App Groups。
- **IPA 安装失败/无法验证**：目标设备 UDID 未登记到描述文件（见「四」）。
- **控车提示「token 失效」**：App 会自动用 refresh_token 续期；若官网改了密码，重新登录即可。
- **车况字段为空**：不同车型字段名有差异，App 已做候选键名容错；个别车型仍可能缺字段，属于车端上报问题，不影响控车。

---

## 八、目录速查（要改的东西）

| 想改什么 | 改哪里 |
| --- | --- |
| 站点地址 / 联系 QQ | `CarCore/Config/APIConfig.swift` |
| 加一条控车指令 | `CarCore/Models/CarModels.swift` + `CarCore/Intents/CarControlIntents.swift` + `CarRemote/Intents/AppShortcutsProvider.swift` |
| 换主 App 证书 / 描述文件 | 改 `project.yml` 里的 `CODE_SIGN_IDENTITY`（共 3 处：工程级 + CarRemote + CarCore）与 `PROVISIONING_PROFILE_SPECIFIER`（仅 CarRemote 目标级，框架目标不能带描述文件）；小组件改 `project.widget.yml`（CI 会用上传的描述文件自动覆盖 UUID，证书名需手动改） |
| 小组件开关 / 描述文件 | `project.widget.yml` + Secret `PROVISIONING_PROFILE_WIDGET_BASE64` |
| 换 App 图标 | 替换 `CarRemote/Assets.xcassets/AppIcon.appiconset/AppIcon.png`（1024×1024） |
| 主题色 | `CarRemote/Assets.xcassets/AccentColor.colorset/Contents.json` |
