# Pomme 🍎

<p align="center">
  <strong>专为苹果硬件收藏家与爱好者打造的数字博物馆与策展人资产管理平台</strong>
</p>

<p align="center">
  <a href="README_zh.md"><strong>🇨🇳 简体中文</strong></a> | 
  <a href="README.md"><strong>🇺🇸 English</strong></a>
</p>

<p align="center">
  <img src="pomme-app-icon-1024-circle.png" alt="Pomme Icon" width="128" height="128">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20watchOS%20%7C%20visionOS-black?style=flat-square&logo=apple" alt="支持平台">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0071e3?style=flat-square" alt="SwiftUI 原生构建">
  <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT 开源协议">
</p>

---

## 🌟 项目简介

**Pomme** 是一套苹果原生现代设计风格的跨平台硬件数字图鉴、实体藏品档案库与资产估值管理工作台。

无论您收藏的是数十年前的中古 Macintosh 电脑、复古 Click-Wheel 转盘 iPod、稀有原型机，还是当代活跃在工作流中的 Apple Silicon 主力生产力设备，Pomme 都能为您所有心爱的硬件提供一个纯粹、离线优先且尊重隐私的数字化归宿。

---

## ✨ 核心特性

### 🏛️ 1. 全品类 Apple 硬件百科图鉴
* **跨越数十载的苹果硬件谱系**：覆盖 Vintage 老 Mac、现代 MacBook / Mac mini / Mac Studio / Mac Pro、iPhone、iPad、iPod、Apple Watch、AirPods、专业显示器、AirTag，以及各类官方转接头与配件。
* **高精度规格参数**：收录机型内部代号（如 `Macmini2,1`、`A1296`）、发售年份、官方配色、首发指导价、芯片架构与内存/存储标准。
* **多级检索与层级聚合**：支持多级硬件品类下钻、全局模糊拼音搜索与动态分类封面自定义。

### 📊 2. Mac 策展人工作台 (Curator Workbench)
* **专业级桌面三栏布局**：左侧智能分类与视图导航、中间自适应磁吸网格 / 高密度资产表格、右侧原位实时属性检查器。
* **极速原位建档与编辑**：实时登记设备别名、成色状态、购入渠道（如闲鱼、eBay）、真实买入价格与实体机身序列号。
* **藏品数据健康体检**：专属数据体检中心，一键排查全馆缺失估值、未填序列号、缺少规格详情的设备条目。
* **纯键盘高效流**：空格键原生快速预览（QuickLook）、上下左右光标无缝穿梭、批量多选分类归档。

### 🔋 3. 电池生命周期与季度防饿死巡检
* **防过放休眠巡检**：针对长期保存的锂电池设备（如各代 iPod、旧 iPhone），根据上一次补电维护日期自动计算季度巡检周期，发出补电防鼓包预警。
* **在用主力机自动豁免**：高频使用的日常主力设备可一键标记“在用”，自动从防饿死巡查列表中豁免。
* **动态维护周期学习**：根据历史电池健康状态自适应调整巡检天数。
* **复古与损坏设备无感免除**：针对无电池交流电老设备或不开机摆件，支持一键停止电池跟踪，保持仪表盘清爽。

### 📄 4. 策展人画册与资产估值 PDF 报告
* **原生 CoreGraphics + CoreText 双底层渲染**：不依赖任何 WebView，极速导出符合 A4 标准的高分辨率印刷级图文画册。
* **资产估值统计胶囊**：自动计算馆藏总市值、计价藏品占比及各硬件品类资产分布。
* **专业级单品档案排版**：包含高清硬件定妆照、序列号、地区版本、电池状态及策展人私人备注。

### ☁️ 5. 基于 iCloud Drive 的去中心化金库同步
* **零第三方服务器、完全隐私**：无需注册账号，无需商业云服务，数据金库（`PommeSync_Vault.json`）直存于您个人的私有 iCloud Drive 文件夹。
* **双向增量合并引擎**：支持 Mac、iPhone 与 Apple Watch 之间的双向增量合并、修改时间戳裁决及墓碑机制（Tombstones），防止意外复活已删除硬件。

### ⌚ 6. Apple Watch 手表端与锁屏小组件
* **手腕上的随身展馆**：在 Apple Watch 上直接浏览最新馆藏、重点收藏设备，并随时接收腕上补电维护提醒。

---

## 📥 下载与安装

### 方式 A：直接下载 macOS 封装版安装包（推荐）
请前往 **[Releases 页面](https://github.com/DavidC0419/Pomme/releases)** 下载最新的独立安装镜像 `Pomme.dmg`：
1. 双击打开 `Pomme.dmg`；
2. 将 **Pomme** 拖移到「应用程序（Applications）」文件夹；
3. 打开 Pomme，即可通过内置的 6 件经典示例设备体验全部功能；
4. 熟悉操作后，随时点击右上角「清空示例」按钮，即可拥有纯净空白展馆并开始录入您的个人设备。

> **首次打开提示**：由于此版本采用公开发布沙盒签名，未签署昂贵的企业分发证书，若 macOS 弹出「无法验证开发者」或「已阻止」提示：只需在应用程序中右键点击 `Pomme.app` 选择**「打开」**，或在「系统设置」->「隐私与安全性」底部点击**「仍要打开」**即可。

### 方式 B：从源码编译构建
运行环境要求：macOS 14.6+ 及 Xcode 16.0+

```bash
# 克隆代码仓库
git clone https://github.com/DavidC0419/Pomme.git
cd Pomme

# 在 Xcode 中打开工程
open Pomme.xcodeproj
```
在 Xcode 顶部选择 **Pomme** Scheme 及目标设备（Mac、iPhone 或 Apple Watch），按 **⌘R** 即可一键编译运行。

---

## 🔒 隐私与本地优先设计哲学

* **100% 本地优先**：不收集任何用户隐私，无任何追踪或数据统计 SDK，无任何广告。
* **完全离线可用**：所有百科数据、藏品元数据全部驻留在本地，断网状态下所有功能完整可用。
* **数据归属自主**：支持随时一键将馆藏完整导出为 CSV 与 JSON。

---

## 🛠 技术架构

* **编程语言**：Swift 5.9+
* **UI 框架**：SwiftUI、AppKit (macOS)、UIKit (iOS)、WatchKit (watchOS)、RealityKit
* **排版与图形**：CoreGraphics、CoreText、PDFKit
* **同步机制**：Security-Scoped Bookmarks、iCloud Drive 去中心化文件协议

---

## 📄 开源许可证

本项目基于 [MIT 开源许可证](LICENSE) 发布。
