import SwiftUI
import UIKit
import CarCore

/// 我的页：只保留与控车直接相关的项 —— 12 款 3D 车模切换、网站授权信息、
/// 车辆位置、退出登录。俱乐部 / 主题 / 壁纸 / 行程 / 公告等非控车功能全部舍弃。
struct CakocheSettingsPage: View {
    @ObservedObject var control: CakocheControl
    @Binding var selectedID: String
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    DotMatrixText(text: "MY", size: 20, color: Mono.paperInk)
                    Text("车辆 / 车型 / 授权")
                        .font(.system(size: 11))
                        .foregroundStyle(Mono.paperDim)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 10)

                section("MODEL", "3D 车模 · 全系 12 款（含真实座舱）")
                ForEach(CakocheModels.all) { model in
                    Button {
                        selectedID = model.id
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Mono.paperInk)
                                Text(model.group + " · " + model.id.uppercased())
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(Mono.paperDim)
                            }
                            Spacer()
                            if selectedID == model.id {
                                Circle().fill(Mono.red).frame(width: 7, height: 7)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(selectedID == model.id
                                    ? Mono.paperHair.opacity(0.35) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.name)
                    .accessibilityAddTraits(selectedID == model.id ? [.isSelected] : [])
                    Hairline(color: Mono.paperHair).padding(.leading, 22)
                }

                section("ACCOUNT", "网站授权")
                VStack(alignment: .leading, spacing: 11) {
                    keyRow("PHONE", maskedPhone)
                    keyRow("AUTH", "已授权 · 白名单")
                    keyRow("SERVER", hostText)
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)

                section("VEHICLE", "车辆")
                Button { openMap() } label: {
                    HStack {
                        Text("在地图中查看车辆位置")
                            .font(.system(size: 13))
                            .foregroundStyle(Mono.paperInk)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Mono.paperDim)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("在地图中查看车辆位置")
                Hairline(color: Mono.paperHair).padding(.leading, 22)

                Button { appState.logout() } label: {
                    HStack {
                        DotMatrixText(text: "SIGN OUT", size: 10, color: Mono.red)
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("退出登录")

                Text("CAKOCHE 1.0.0 · 与网站同一套白名单授权体系")
                    .font(.system(size: 10))
                    .foregroundStyle(Mono.paperDim)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func section(_ en: String, _ cn: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            DotMatrixText(text: en, size: 9, color: Mono.paperDim)
            Text(cn).font(.system(size: 10)).foregroundStyle(Mono.paperDim)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private func keyRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            DotMatrixText(text: key, size: 8, color: Mono.paperDim)
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Mono.paperInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
        }
    }

    private var maskedPhone: String {
        guard let phone = appState.credentials?.phone, phone.count == 11 else { return "--" }
        return String(phone.prefix(3)) + "****" + String(phone.suffix(4))
    }

    private var hostText: String {
        URL(string: APIConfig.siteBaseURL)?.host ?? APIConfig.siteBaseURL
    }

    private func openMap() {
        guard let location = appState.status?.location else { return }
        let lat = location.latitude
        let lon = location.longitude
        let scheme = "iosamap://viewMap?sourceApplication=CAKOCHE&lat=\(lat)&lon=\(lon)&dev=0"
        if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let web = URL(string: "https://uri.amap.com/marker?position=\(lon),\(lat)") {
            UIApplication.shared.open(web)
        }
    }
}
