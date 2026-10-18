//
//  MacWorkbenchColors.swift
//  Pomme
//
//  Mac Curator Workbench 专属主题色调支持
//

import SwiftUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

var macCanvasColor: Color {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    return Color(NSColor.windowBackgroundColor)
    #elseif canImport(UIKit)
    return Color(UIColor.systemGroupedBackground)
    #else
    return Color(red: 0.965, green: 0.966, blue: 0.975)
    #endif
}

var macGroupedBackground: Color {
    macCanvasColor
}

var macCardBackground: Color {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    return Color(NSColor.controlBackgroundColor)
    #elseif canImport(UIKit)
    return Color(UIColor.secondarySystemGroupedBackground)
    #else
    return Color.white
    #endif
}
