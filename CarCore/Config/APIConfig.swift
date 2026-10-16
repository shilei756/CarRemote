import Foundation

/// 全局接口配置。
///
/// 站点地址即站主自有的「长安控车系统」后端；
/// 车联网指令链路与官网 App 一致（长安车联网开放平台）。
public enum APIConfig {

    // MARK: - 站主自有后端

    /// 你的网站（提供登录 / 卡密 / 白名单 / 圈子 / 加密代理）
    public static let siteBaseURL = "https://a9db267525c1cf6b2.app.workbuddy.host"

    /// 卡密获取联系方式（展示在体验网关页面）
    public static let ownerContactQQ = "2317665079"

    // MARK: - 长安车联网开放平台

    /// OAuth client_id（与官网 App 一致）
    public static let changanOAuthClientID = "2c918082632162010163388048d60158"

    /// inCall 刷新令牌换取 access_token
    public static let inCallTokenURL = "https://incallapi.changan.com.cn/cac/api/v1/oauth2/refresh_token"

    /// 车联网 API 基础地址
    public static let iovBaseURL = "https://m.iov.changan.com.cn/app2/api"

    // MARK: - 共享容器（与描述文件 Entitlements 对应）

    /// App Group：App 与小组件共享数据
    public static let appGroupIdentifier = "group.6cd6b6c14418f98a.1"

    /// Keychain 共享组：App 与小组件共享登录凭据
    public static let keychainAccessGroup = "7NSH43RT4Z.carremote"

    /// 自定义 URL Scheme：小组件点击唤起 App
    public static let urlScheme = "carremote"

    /// 默认车型显示名
    public static let defaultCarName = "我的爱车"
}
