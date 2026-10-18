//
//  SpatialMuseumImmersiveView.swift
//  Pomme
//
//  Vision Pro 混合现实沉浸空间 (Mixed Immersion Physical Placement Space)
//  让 Apple 硬件直接融入用户的物理真实房间（桌面、地面、架子），支持直接手势交互与漫步欣赏。
//

import SwiftUI
import RealityKit

#if os(visionOS)
struct SpatialMuseumImmersiveView: View {
    @State private var store = SpatialMuseumStore.shared

    var body: some View {
        SpatialRealityCanvasView(store: store)
    }
}
#endif
