# Pomme 🍎

<p align="center">
  <strong>The Definitive Apple Hardware Digital Museum & Curator Asset Workbench</strong>
</p>

<p align="center">
  <a href="README_zh.md"><strong>🇨🇳 简体中文</strong></a> | 
  <a href="README.md"><strong>🇺🇸 English</strong></a>
</p>

<p align="center">
  <img src="pomme-app-icon-1024-circle.png" alt="Pomme Icon" width="128" height="128">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20watchOS%20%7C%20visionOS-black?style=flat-square&logo=apple" alt="Platforms">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0071e3?style=flat-square" alt="SwiftUI">
  <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="License">
</p>

---

## 🌟 Overview

**Pomme** is an Apple-grade, native multi-platform digital archive, encyclopedia, and asset management workbench designed for Apple hardware enthusiasts, archivists, and curators. 

Whether you collect vintage Macintosh computers, classic click-wheel iPods, developer prototypes, or daily driver modern Silicon devices, Pomme provides a private, offline-first home for your collection.

---

## ✨ Key Features

### 🏛️ 1. Comprehensive Apple Hardware Encyclopedia
* **Decades of Apple History**: Rich, categorized encyclopedia spanning Vintage Macs, modern Apple Silicon laptops & desktops, iPhones, iPads, iPods, Apple Watch, AirPods, Displays, AirTags, and accessories/cables.
* **Accurate Tech Specs**: Models, internal identifiers (e.g. `Macmini2,1`, `A1296`), release years, official finishes, original MSRPs, processor architectures, and memory/storage configurations.
* **Search & Filter**: Instant hierarchical category filtering, full-text fuzzy searching, and interactive category covers.

### 📊 2. Mac Curator Workbench
* **Three-Pane Desktop Productivity**: Left sidebar navigation, central interactive grid / table views, and right real-time inspector.
* **Fast In-Place Editing**: Edit custom names, condition notes, acquisition sources (e.g. eBay, Xianyu), actual purchase prices, and physical serial numbers on the fly.
* **Hardware Health Checkup**: Dedicated data health audit dashboard highlighting missing prices, empty serial numbers, or incomplete specs across your archive.
* **Full Keyboard Workflow**: Spacebar QuickLook preview, Arrow navigation, and batch operations.

### 🔋 3. Battery Health & Quarterly Maintenance System
* **Anti-Starvation Inspection**: Automatically flags preserved battery-powered devices that need quarterly re-charging to prevent lithium battery starvation and swelling.
* **Daily Driver Exemption**: Mark your everyday devices as "In Use" to automatically exempt them from archival maintenance cycles.
* **Dynamic Cycle Tracking**: Intelligently tunes recharge frequency based on historical health and battery chemistry.
* **Vintage & Untracked Support**: One-tap toggling to ignore battery alerts for AC-powered vintage machines or damaged shelf display units.

### 📄 4. High-Resolution Artbook & Valuation PDF Dossier
* **Native CoreGraphics & CoreText Engine**: Exports pixel-perfect, print-ready multi-page A4 PDF dossiers (zero webview rendering, crystal-clear typography).
* **Asset Valuation Summary**: Calculates total collection monetary valuation, priced item ratios, and categorical asset distribution.
* **Individual Hardware Dossier**: Includes high-resolution imagery, serial numbers, region models, battery state, and curator acquisition notes.

### ☁️ 5. Decentralized iCloud Drive Vault Sync
* **Zero Third-Party Servers**: No subscription fees, no proprietary cloud databases. Your vault data (`PommeSync_Vault.json`) lives strictly in your personal iCloud Drive folder.
* **Cross-Device Merge Engine**: Seamless two-way merging, conflict resolution based on timestamps and maintenance logs, and tombstone deletion tracking across Mac, iPhone, and Apple Watch.

### ⌚ 6. Apple Watch & Lock Screen Widgets
* **Curator Wrist Companion**: View your collection highlights, favorite pieces, and upcoming battery maintenance alerts right on Apple Watch complications and Lock Screen widgets.

---

## 📥 Download & Installation

### Option A: Pre-built macOS Release (Recommended)
Download the standalone `.dmg` installer from the **[Releases](https://github.com/DavidC0419/Pomme/releases)** page:
1. Open `Pomme.dmg`.
2. Drag **Pomme** into your **Applications** folder.
3. Open Pomme and explore the built-in 6-device demonstration catalog.
4. When ready, click **Clear Samples** in the toolbar to begin adding your own hardware!

> **Gatekeeper Notice**: Since this build is signed with standard distribution sandbox entitlements, if macOS displays *"Unidentified Developer"*, simply right-click `Pomme.app` in Applications and choose **Open**, or allow it in *System Settings -> Privacy & Security*.

### Option B: Build from Source
Requirements: macOS 14.6+ and Xcode 16.0+

```bash
# Clone the repository
git clone https://github.com/DavidC0419/Pomme.git
cd Pomme

# Open in Xcode
open Pomme.xcodeproj
```
Select the **Pomme** scheme and target destination (Mac, iPhone, or Apple Watch) and press **⌘R** to build and run.

---

## 🔒 Privacy & Local-First Philosophy

* **100% Local & Private**: No analytics, no tracking SDKs, no ad frameworks.
* **Offline Capable**: All encyclopedia data and your collection records reside locally on your device.
* **Your Data Stays Yours**: Easy one-click CSV & JSON export at any time.

---

## 🛠 Tech Stack

* **Language**: Swift 5.9+
* **Frameworks**: SwiftUI, AppKit (macOS), UIKit (iOS), WatchKit (watchOS), RealityKit
* **Graphics & Typography**: CoreGraphics, CoreText, PDFKit
* **Sync Architecture**: Security-Scoped Bookmarks, iCloud Drive Decentralized Vault

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
