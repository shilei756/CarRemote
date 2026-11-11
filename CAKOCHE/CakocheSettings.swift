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
                    Text("我的")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(6)
                        .foregroundStyle(Mono.paperInk)
                    Text("车辆 / 车型 / 授权")
                        .font(.system(size: 11))
                        .foregroundStyle(Mono.paperDim)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 10)

                section("3D 车模", "全系 12 款（含真实座舱），点按切换")
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

                section("账号授权", "手机号与控车码由站主网站校验")
                VStack(alignment: .leading, spacing: 11) {
                    keyRow("手机号", maskedPhone)
                    keyRow("授权状态", "已授权 · 白名单")
                    keyRow("授权站点", hostText)
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)

                section("车辆", "位置与退出")
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
                        Text("退出登录")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(Mono.red)
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("退出登录")

                Text("CAKOCHE 1.1.0 · 与网站同一套白名单授权体系")
                    .font(.system(size: 10))
                    .foregroundStyle(Mono.paperDim)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func section(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .tracking(3)
                .foregroundStyle(Mono.paperInk)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Mono.paperDim)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private func keyRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Mono.paperDim)
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
