//
//  LaunchSplashScreenView.swift
//  Pomme
//
//  App 动态启动与加载过渡界面 (Interactive Launch & Loading Splash Screen)
//  精美呼吸光环、圆形 Pomme 徽标、柔和淡出转场，兼顾 Vision Pro、iOS 与 macOS 极致质感。
//

import SwiftUI

struct LaunchSplashScreenView: View {
    @Binding var isPresented: Bool
    @State private var iconScale: CGFloat = 0.85
    @State private var iconOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    @State private var glowOpacity: Double = 0.3
    @State private var pulseAnimation: Bool = false

    var body: some View {
        ZStack {
            // 背景磨砂与深邃暗光渐变
            #if os(visionOS)
            Color.clear
                .background(.regularMaterial)
                .ignoresSafeArea()
            #elseif os(macOS)
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            #else
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            #endif

            // 柔和径向环境光晕
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.accentColor.opacity(0.18),
                    Color.accentColor.opacity(0.04),
                    Color.clear
                ]),
                center: .center,
                startRadius: 40,
                endRadius: 280
            )
            .scaleEffect(pulseAnimation ? 1.15 : 0.95)
            .opacity(glowOpacity)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // 圆形 App 图标与光环
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 136, height: 136)
                        .scaleEffect(pulseAnimation ? 1.08 : 0.96)
                        .blur(radius: 12)

                    Image("pomme-app-icon-1024")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 108, height: 108)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 8)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                // 标题与副标题
                VStack(spacing: 6) {
                    Text("Pomme")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Apple Collection & Spatial Museum")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                }
                .opacity(textOpacity)

                Spacer()

                // 底部微型加载指示器
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading Museum Assets…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 48)
                .opacity(textOpacity)
            }
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissSplash()
        }
        .onAppear {
            // 动效入场序列
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.5).delay(0.2)) {
                textOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulseAnimation = true
                glowOpacity = 0.5
            }

            // 1.2 秒后平滑淡出过渡至主界面
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                dismissSplash()
            }
        }
    }

    private func dismissSplash() {
        withAnimation(.easeOut(duration: 0.45)) {
            isPresented = false
        }
    }
}
