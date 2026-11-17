# PickBank iOS 架构解析与跨平台移植蓝图

## 1. 原版 Android `pickbank` / `pickbank-app` 深度理解

通过深度审计 `smartlotus/pickbank` (v1.7.7) 与 `smartlotus/pickbank-app` (v1.9.2) 的完整源码与契约，原项目的核心工程资产如下：

1. **纯净无广告账本底座 & 整数分契约**：
   - 全部交易金额采用 `Int64`（单位：分）存储，严格避免浮点精度漂移。
   - **v1.7.7 分类归档与永久分类名称快照**：每笔交易写入时将绑定分类名固化到 `categoryNameSnapshot`；分类支持**归档**（从新建下拉/手动录入选择面隐藏，但在历史统计与明细中保留并通过 `（已归档）` 标注）与**彻底删除**（即使分类行被删除，历史流水仍完整显示原分类名）。
2. **自然语言多笔解析引擎 (`NlpParseEngine`)**：
   - 支持单句同时记多笔（逗号/句号/`然后`/`还买了` 分词），识别阿拉伯数字与中文大写数字（如`三十五元`）、相对日期（`今天/昨天/前天`）与早中晚时间段推理。
3. **MVI 响应式页面矩阵**：
   - 记账台 (`Home`)：预算余量环、近 7 日支出折线、周期固定账单、一键复制/删除撤销、账单文件导入。
   - 总结页 (`Summary`)：日/周/月/年/自定义区间、环比对照、分类占比环、柱状分布点击下钻当日流水，且遵守 **v1.9.2 维度切换锚点重置为当前时刻**。
   - 明细流 (`Details`)：多时间预设、关键词全局搜索（含快照分类名）、收支与分类筛选。
   - AI 洞察与问账 (`AI`)：自带服务商与 API Key (BYOK)，支持 DeepSeek / OpenAI / Kimi / 通义千问 / 智谱及自定义 OpenAI 兼容协议。
4. **双主题视觉 DNA**：
   - **经典暖黑 (`Classic Warm Dark`)**：OLED 纯黑 `#000000` + 暖炭灰 `#1B1917` + 暖琥珀强调 `#FFB74D` + 柔和草绿收入 `#A5D6A7` + 珊瑚橙支出 `#FFAB91`。
   - **Hermes 编辑风格皇室蓝 (`Hermes Royal Blue`)**：高饱和 `#0000F2` + 纸白 `#F5F5F5` + 酸性黄 `#EDFF45` + 极细印版注册框线与慢速粒子/轨道天体底纹。
5. **像素伙伴养成系统（v1.6 – v1.9.2）**：
   - 内置 8 种原创 MIT 物种（猫、狗、羊、鱼、牛、马、熊猫、兔）+ 39 个策展固定动作 + 同构 `DAY` (`05:00-16:59`) / `NIGHT` (`17:00-04:59`) 房间背景。
   - 预算结余转化为每日能量（每日上限 30 ⚡），饱腹、成长与每日最多 +3 好感。
   - 真实本地日历五阶段单调生命周期（幼崽/青年/壮年/中年/老年 + 生病/纪念），**v1.9.0 放生纪念与渐进式无限栏位解锁**（满 30 天且好感 ≥ 40，或成长 ≥ 120 且好感 ≥ 30 可解锁新栏位并允许放生至永久纪念档案），**v1.8.0 自定义伙伴工坊**。

---

## 2. iOS / iPadOS 移植设计与发散性升级

### 2.1 双层工程结构（本地可验证 + CI 产包）
- **`Packages/PickBankCore`**（纯 Swift 6 Package，零第三方依赖）：
  - 全部实体模型、SQLite3 关系持久化 (`sum_ledger.db`)、整数分与算术键盘求值、双语多笔 NLP 引擎、统计分析、宠物生命周期与放生契约、BYOK Keychain & OpenAI 客户端，以及**全新数据主权子系统**均沉淀在本包，可通过 `swift test` 在任意 macOS/Linux/CI 环境独立验证。
- **`PickBankApp`**（通用 iPhone + iPad SwiftUI 应用）：
  - **iOS 26 液态玻璃 (Liquid Glass) 适配**：通过 `#if compiler(>=6.2)` + `@available(iOS 26.0, *)` 接入原生 `GlassEffectContainer`、`.glassEffect(.regular.tint(...).interactive(), in: ...)`、`.glassEffectID` 形态融合、`buttonStyle(.glass)` 与 `.buttonStyle(.glassProminent)`；在 iOS 18 上自动回退至多层次高光描边 `.ultraThinMaterial`，兼顾液态折射通透感与财务数字的锐利可读性。
  - **iPhone 与 iPad 双形态人体工学**：
    - iPhone 端采用底部悬浮液态玻璃胶囊导航栏 + 实时 NLP 解析胶囊预览。
    - iPad 端启用 `NavigationSplitView` 侧边栏 + 双栏 Bento 仪表盘，支持多向横竖屏旋转、指针悬停 `.hoverEffect(.lift)` 与硬件键盘快捷键（`⌘N` 新建账单、`⌘K` 聚焦快记、`⌘B` 立即备份、`⌘T` 切换主题）。
  - **算术记账键盘 & 多钱包轻标签**：手动录入支持 `35 + 12.5 * 2` 四则运算实时换算；支持微信/支付宝/银行卡/现金等钱包标签且保持 1 秒快记默认流不变。

### 2.2 全新数据主权、自动定时本地备份与本地数据治理中心 (`DataSovereigntyCenterView`)
针对无开发者付费账号（$0 自签每 7 天续签）与隐私优先需求：
1. **全格式双向本地导入导出 (`ArchiveCodec` & `UniversalImporter`)**：
   - `.pickbank.json`（v2 全量无损快照 + SHA-256 校验，含账目、分类归档、预算、周期规则、多钱包及全套宠物与自定义宠物定义）。
   - `.pickbank.enc.json`（PBKDF2-SHA256 120,000 轮 + AES-256-GCM 加密备份，与 PickBank Web 加密结构对齐）。
   - `.xlsx`（纯 Swift 原生 OpenXML + RFC1951 Deflate 压缩工作簿导出与读取，可直接导入 Android Pickbank 导出的 `.xlsx`）。
   - `.csv`（UTF-8 BOM，自动识别并导入微信支付账单 CSV、支付宝账单 CSV、PickBank CSV 及 Android 迁移包 JSON）。
   - 导入前先执行 **Dry-Run 预演**（展示检测格式、校验状态、重复数与净新增数），支持**智能合并去重**或**覆盖替换（强制先写锁定 Safety Snapshot）**。
2. **自动定时本地备份 (`AutoBackupScheduler`)**：
   - 支持关闭 / 每 6 小时 / 每日定时 / 每周定时 / 数据变更退至后台即备；注册 `BGAppRefreshTask` 与 `scenePhase` 双重保障。
   - **「文件」App 原生可见 + 外部安全书签同步目录**：开启 `UIFileSharingEnabled` 与 `LSSupportsOpeningDocumentsInPlace`，同时支持绑定系统「文件 / iCloud Drive」外部目录的 Security-Scoped Bookmark——即使 7 天自签过期重装 App，外部备份依然毫发无损！
   - 智能保留清理策略：超过上限时仅清理最旧的自动备份，永久保护手动锁定、安全快照与置顶快照。
3. **本地数据治理 (`DataGovernanceService`)**：
   - 本地存储空间分层统计、疑似重复账单扫描与安全合并、数据库一致性体检与快照修复、按条件批量清理、一键演示数据注入/清空，以及附带预备份保护的账本重置。
