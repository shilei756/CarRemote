import Foundation

/// 使用量上报（与网页版一致：站主后台统计谁在用、用了多少次）。
/// App 启动和回到前台时调用；失败静默忽略，不影响主流程。
public enum UsageService {
    public static func beat(phone: String) async {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/usage/beat") else { return }
        _ = try? await APIClient.postJSON(url, json: ["phone": phone])
    }
}
