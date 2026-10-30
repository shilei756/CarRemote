//
//  CarModelGalleryView.swift
//  长安控车 — 3D 车模库
//
//  「我的爱车」App 提取的 12 款长安系 GLB 三维车模的浏览页。
//  拖拽逻辑参考「我的爱车」（OrbitControls 风格）：
//    - 拖拽旋转（横向转方位角 + 纵向转仰角）
//    - 双指捏合缩放
//    - 双击重置视角
//    - 俯视图按钮（0.8s 缓动切到车顶正上方）
//
//  车模为静态展示（仅查看旋转，无车门/车窗/灯光联动），
//  复用仪表盘 CarVisual3DStage 的舞台组件与轨道相机。
//

import SwiftUI
import CarCore

/// 3D 车模库浏览页（我的 → 3D 车模库）
struct CarModelGalleryView: View {
    /// 车模库全部车型（按代号排序展示）
    private static let catalogStyles: [CarModelStyle] = CarModelStyle.allCases.filter { $0.isCatalogModel }

    @State private var selected: CarModelStyle = .c211
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
                Text("共 \(Self.catalogStyles.count) 款 · 来自「我的爱车」")
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
                                Image(systemName: "view.3d")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(selected == style ? WebTheme.blue : WebTheme.muted)
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
                doorsAndWindows: CarStatus.DoorsAndWindows(),   // 静态展示，无车况联动
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
            Text("以下车模提取自「我的爱车」App 的三维展厅资产，共 \(Self.catalogStyles.count) 款长安系车型。")
                .font(.system(size: 11.5))
                .foregroundStyle(WebTheme.muted)
            Text("拖拽旋转（横+纵）· 双指捏合缩放 · 双击复位视角 · 点「俯视图」缓动切到车顶视角。车模为静态展示，不与实车车况联动。")
                .font(.system(size: 11.5))
                .foregroundStyle(WebTheme.muted)
            Text("部分车型中文名暂未收录，先以代号（如 C236、S202）展示。")
                .font(.system(size: 10.5))
                .foregroundStyle(WebTheme.faint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }
}
