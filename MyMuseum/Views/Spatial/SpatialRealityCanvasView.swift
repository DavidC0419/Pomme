//
//  SpatialRealityCanvasView.swift
//  Pomme
//
//  RealityKit 空间 3D 画布与实体交互视图 (RealityKit Spatial 3D Canvas & Gesture Manipulator)
//  支持原生 1:1 真机尺寸、自然手势平移 (1:1 Hand Tracking)、双指缩放、旋转与微型磨砂底托。
//

import SwiftUI
import RealityKit
import simd

#if os(visionOS)
struct SpatialRealityCanvasView: View {
    @Bindable var store: SpatialMuseumStore
    
    // 手势交互中的中间拖拽/旋转/缩放状态
    @State private var draggingDeviceID: UUID?
    @State private var dragInitialPosition: SIMD3<Float> = .zero
    @State private var rotatingDeviceID: UUID?
    @State private var rotateInitialRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var magnifyingDeviceID: UUID?
    @State private var magnifyInitialScale: Float = 1.0

    var body: some View {
        RealityView { content, attachments in
            // 建立空间根锚点
            let root = Entity()
            root.name = "MuseumRoot"

            // 1. 展厅级摄影棚主聚光灯与柔和补光（visionOS 2.0+ 原生高光渲染）
            if #available(visionOS 2.0, *) {
                let keyLightEntity = Entity()
                var dirLight = DirectionalLightComponent()
                dirLight.intensity = 3500
                dirLight.color = .white
                keyLightEntity.components.set(dirLight)
                keyLightEntity.look(at: [0, 1.0, -0.8], from: [0.6, 2.4, 0.2], relativeTo: nil)
                root.addChild(keyLightEntity)

                let fillLightEntity = Entity()
                var fillLight = PointLightComponent()
                fillLight.intensity = 4000
                fillLight.color = UIColor(white: 0.95, alpha: 1.0)
                fillLightEntity.components.set(fillLight)
                fillLightEntity.position = [0, 1.6, 0]
                root.addChild(fillLightEntity)
            }

            content.add(root)
        } update: { content, attachments in
            guard let root = content.entities.first(where: { $0.name == "MuseumRoot" }) else { return }

            let currentIDs = Set(store.placedDevices.map { $0.id.uuidString })
            
            // 移除已不在列表中的实体与悬浮标牌（保留灯光）
            for child in root.children {
                if child.name.starts(with: "Light") || child.name == "keyLight" || child.name == "fillLight" {
                    continue
                }
                let baseUUID = child.name.replacingOccurrences(of: "_badge", with: "")
                if let uuid = UUID(uuidString: baseUUID), !currentIDs.contains(uuid.uuidString) {
                    root.removeChild(child)
                }
            }

            // 更新或加载新摆放的设备与悬浮标牌
            for placed in store.placedDevices {
                let entityName = placed.id.uuidString
                if let existing = root.findEntity(named: entityName) {
                    existing.position = placed.position
                    existing.orientation = placed.rotation
                    existing.scale = SIMD3<Float>(repeating: placed.scale)

                    // 更新展示台底盘可见性（全局开关与单机独立开关联动）
                    if let pedestal = existing.findEntity(named: "\(entityName)_pedestal") {
                        pedestal.isEnabled = store.showMuseumPedestals && placed.showPedestal
                    }
                } else {
                    loadEntity(for: placed, into: root, attachments: attachments)
                }

                // 悬浮玻璃标牌：挂在世界坐标系根节点，锁定在模型顶部正上方，始终正面朝向用户视线（Billboard）
                if let badgeEntity = root.findEntity(named: "\(entityName)_badge") {
                    badgeEntity.isEnabled = store.showAllBadges
                    if store.showAllBadges {
                        let topY = placed.position.y + (placed.boundingHeight * placed.scale) + 0.08
                        badgeEntity.position = SIMD3<Float>(placed.position.x, topY, placed.position.z)
                        if #available(visionOS 2.0, *) {
                            if badgeEntity.components[BillboardComponent.self] == nil {
                                badgeEntity.components.set(BillboardComponent())
                            }
                        }
                    }
                }
            }
        } attachments: {
            // 为每台设备挂载浮空玻璃标牌
            ForEach(store.placedDevices) { placed in
                Attachment(id: placed.id) {
                    SpatialDeviceBadgeView(
                        device: placed,
                        onDelete: {
                            store.remove(id: placed.id)
                        },
                        onReset: {
                            store.resetToDesk(device: placed)
                        },
                        onSelect: {
                            for d in store.placedDevices { d.isSelected = (d.id == placed.id) }
                            store.selectedDeviceID = placed.id
                        }
                    )
                }
            }
        }
        // 空间 3D 拖拽手势：支持完全锁定与 Y 轴防漂移锁定
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let (device, _) = targetDevice(for: value.entity) else { return }

                    // 完全锁定：单机锁定或全局总锁激活时，绝对禁止任何位移拖动
                    if device.isLocked || store.isAllLocked {
                        return
                    }

                    // 若正在执行双手捏合缩放 Apple Park，则暂不位移，防止缩放时带偏位置
                    if magnifyingDeviceID != nil {
                        return
                    }

                    if draggingDeviceID != device.id {
                        draggingDeviceID = device.id
                        dragInitialPosition = device.position
                    }

                    // 核心关键：从手势稳定的绝对坐标空间（.global）换算为场景坐标空间（.scene）
                    let startInScene = value.convert(value.startLocation3D, from: .global, to: .scene)
                    let currentInScene = value.convert(value.location3D, from: .global, to: .scene)
                    let delta = currentInScene - startInScene

                    // Y 轴防漂移锁定：优先遵循单设备独立锁定状态，同时支持全局锁定
                    let shouldLockY = device.isYAxisLocked || store.isYAxisLocked
                    let newY: Float = shouldLockY
                        ? dragInitialPosition.y
                        : max(0.35, min(1.60, dragInitialPosition.y + Float(delta.y)))

                    var newPos = SIMD3<Float>(
                        max(-1.60, min(1.60, dragInitialPosition.x + Float(delta.x))),
                        newY,
                        max(-2.20, min(-0.35, dragInitialPosition.z + Float(delta.z)))
                    )

                    device.position = newPos
                }
                .onEnded { _ in
                    draggingDeviceID = nil
                }
        )
        // 空间双指全 3D 旋转手势：支持完全锁定与上下俯仰 (Pitch)、水平左右 (Yaw) 全自由度旋转
        .gesture(
            RotateGesture3D()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let (device, _) = targetDevice(for: value.entity) else { return }

                    // 完全锁定：单机锁定或全局总锁激活时，绝对禁止任何手势扭动与旋转
                    if device.isLocked || store.isAllLocked {
                        return
                    }

                    if rotatingDeviceID != device.id {
                        rotatingDeviceID = device.id
                        rotateInitialRotation = device.rotation
                    }

                    let axisX: Double = value.rotation.axis.x
                    let axisY: Double = value.rotation.axis.y
                    let axisZ: Double = value.rotation.axis.z
                    let lenSq: Double = axisX * axisX + axisY * axisY + axisZ * axisZ
                    if lenSq > 0.00001 {
                        let norm: Float = Float(sqrt(lenSq))
                        let axis = SIMD3<Float>(Float(axisX) / norm, Float(axisY) / norm, Float(axisZ) / norm)
                        let angle = Float(value.rotation.angle.radians)
                        let rotDelta = simd_quatf(angle: angle, axis: axis)
                        device.rotation = simd_mul(rotDelta, rotateInitialRotation)
                    }
                }
                .onEnded { _ in
                    rotatingDeviceID = nil
                }
        )
        // 空间双手同时捏合缩放手势（SimultaneousGesture）：专为 Apple Park 打造，不与单手平移冲突
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let (device, _) = targetDevice(for: value.entity) else { return }

                    // 完全锁定：单机锁定或全局总锁激活时，禁止双手缩放
                    if device.isLocked || store.isAllLocked {
                        return
                    }

                    let isApplePark = device.modelItem.fileName.contains("APPLE_PARK") || device.modelItem.fileName.contains("apple_park")
                    guard isApplePark else { return }

                    if magnifyingDeviceID != device.id {
                        magnifyingDeviceID = device.id
                        magnifyInitialScale = device.scale
                    }

                    let newScale = magnifyInitialScale * Float(value.magnification)
                    device.scale = max(0.05, min(25.0, newScale))
                }
                .onEnded { _ in
                    magnifyingDeviceID = nil
                }
        )
    }

    /// 从被触控的手势实体沿层级向上搜寻对应的设备 ID 与容器实体
    private func targetDevice(for entity: Entity) -> (PlacedSpatialDevice, Entity)? {
        var current: Entity? = entity
        while let c = current {
            if let uuid = UUID(uuidString: c.name),
               let device = store.placedDevices.first(where: { $0.id == uuid }) {
                return (device, c)
            }
            let baseName = c.name.components(separatedBy: "_").first ?? ""
            if let uuid = UUID(uuidString: baseName),
               let device = store.placedDevices.first(where: { $0.id == uuid }) {
                return (device, c)
            }
            current = c.parent
        }
        return nil
    }

    /// 递归为实体及其子实体挂载交互与原生注视高光组件
    private func setupInteraction(for entity: Entity) {
        entity.components.set(InputTargetComponent())
        entity.components.set(HoverEffectComponent())
        for child in entity.children {
            setupInteraction(for: child)
        }
    }

    /// 异步加载 USDZ 模型并计算贴地与微型比例
    private func loadEntity(for placed: PlacedSpatialDevice, into parent: Entity, attachments: RealityViewAttachments) {
        guard let url = placed.modelItem.resolvedURL else {
            print("❌ Cannot resolve model URL for: \(placed.modelItem.fileName)")
            return
        }

        let container = Entity()
        container.name = placed.id.uuidString
        container.position = placed.position
        container.orientation = placed.rotation
        container.scale = SIMD3<Float>(repeating: placed.scale)
        parent.addChild(container)

        Task {
            do {
                let modelEntity = try await Entity(contentsOf: url)
                modelEntity.name = "\(placed.id.uuidString)_model"

                let isApplePark = placed.modelItem.fileName.contains("APPLE_PARK") || placed.modelItem.fileName.contains("apple_park")
                if isApplePark {
                    // Apple Park 园区建筑模型等比例自适应缩放：
                    // 让初始桌面占地面积等于 Mac Pro Tower (A2786/A1991 模具，跨度约 0.45 米)
                    let parkBounds = modelEntity.visualBounds(relativeTo: nil)
                    let maxGround = max(parkBounds.extents.x, parkBounds.extents.z)
                    if maxGround > 0.001 {
                        let targetFootprint: Float = 0.45
                        modelEntity.scale *= (targetFootprint / maxGround)
                    }
                } else {
                    let rawBounds = modelEntity.visualBounds(relativeTo: nil)
                    let maxRaw = max(rawBounds.extents.x, max(rawBounds.extents.y, rawBounds.extents.z))
                    if maxRaw > 1.2 {
                        modelEntity.scale *= 0.01
                    }
                }

                // 真实物理世界包围盒
                let bounds = modelEntity.visualBounds(relativeTo: nil)
                let extents = bounds.extents

                // 将设备底面贴合 y=0（放置在桌面或展台上）
                let bottomOffset: Float = -bounds.min.y
                let centerXOffset: Float = -bounds.center.x
                let centerZOffset: Float = -bounds.center.z
                modelEntity.position = SIMD3<Float>(centerXOffset, bottomOffset, centerZOffset)

                // 记录模型真实尺寸高度，用于计算世界空间悬浮标牌位置
                placed.boundingHeight = max(0.08, extents.y)

                // 递归为整个模型及其所有子节点添加输入与注视高光
                modelEntity.generateCollisionShapes(recursive: true)
                setupInteraction(for: modelEntity)
                container.addChild(modelEntity)

                // 挂载微型精致 Apple 磨砂亚克力微光展台底盘
                let pedestal = createMuseumPedestal(for: extents)
                pedestal.name = "\(placed.id.uuidString)_pedestal"
                pedestal.isEnabled = store.showMuseumPedestals && placed.showPedestal
                let maxDim = max(extents.x, extents.z)
                let pedRadius = max(0.035, min(0.35, maxDim * 0.55))
                pedestal.components.set(CollisionComponent(shapes: [.generateBox(size: [pedRadius * 2, 0.012, pedRadius * 2])]))
                pedestal.components.set(InputTargetComponent())
                pedestal.components.set(HoverEffectComponent())
                container.addChild(pedestal)

                // 设立整个 container 的外层宽松碰撞盒，确保无论是捏机身、捏屏幕还是捏底座都能 100% 灵敏响应
                let grabBoxSize = max(extents, SIMD3<Float>(0.08, 0.08, 0.08)) * 1.15
                container.components.set(CollisionComponent(
                    shapes: [.generateBox(size: grabBoxSize).offsetBy(translation: [0, extents.y / 2.0, 0])],
                    isStatic: false
                ))
                container.components.set(InputTargetComponent())
                container.components.set(HoverEffectComponent())

                // 挂载悬浮玻璃标牌：直接挂载在世界空间根节点 parent (MuseumRoot)，锁定在真机顶部正上方，永不随模型角度倾斜翻滚
                if let attachment = attachments.entity(for: placed.id) {
                    attachment.name = "\(placed.id.uuidString)_badge"
                    let topY = placed.position.y + (extents.y * placed.scale) + 0.08
                    attachment.position = SIMD3<Float>(placed.position.x, topY, placed.position.z)
                    if #available(visionOS 2.0, *) {
                        attachment.components.set(BillboardComponent())
                    }
                    attachment.isEnabled = store.showAllBadges
                    parent.addChild(attachment)
                }
            } catch {
                print("❌ Failed to load USDZ entity from \(url): \(error)")
            }
        }
    }

    /// 生成与设备真实真机尺寸精确匹配的 Apple 风格磨砂微光底盘
    private func createMuseumPedestal(for extents: SIMD3<Float>) -> Entity {
        let maxDim = max(extents.x, extents.z)
        let radius = max(0.035, min(0.35, maxDim * 0.55))
        let height: Float = 0.006 // 6 毫米超薄极简亚克力微光底托
        let mesh = MeshResource.generateCylinder(height: height, radius: radius)

        var material = SimpleMaterial()
        material.color = .init(tint: UIColor(white: 0.98, alpha: 0.7), texture: nil)
        material.roughness = 0.3
        material.metallic = 0.05

        let pedestalEntity = ModelEntity(mesh: mesh, materials: [material])
        pedestalEntity.position = SIMD3<Float>(0, -height / 2.0, 0)
        return pedestalEntity
    }
}

// MARK: - 空间悬浮玻璃信息牌（支持独立折叠/展开与固定朝向）
struct SpatialDeviceBadgeView: View {
    let device: PlacedSpatialDevice
    var onDelete: () -> Void
    var onReset: () -> Void
    var onSelect: () -> Void

    var body: some View {
        Group {
            if device.isCollapsed {
                // 极简微型静音眼球：只留带斜杠小眼睛与极细淡灰外框，不加名字，告别亮蓝色与文字干扰
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        device.toggleCollapsed()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                        Circle()
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        Image(systemName: "eye.slash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(white: 0.8))
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(10) // 确保在 RealityKit 空间 AttachmentEntity 贴图渲染中四周有充裕的安全边界，绝不裁边！
                .help("Expand Controls")
            } else {
                // 两行紧凑型控制卡片 (Two-row Compact Control Card)
                VStack(alignment: .leading, spacing: 6) {
                    // 第一行：设备品名与折叠/删除管理按钮 (Row 1: Title & Management Controls)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.modelItem.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                if let year = device.modelItem.year, !year.isEmpty {
                                    Text(year)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                if let color = device.modelItem.colorLabel {
                                    Text(color)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                if device.modelItem.fileName.contains("APPLE_PARK") || device.modelItem.fileName.contains("apple_park") {
                                    Text("Scalable")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.18), in: Capsule())
                                        .foregroundStyle(Color.green)
                                } else {
                                    Text("1:1")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }

                        Spacer(minLength: 6)

                        // 单机折叠眼球按钮 (Collapse to Mini Pill)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                device.toggleCollapsed()
                            }
                        } label: {
                            Image(systemName: "eye")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Collapse Controls to Mini Eye Pill")

                        // 删除按钮
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Remove Device")
                    }

                    Divider().opacity(0.3)

                    // 第二行：核心功能快捷按钮集 (Row 2: Action Toolset)
                    HStack(spacing: 6) {
                        // 1. 完全锁定开关 (Master Lock / Freeze Toggle - 彻底冻结手势)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                device.toggleLock()
                            }
                        } label: {
                            Image(systemName: device.isLocked ? "lock.fill" : "lock.open")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(device.isLocked ? Color.orange : .secondary)
                                .frame(width: 22, height: 22)
                                .background(device.isLocked ? Color.orange.opacity(0.2) : Color.primary.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help(device.isLocked ? "Device is locked (gestures frozen). Tap to unlock." : "Lock device to freeze gestures & prevent accidental moves")

                        // 2. 独立 Y 轴高度锁定开关 (Dedicated Y-Axis Height Lock - 默认不开启，开启后锁定桌面高度)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                device.toggleYAxisLock()
                            }
                        } label: {
                            Image(systemName: device.isYAxisLocked ? "arrow.up.and.down.slash" : "arrow.up.and.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(device.isYAxisLocked ? Color.accentColor : .secondary)
                                .frame(width: 22, height: 22)
                                .background(device.isYAxisLocked ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help(device.isYAxisLocked ? "Y-Axis height locked (flat desk drag). Tap to free 3D height." : "Y-Axis free in 3D. Tap to lock height on desk.")

                        // 3. 一键就地正面朝向当前 VP 视线快速回正 (Face Me In-Place)
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                device.faceUserInPlace()
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Face Me (Quick in-place reorient towards your view)")

                        // 4. 展台底座开关 (Stand Toggle)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                device.togglePedestal()
                            }
                        } label: {
                            Image(systemName: device.showPedestal ? "circle.inset.filled" : "circle")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(device.showPedestal ? Color.accentColor : .secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help(device.showPedestal ? "Hide Stand for this Device" : "Show Stand for this Device")

                        // 5. 3D 旋转、姿态与高度锁定菜单 (3D Menu)
                        Menu {
                            Section("Face & Axis") {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        device.faceUserInPlace()
                                    }
                                } label: {
                                    Label("Face Me in Place", systemImage: "arrow.triangle.2.circlepath")
                                }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        device.toggleYAxisLock()
                                    }
                                } label: {
                                    Label(
                                        device.isYAxisLocked ? "Unlock Height (Free 3D)" : "Lock Height (Desk Flat)",
                                        systemImage: device.isYAxisLocked ? "arrow.up.and.down.slash" : "arrow.up.and.down"
                                    )
                                }
                            }

                            Section("Pitch (Up / Down)") {
                                Button {
                                    withAnimation { device.tilt(degrees: 15) }
                                } label: {
                                    Label("Tilt Up (+15°)", systemImage: "arrow.up")
                                }
                                Button {
                                    withAnimation { device.tilt(degrees: -15) }
                                } label: {
                                    Label("Tilt Down (-15°)", systemImage: "arrow.down")
                                }
                            }

                            Section("Yaw (Left / Right)") {
                                Button {
                                    withAnimation { device.rotateYaw(degrees: 45) }
                                } label: {
                                    Label("Turn Right (+45°)", systemImage: "arrow.clockwise")
                                }
                                Button {
                                    withAnimation { device.rotateYaw(degrees: -45) }
                                } label: {
                                    Label("Turn Left (-45°)", systemImage: "arrow.counterclockwise")
                                }
                            }

                            Section {
                                Button {
                                    onReset()
                                } label: {
                                    Label("Reset to Desk Center", systemImage: "arrow.counterclockwise")
                                }
                            }
                        } label: {
                            Image(systemName: "rotate.3d")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("3D Tilt, Rotate & Axis Controls")

                        // Apple Park 专用快速缩放调节按钮
                        if device.modelItem.fileName.contains("APPLE_PARK") || device.modelItem.fileName.contains("apple_park") {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    device.scale = min(25.0, device.scale * 1.3)
                                }
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.green)
                                    .frame(width: 22, height: 22)
                                    .background(Color.green.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Zoom in Apple Park (+30%)")

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    device.scale = max(0.05, device.scale * 0.75)
                                }
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.green)
                                    .frame(width: 22, height: 22)
                                    .background(Color.green.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Zoom out Apple Park (-25%)")
                        }

                        if device.isLocked {
                            Spacer(minLength: 4)
                            Text("Locked")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 240)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(device.isSelected ? Color.accentColor : Color.white.opacity(0.2), lineWidth: device.isSelected ? 2 : 1)
                )
                .padding(8) // 避免边缘贴图裁切
                .onTapGesture {
                    onSelect()
                }
            }
        }
    }
}
#endif
