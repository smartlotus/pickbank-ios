# PickBank iOS · 拾念记账（液态玻璃版）

基于原 Android `pickbank` (v1.7.7) 与 `pickbank-app` (v1.9.2) 深度重构与升华的原生 **SwiftUI Universal App（iPhone + iPad）**，融合 **iOS 26 Liquid Glass（液态玻璃）** 设计语言与 PickBank 标志性的 **经典暖黑 / Hermes 皇室蓝** 双主题美学，面向 **$0 免费 Apple ID 自签安装**（无需支付 $99 年费，不上架 App Store）。

## 核心特性

- **液态玻璃 & 双主题视觉**：在 iOS 26+ 使用原生 `GlassEffectContainer` / `.glassEffect` / `.glassEffectID` 形态融合与流体折射（iOS 18 自动适配高光光学玻璃材质）；保留经典 OLED 暖黑与 Hermes 皇室蓝编辑风双主题。
- **全能记账底座**：整数分 (`Int64`) 精确计算、算术快捷键盘 (`35+12.5*2`)、中英双语自然语言多笔实时解析、多钱包标签、周期固定账单、分类归档与**永久分类名称快照**。
- **iPhone + iPad 原生自适应**：iPhone 悬浮液态玻璃胶囊底栏；iPad `NavigationSplitView` 侧边栏 + 多栏 Bento 看板 + 指针悬停反馈 + 硬件键盘快捷键（`⌘N`、`⌘K`、`⌘B`、`⌘T`）。
- **8 物种像素伙伴生态**：完整保留 8 种 MIT 授权像素伙伴、同构昼夜场景、真实日历五阶段生命周期、每日预算结余能量结算、放生纪念与渐进式无限栏位，以及自定义图片/帧序列工坊。
- **全量数据主权与自动定时本地备份**：
  - 导出/导入：`.pickbank.json` 无损全量备份 (SHA-256)、`PBKDF2+AES-256-GCM` 加密备份、原生 OpenXML `.xlsx` 工作簿、UTF-8 BOM `.csv`，并智能识别微信支付/支付宝账单 CSV 与 Android Pickbank 迁移包。
  - 自动定时备份：关闭 / 每 6 小时 / 每日定时 / 每周 / 退后台变更即备，自动保留上限清理，支持绑定「文件」App / iCloud Drive **外部防丢同步目录**。
  - 本地数据治理：占用空间分析、重复账目扫描合并、一致性体检修复、按条件批量清理、快照时光机与安全重置。

## 本地验证与编译

```zsh
# 运行纯 Swift 6 核心单元测试
cd Packages/PickBankCore && swift test

# 使用 XcodeGen 生成工程（需安装 Xcode + xcodegen）
xcodegen generate
open PickBank.xcodeproj
```

## GitHub Actions 云端自动构建未签名 IPA

仓库内的 [ci/ios-release.yml](ci/ios-release.yml) 已完整配置 `macos-26` + Xcode 26 / iOS 26 SDK 云端编译链路，可自动运行 `PickBankCore` 单测并打包通用（iPhone + iPad）未签名 `PickBank-iOS.ipa` 及 `SHA256SUMS.txt` 发布到 GitHub Release。

> 注：由于当前终端 `gh` OAuth Token 仅含 `repo` 权限（不含 `workflow` 作用域），`ci/ios-release.yml` 暂存于 `ci/` 目录。若需启用自动云端构建，请在本机执行以下授权并将该文件移入 `.github/workflows/ios-release.yml` 推送（或在 GitHub 网页端手动新增 Workflow）：
>
> ```zsh
> gh auth refresh -h github.com -s workflow
> mkdir -p .github/workflows && mv ci/ios-release.yml .github/workflows/ios-release.yml
> git add -A && git commit -m "ci: enable GitHub Actions unsigned IPA release" && git push
> ```

免付费开发者账号安装方式详见 [零费用安装指南](docs/SIDELOAD_GUIDE_CN.md)，架构细节见 [架构与移植蓝图](docs/ARCHITECTURE_AND_PORTING.md)。

## License

[MIT License](LICENSE) · 素材归属声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
