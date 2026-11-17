# 零开发者费用（$0）安装 PickBank iOS 到 iPhone 与 iPad 完整指南

PickBank iOS 刻意去除所有付费 Apple Developer 专属能力（无 Push、无私有 App Group、无云端付费 entitlement，`.entitlements` 保持空字典），因此可以 **0 元免费 Apple ID** 直接安装到你的 iPhone 和 iPad 长期使用，无需上架 App Store，也无需缴纳每年 $99 美元开发者费用。

---

## 方式一：SideStore（最推荐 · 手机端 Wi-Fi 自动续签，装完不再依赖电脑）

1. 初次引导（仅需电脑一次）：在 Mac 或 Windows 安装 **SideStore** 与配对工具（按 SideStore 官方引导启用 iPhone/iPad 开发者模式）。
2. 在 iPhone / iPad Safari 下载 **`PickBank-iOS.ipa`**（可从 GitHub Release 或官方网页 `https://pickbank-ios.pages.dev/downloads/PickBank-iOS.ipa` 下载），或直接把源地址 `https://pickbank-ios.pages.dev/downloads/altstore-source.json` 添加进 SideStore。
3. 在 SideStore 内选择 `PickBank-iOS.ipa`，使用你的免费普通 Apple ID 完成自签安装。
4. 在 `设置 -> 通用 -> VPN 与设备管理` 中信任你的 Apple ID 证书即可打开。
5. **续签方式**：日常每隔 7 天内，手机连上任意 Wi-Fi 并开启 SideStore 内的本地回环 VPN，点一次「Refresh All」即可 3 秒续期 7 天（可配合 iOS 快捷指令实现全自动续签）。

---

## 方式二：Sideloadly / AltStore（Mac / Windows 一键签名安装）

1. 在电脑端打开免费开源工具 **Sideloadly** 或 **AltStore**。
2. 用数据线或同局域网 Wi-Fi 连接 iPhone 或 iPad，将 `PickBank-iOS.ipa` 拖入窗口。
3. 输入普通免费 Apple ID 登录签名并安装（注意：免费账号同时最多安装 3 个自签应用）。
4. 在设备上信任开发者证书并开启使用。

---

## 方式三：Xcode 免费 Personal Team（源码直装）

如果你后续在 Mac 上安装了 Xcode（免费版即可，无需付费账号）：

```bash
git clone https://github.com/smartlotus/pickbank-ios.git
cd pickbank-ios
brew install xcodegen
xcodegen generate
open PickBank.xcodeproj
```

1. 在 `Signing & Capabilities` 选择你自己的普通 Apple ID（Personal Team），把 Bundle Identifier 改为个人唯一后缀（例如 `com.yourname.pickbank`）。
2. 连接 iPhone 或 iPad，直接 `Cmd + R` 构建并安装到真机。

---

## 防重装丢数据贴士（强烈建议开启）

因为免费 Apple ID 自签证书有效期为 7 天，万一忘记续签导致应用无法打开需要覆盖重装，强烈建议打开 PickBank 的两项数据保护开关：
1. 进入「**数据**」页签 →「**自动定时本地备份设置**」→ 点击「**选择目录**」绑定一个「文件」App 中的独立文件夹（例如 `iCloud 云盘/PickBankBackups` 或 `我的 iPhone/文档/PickBankBackups`）。
2. 启用「**数据变更退至后台即备**」或「**每日定时备份**」。即使卸载或过期重装 App，只需在「数据 → 智能导入文件」选中该外部文件夹里的 `.pickbank.json` 快照即可 100% 瞬间复原。
