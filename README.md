# PickBank iOS · 拾念记账（原生 SwiftUI 液态玻璃版）

> **纯粹的原生 iOS / iPadOS 应用程序（非 WebApp / 非 PWA）**

基于原 Android `pickbank` (v1.7.7) 与 `pickbank-app` (`com.sum.ledger`, v1.9.1/v1.9.2) 深度重构与 1:1 功能还原移植的 **Swift 6 + SwiftUI Universal App（iPhone + iPad）**，全面融合 **iOS 26 Liquid Glass（液态玻璃）** 设计语言与 PickBank 标志性的 **经典暖黑（OLED Warm Dark）/ Hermes 皇室蓝（Editorial Royal Blue）** 双主题美学，面向 **$0 免费 Apple ID 自签与 Sidestore 安装**（无需 $99 开发者年费，不上架 App Store）。

## 核心原生特性（Android v1.9.2 完整移植 + iOS 深度强化）

- **iOS 26 Liquid Glass & 双主题圆弧扩散动效**：在 iOS 26+ 使用原生 `GlassEffectContainer` / `.glassEffect` / `.glassEffectID` / `.buttonStyle(.glass)` 形态融合与折射；兼容 iOS 18 光学高光降级材质；一键切换经典 OLED 暖黑与 Hermes 皇室蓝全屏墨水扩散主题。
- **全能记账与智能解析引擎**：
  - `Int64` 整数分高精度 SQLite WAL 持久化底座 + 算术快捷键盘（`35+12.5*2`）。
  - 中英双语 NLP 一句话多笔记录解析（支持 `#标签` 自动识别建标与多钱包匹配）。
  - **分类月度支出限额（`CategoryMonthlyLimit`）**：首页限额进度看板与超支预警。
  - **周期固定账单 + 分类归档与永久分类名称快照**。
- **统计分析与本地 AI 问账**：
  - **月度收支热力日历（Monthly Calendar Heatmap）**、周期切换（周/月/年/自定义 + 锚点重置）、环比对比条、分类饼图与 7 日 Sparkline。
  - **本地检索优先问账（`AiLocalQueryEngine`）**：识别「今天 / 上个月 / 去年 / 关键词」并在调用 OpenAI 兼容接口前生成离线检索明细卡片与报告；密钥存系统 Keychain，支持一键连通性与问账管道验证。
- **完整 8 物种像素伙伴生态（内嵌 Android 同源 1,813 份 MIT 素材）**：
  - 全量打包 8 大物种（小猫 / 小狗 / 小羊 / 小鱼 / 小牛 / 小马 / 熊猫 / 兔子）的昼夜同源小屋背景 (`rooms/`)、39 个演出动作槽位 (`slots`)、5 个真实日历生命阶段 (`infant / young / prime / middle_aged / senior`) + 清理补丁 (`stage_patches/`) 与 288 帧透明漫步/探头/游窗精灵 (`roaming/`)。
  - `HabitatHudIdleState` 5 秒无操作自动淡出全屏沉浸舞台；单点唤醒；双路线（30 天+好感40 或 成长120+好感30）渐进解锁无限新栏位；输入准确名字二次确认后**放生并永久封存纪念档案**。
  - **多动作/视频自定义伙伴工坊**：支持透明 PNG 序列帧（1–30 FPS）或循环 `.mp4`/`.mov` 视频、动作角色时段匹配（玩耍/进食/休息/陪伴）、自定义小屋背景与已领养删除锁定保护。
- **全量数据主权与自动定时本地备份**：
  - 无损全量 `.pickbank.json`（SHA-256 校验）、`PBKDF2-SHA256 + AES-256-GCM` 加密备份、原生 OpenXML `.xlsx` 工作簿、UTF-8 BOM `.csv`；智能识别微信支付 CSV、支付宝 CSV 与 Android `Pickbank` JSON 迁移包。
  - 可配置自动定时本地备份（关闭 / 每 6 小时 / 每日 / 每周 / 退后台变更即备）与上限保留清理，支持通过 `Security-Scoped Bookmark` 绑定「文件 App / iCloud Drive」外部同步目录。
  - 本地数据治理（占用体积可视化、重复账目扫描合并、一致性校验修复、快照时光机还原与防误删重置）。

## 直接打开 Xcode 工程与本地测试验证

本仓库根目录下即包含统一 **Swift 6 Package（[Package.swift](Package.swift)）** 与提交就绪的 **原生 Xcode 工程（[PickBank.xcodeproj](PickBank.xcodeproj)）**，克隆后可直接打开与编译：

```zsh
# 1. 运行全套 Swift Targets 编译 + 18 项单元测试（包含 1,813 份素材解析验证）
./scripts/run_tests.sh

# 2. 在已安装 Xcode 的 Mac 上直接打开工程真机运行（选择个人免费 Apple ID Team）
open PickBank.xcodeproj

# 3. 无付费证书本地打包通用未签名 PickBank-iOS.ipa（供 SideStore / AltStore / Sideloadly 安装）
./scripts/build_unsigned_ipa.sh
```

## GitHub Actions 云端自动构建未签名 `.ipa`

仓库内的 [ci/ios-release.yml](ci/ios-release.yml) 已完整配置 `macos-26` + Xcode 26 / iOS 26 SDK 云端编译链路，可自动运行 `./scripts/run_tests.sh` 并构建通用（iPhone + iPad）未签名 `PickBank-iOS.ipa` 与 `SHA256SUMS.txt` 发布至 GitHub Release。

> 注：由于终端初始 `gh` Token 缺少 `workflow` 作用域，`ci/ios-release.yml` 存放在 `ci/` 目录。执行附带脚本即可一键完成授权激活并推送至 `.github/workflows/ios-release.yml`：
>
> ```zsh
> ./scripts/enable_cloud_ipa_ci.sh
> ```

免付费开发者账号装机教程详见 [零费用安装指南](docs/SIDELOAD_GUIDE_CN.md)，系统架构与 Android 对照表详见 [架构与移植蓝图](docs/ARCHITECTURE_AND_PORTING.md)。

## License

[MIT License](LICENSE) · 素材归属声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
