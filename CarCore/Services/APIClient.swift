import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 网络错误
public enum APIError: LocalizedError, Equatable {
    case invalidURL
    case network(String)
    case http(Int, String)
    case server(String)
    case decode(String)
    case notLoggedIn

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "接口地址无效"
        case .network(let message): return "网络连接失败：\(message)"
        case .http(let code, let message): return "服务返回 \(code)：\(message)"
        case .server(let message): return message
        case .decode(let message): return "数据解析失败：\(message)"
        case .notLoggedIn: return "请先登录"
        }
    }
}

/// 轻量网络客户端：JSON / form / multipart 三种请求。
public enum APIClient {

    /// 车联网接口通用请求头（与网页版一致）
    public static let changanHeaders: [String: String] = [
        "User-Agent": "okhttp/4.9.0",
        "vcs-app-id": "inCall",
        "X-Requested-With": "cn.com.changan.cvim",
        "Accept": "application/json, text/plain, */*"
    ]

    public static func request(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("无效的服务器响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, String(text.prefix(160)))
        }
        if data.isEmpty { return [String: Any]() }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return ["text": text]
            }
            throw APIError.decode("无法解析服务器响应")
        }
    }

    public static func getJSON(_ url: URL, headers: [String: String] = [:]) async throws -> Any {
        try await request(url, method: "GET", headers: headers)
    }

    public static func postJSON(_ url: URL, json: [String: Any], headers: [String: String] = [:]) async throws -> Any {
        var merged = ["Content-Type": "application/json"]
        merged.merge(headers) { current, _ in current }
        let body = try JSONSerialization.data(withJSONObject: json)
        return try await request(url, method: "POST", headers: merged, body: body)
    }

    public static func postForm(_ url: URL, params: [(String, String)], headers: [String: String] = [:]) async throws -> Any {
        var merged = ["Content-Type": "application/x-www-form-urlencoded"]
        merged.merge(headers) { current, _ in current }
        let body = formData(params).data(using: .utf8)
        return try await request(url, method: "POST", headers: merged, body: body)
    }

    /// multipart 上传（圈子图片）
    public static func upload(
        _ url: URL,
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        extraFields: [(String, String)]
    ) async throws -> Any {
        let boundary = "----CarRemoteBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        for (key, value) in extraFields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".data(using: .utf8) ?? Data())
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8) ?? Data())
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8) ?? Data())
        return try await request(
            url,
            method: "POST",
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: body
        )
    }

    public static func formData(_ params: [(String, String)]) -> String {
        params.map { "\($0.0)=\($0.1.urlQueryEncoded)" }.joined(separator: "&")
    }
}

extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

public extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }

    func bool(_ key: String) -> Bool? {
        if let b = self[key] as? Bool { return b }
        if let n = self[key] as? Int { return n != 0 }
        if let s = self[key] as? String { return ["1", "true", "yes"].contains(s.lowercased()) }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let n = self[key] as? Int { return n }
        if let d = self[key] as? Double { return Int(d) }
        if let s = self[key] as? String { return Int(s) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let d = self[key] as? Double { return d }
        if let n = self[key] as? Int { return Double(n) }
        if let s = self[key] as? String { return Double(s) }
        return nil
    }
}
