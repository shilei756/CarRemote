//
//  CarModelGalleryView.swift
//  长安控车 — 3D 车模库
//
//  「我的爱车」App 提取的官方 GLB 三维车模浏览页（能对应现有 2D 车型的全部接入）。
//  拖拽逻辑参考「我的爱车」（OrbitControls 风格）：
//    - 拖拽旋转（横向转方位角 + 纵向转仰角）
//    - 双指捏合缩放
//    - 双击重置视角
//    - 俯视图按钮（0.8s 缓动切到车顶正上方）
//
//  车模带官方铰链枢轴：长按车门/尾门/天窗可开合预览；车灯保持熄灭。
//  复用仪表盘 CarVisual3DStage 的舞台组件与轨道相机。
//

import SwiftUI
import CarCore

/// 3D 车模库浏览页（我的 → 3D 车模库）
struct CarModelGalleryView: View {
    /// 全部带 3D 车模的车型（.rk 全件模 + 「我的爱车」GLB 官方模）
    private static let catalogStyles: [CarModelStyle] = CarModelStyle.allCases.filter { $0.has3DModel }

    @State private var selected: CarModelStyle = .yidong
    /// 当前选择的车型换挡时强制重建舞台（Stage 内部 StateObject 随 identity 变化重建）
    @State private var stageGeneration = 0

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        modelPicker
                        stageCard
                        infoCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("3D 车模库")
            .navigationBarTitleDisplayMode(.large)
        }
        .tint(WebTheme.blue)
    }

    // MARK: - 车型选择（横滑胶囊）

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("选择车模")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                Spacer()
                Text("共 \(Self.catalogStyles.count) 款 · 本 App 内置资产")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WebTheme.faint)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.catalogStyles, id: \.self) { style in
                        Button {
                            guard selected != style else { return }
                            selected = style
                            stageGeneration += 1
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 4) {
                                Image(style.sideImageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 20)
                                Text(style.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WebTheme.txt)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selected == style ? WebTheme.blue.opacity(0.09) : WebTheme.card2.opacity(0.7))
                            .overlay(
                                Capsule().strokeBorder(selected == style ? WebTheme.blue : WebTheme.border,
                                                       lineWidth: selected == style ? 1.5 : 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看\(style.displayName)三维车模")
                        .accessibilityAddTraits(selected == style ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }

    // MARK: - 3D 舞台

    private var stageCard: some View {
        VStack(spacing: 0) {
            CarVisual3DStage(
                style: selected,
                doorsAndWindows: CarStatus.DoorsAndWindows(),   // 车况默认全关；长按部件可预览开合
                vehicleStarted: false,
                wheelsRolling: false
            )
            .padding(.horizontal, 0)
            .id(stageGeneration)   // 换车型时整体重建（含 StateObject 与 3D 加载）
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 16)
    }

    // MARK: - 说明

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("车模说明", systemImage: "info.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WebTheme.txt)
            Text("本 App 内置的官方三维车模资产，与「切换车型」共用同一套模型。")
                .font(.system(size: 11.5))
                .foregroundStyle(WebTheme.muted)
            Text("拖拽旋转（横+纵）· 双指捏合缩放 · 双击复位视角 · 点「俯视图」缓动切到车顶视角 · 长按车门/尾门/天窗可开合预览。车灯保持熄灭。")
                .font(.system(size: 11.5))
                .foregroundStyle(WebTheme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }
}
