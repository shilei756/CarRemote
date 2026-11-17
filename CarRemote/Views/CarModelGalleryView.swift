//
//  CarModelGalleryView.swift
//  长安控车 — 3D 车模库（1.11.4：全系 14 款）
//
//  「我的爱车」/岁岁长安提取的官方 GLB 三维车模浏览页，全部 14 款内置车模可选。
//  拖拽旋转（横+纵）· 双指捏合缩放 · 双击重置 · 俯视图按钮。
//  车模带官方铰链枢轴，长按车门/尾门/天窗可开合预览；车灯保持熄灭。
//

import SwiftUI
import CarCore

/// 3D 车模库浏览页（我的 → 3D 车模库）
struct CarModelGalleryView: View {
    /// 全部 14 款官方 GLB 车模
    private static let catalog = FormalCarModels.all

    @State private var selectedID: String = FormalCarModels.selectedID
    /// 当前选择的车模换挡时强制重建舞台
    @State private var stageGeneration = 0

    private var selected: FormalCarModel {
        FormalCarModels.all.first { $0.id == selectedID } ?? FormalCarModels.all[0]
    }

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

    // MARK: - 车型选择（横滑胶囊，只显示车名）

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("选择车模")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                Spacer()
                Text("共 \(Self.catalog.count) 款 · 全部内置资产")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WebTheme.faint)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.catalog, id: \.id) { model in
                        Button {
                            guard selectedID != model.id else { return }
                            selectedID = model.id
                            FormalCarModels.selectedID = model.id
                            stageGeneration += 1
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 3) {
                                Text(model.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WebTheme.txt)
                                    .lineLimit(1)
                                Text(model.group)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(WebTheme.faint)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selectedID == model.id ? WebTheme.blue.opacity(0.09) : WebTheme.card2.opacity(0.7))
                            .overlay(
                                Capsule().strokeBorder(selectedID == model.id ? WebTheme.blue : WebTheme.border,
                                                       lineWidth: selectedID == model.id ? 1.5 : 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看\(model.name)三维车模")
                        .accessibilityAddTraits(selectedID == model.id ? [.isSelected] : [])
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

    // MARK: - 3D 舞台（用 modelOverride 直接加载选中的 GLB）

    private var stageCard: some View {
        VStack(spacing: 0) {
            CarVisual3DStage(
                style: .yidong,
                doorsAndWindows: CarStatus.DoorsAndWindows(),
                vehicleStarted: false,
                wheelsRolling: false,
                modelOverride: selected.model3DName
            )
            .padding(.horizontal, 0)
            .id(stageGeneration)
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
            Text("本 App 内置的 14 款官方三维车模，与「我的爱车」同源，均为带内饰的真 3D 模型。")
                .font(.system(size: 11.5))
                .foregroundStyle(WebTheme.muted)
            Text("拖拽旋转（横+纵）· 双指捏合缩放 · 双击复位视角 · 点「俯视图」切到车顶 · 长按车门/尾门/天窗可开合预览。车灯保持熄灭。")
                .font(.system(size: 11.5))
                .foregroundStyle(WebTheme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16)
    }
}
