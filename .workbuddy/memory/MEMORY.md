# Atoll (DynamicIsland for macOS) 项目长期记忆

## 项目性质

macOS SwiftUI 应用，把 MacBook 刘海做成可展开的命令面板（Atoll，原 DynamicIsland）。
Xcode 27 / Swift 6.4，GPL v3。源码主体在 `DynamicIsland/`，363+ 个 Swift 文件。

## 在本机构建（重要）

日常编译（只要能在 Xcode 里跑，不装到 /Applications）：

```bash
cd /Users/zhanghl/WorkBuddy/Atoll
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
```

要**装到 /Applications 替换已安装的 App** 时，必须用 ad-hoc 身份让 Xcode 自己签名：

```bash
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  OTHER_CODE_SIGN_FLAGS="--deep" clean build
```

- **不要**走「先 `CODE_SIGNING_ALLOWED=NO` 构建、再手工 `codesign --force --deep --sign -`」这条路：
  `--deep` 重签 Sparkle.framework 会破坏嵌套结构，校验报
  `code has no resources but signature indicates they must be present`，App 起不来。
- entitlements 里写的是 `$(PRODUCT_BUNDLE_IDENTIFIER)-spks / -spki`（Sparkle 的 XPC 服务）。
  手工签名时变量**不会展开**；交给 Xcode 签名才会替换成 `com.Ebullioscopic.Atoll-*`。
- 本机没有 team ID `9Y64TRM77N` 的 Developer ID / Mac Development 证书，
  用默认配置构建直接 `No signing certificate ... found` 失败。
- 产物路径：`~/Library/Developer/Xcode/DerivedData/DynamicIsland-gbyymgfpilamnthhplqqupvbhfwe/Build/Products/Release/Atoll.app`
  （Release 约 87M、arm64 only；官方发布版是 44M 的 x86_64+arm64 通用包）

## 替换已安装 App 的注意

- 装完是 ad-hoc 签名，**cdhash 变了 → TCC 权限要重新授权**（辅助功能、屏幕录制、日历等），
  Sparkle 自动更新也会因签名校验失败而不可用。
- 退出正在运行的实例用 `killall Atoll`（`osascript quit` 会因为 Automation 权限报 -10004）。
- 替换流程：备份 → 旧版 `mv` 进废纸篓（不要 `rm -rf` /Applications）→ `cp -R` 新产物 →
  `codesign -v` 校验 → `open -a` 启动确认。
- 当前备份：`/Applications/Atoll.app.backup-20261002`（官方 2.3.3 原件，确认无误后可删）。
- **必须绕过沙箱**：默认 Bash 沙箱会让 SwiftPM 报 `sandbox-exec: sandbox_apply:
  Operation not permitted`，伪装成 "Could not resolve package dependencies"。
  用 `dangerouslyDisableSandbox: true` 且**在前台运行**（后台任务拿不到批准）。
- 已编译过的文件不会重报警告；要检查新文件的警告需先 `touch` 再 build。
- DerivedData 已有包 checkout：`~/Library/Developer/Xcode/DerivedData/DynamicIsland-gbyymgfpilamnthhplqqupvbhfwe/`。

## 工程结构要点

- **Xcode 16+ 文件同步**：`project.pbxproj` 用 `PBXFileSystemSynchronizedRootGroup`
  （根 = `DynamicIsland`，仅 `Info.plist` 例外），**新建 .swift 文件自动纳入 target，无需改工程文件**。
- `Defaults`（sindresorhus）是设置存储；键定义在 `models/Constants.swift` 的
  `extension Defaults.Keys`（约 984 行起）。视图里统一用 `@Default(.xxx)`。
- **设置面板几乎全在 `components/Settings/SettingsView.swift`**（现已 1 万行）。
  `SettingsTab` / `SettingsTabGroup` 是 **private**，加一页要改 6 处：
  tab 枚举 case、group、title、systemImage、tint、`detailView(for:)`，
  另有 `availableTabs`（手工有序数组，漏加就不显示）与 `SettingsSearchIndex.entries`。
  页面范式：`Form { Section { ... } header/footer }` + `.navigationTitle("X")` +
  行上 `.settingsHighlight(id: highlightID("标题"))`（标题串要和搜索索引一致）。
- **灵动岛 tab 栏**在 `components/Tabs/TabSelectionView.swift`；挂载点
  `components/Notch/DynamicIslandHeader.swift:92`。
- **面板宽度**由 `sizing/matters.swift` 的 `enabledStandardTabCount()` 手算，
  它**手工镜像** TabSelectionView 的逻辑 —— 加 tab 必须同步改，否则布局挤。
  改完后还需在 `DynamicIslandViewCoordinator` 的 `Publishers.MergeMany` 里加订阅才会重算。

## 本地化（改文案前必读）

- **生效目录是 `DynamicIsland/Localizable.xcstrings`**；仓库根目录还有一份同名文件，
  但它**不在 target 里**（同步根组只有 `DynamicIsland` 和 `Contents`），改它没用。
- `sourceLanguage: en`，19 种语言，zh-Hans 覆盖率约 87%。主人机器跑中文界面，
  所以新文案必须补 zh-Hans，否则只有英文。
- SwiftUI 里 `Text("字面量")` 会走 `LocalizedStringKey` 自动查表；`String(localized:)` 同理。
  带插值的 key 会变成 `%lld` / `%@`，例如 `Text("\(count) lines")` 的 key 是 `"%lld lines"`。
- **安全写入方式**（改前先 `cp` 备份）：

  ```python
  d = json.load(open('DynamicIsland/Localizable.xcstrings', encoding='utf-8'))
  d['strings'][key] = {"localizations": {
      "en":      {"stringUnit": {"state": "translated", "value": key}},
      "zh-Hans": {"stringUnit": {"state": "translated", "value": 中文}},
  }}
  open(path,'w').write(json.dumps(d, ensure_ascii=False, indent=2, separators=(',', ' : ')))
  ```

  **千万不能 `sort_keys=True`** —— `strings` 里有个空串 key，一排序就把既有顺序打乱。
  不排序时 `json.load` → `json.dumps` 是**字节级往返一致**的，可以先跑一遍确认再改。
- **key 冲突是真实存在的坑**：同一个英文串在不同模块含义不同时（如 `"Fair"` 既是空气质量等级
  又是密码强度），共用一个 key 会互相污染。解法是给其中一个开独立字符串表：
  新建 `DynamicIsland/<表名>.xcstrings`（会被自动同步进 target），
  代码里写 `String(localized: "Fair", table: "PasswordGenerator")`。
  现成的例子：`DynamicIsland/PasswordGenerator.xcstrings`。
- 验证打包结果：

  ```bash
  cd ~/Library/Developer/Xcode/DerivedData/DynamicIsland-gbyymgfpilamnthhplqqupvbhfwe/Build/Products/Release/Atoll.app/Contents/Resources
  plutil -convert xml1 -o - zh-Hans.lproj/Localizable.strings   # 检查译文是否进去
  ```

## 统计图表（NotchStatsView）

- `components/Notch/NotchStatsView.swift`：`GraphData` 协议 + `SingleGraphData`（单值）
  / `DualGraphData`（双值，网络/磁盘）。卡片统一由 `UnifiedStatsCard` 渲染，
  头部是 `图标 + 标题 + Spacer() + 温度`。
- 图表数量决定布局：≤3 一行；4 → 2×2；5 → 3+2。开关在设置页「统计 › Graph Visibility」。
- **温度数据源很少**：只有 CPU（`statsManager.cpuTemperature.celsius`，走 SMC）和
  GPU（`gpuDevices[].temperature`，走 IOKit PerformanceStatistics）有传感器；
  内存/网络/磁盘没有。目前策略是 CPU/GPU 取各自的，其余回落 SoC(CPU) 温度，
  由 `Defaults[.showTemperatureOnStatsCards]`（默认开）控制显隐。
  单位换算复用 `Defaults[.cpuTemperatureUnit]` + `LockScreenWeatherTemperatureUnit.symbol`。

## 复用组件（新增 UI 优先用这些，别重复造）

- `VisualEffectView(material:blendingMode:)` — `components/Settings/EditPanelView.swift`
- `NativeStyleCloseButton(action:)` — `components/ColorPicker/ColorPickerPanel.swift`
- 浮出面板范式：`ClipboardPanel` / `ColorPickerPanel`（NSPanel + 圆角 mask + 位置记忆）
- notch 上挂 `.popover(isPresented:arrowEdge: .bottom)` 是既有做法（剪贴板/取色器）
- 弹窗打开时要设 `vm.isXPopoverActive` 并加进 `ContentView.hasAnyActivePopovers()`，
  否则鼠标离开 notch 会自动收起。

## 已实现的功能（本次二次开发新增）

1. **代码格式化**：入口在 tab 栏 Terminal 右侧，点开独立浮出面板（HSplitView 左右分栏，
   左输入 + 语言下拉，右结果）。引擎 `components/CodeFormatter/CodeFormatterEngine.swift`
   纯 Swift 无三方依赖，支持 JSON/YAML/SQL/HTML/XML/CSS/JS 的 format 与 minify。
2. **密码生成器**：入口在代码格式化右侧，弹出紧凑 popover（密码 + 强度条 + 重生成 + 复制）。
   规则在设置里配（长度/大小写/数字/自定义符号集/排除易混/每类必含/去重/自动复制）。
   随机源用 `SecRandomCopyBytes` + 拒绝采样。
3. **入口显隐**：新增 `NotchEntry` 枚举（在 `enums/generic.swift`）+
   `Defaults[.notchEntryVisibility]` 字典（`缺失=显示`），设置页「Notch Entries」统一开关全部入口。
   新增的两个功能默认关闭（与 Terminal 惯例一致），需要在设置里先开启。

## 验证资产

`.workbuddy/tmp/engine-harness.swift`：格式化引擎的独立验证脚本（56 项断言，全绿）。
引擎不依赖 AppKit/SwiftUI，可脱离 Xcode 单独编译：

```bash
cd .workbuddy/tmp
cat ../../DynamicIsland/components/CodeFormatter/CodeFormatterEngine.swift engine-harness.swift > Combined.swift
swiftc -o engine-test Combined.swift && ./engine-test
```

改动格式化逻辑后请重跑它。
