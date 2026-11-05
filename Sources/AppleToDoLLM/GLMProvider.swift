import Foundation
import Security

/// 智谱 GLM 提供者（ADR-0004 §4：key 只从 Keychain 读取）。
/// 端点 open.bigmodel.cn/api/paas/v4/chat/completions（OpenAI 兼容格式）。
public struct GLMProvider: LLMProviding {
    private let apiKey: String
    private let model: String

    public init(model: String = "glm-5.3") throws {
        guard let key = Self.readKeychainKey() else {
            throw LLMError.apiKeyMissing
        }
        apiKey = key
        self.model = model
    }

    public func complete(_ prompt: Prompt) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(APIRequest(model: model, messages: [
            .init(role: "system", content: prompt.system),
            .init(role: "user", content: prompt.user)
        ]))

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard httpResponse.statusCode != 429 else {
            throw LLMError.rateLimited
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw LLMError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let decoded: APIResponse
        do {
            decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw LLMError.invalidResponse
        }
        guard let choice = decoded.choices.first else {
            throw LLMError.invalidResponse
        }
        return Response(content: choice.message.content, reasoning: choice.message.reasoningContent)
    }

    // MARK: - Keychain 读取（ADR-0004 §4：服务名 com.appletodo.llm，账户 zhipu）

    private static func readKeychainKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.appletodo.llm",
            kSecAttrAccount as String: "zhipu",
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 智谱 API DTO（与 open.bigmodel.cn 的 JSON 字段一一对应）

struct APIRequest: Encodable {
    let model: String
    let messages: [APIMessage]
}

struct APIMessage: Encodable {
    let role: String
    let content: String
}

struct APIResponse: Decodable {
    let choices: [APIChoice]
}

struct APIChoice: Decodable {
    let message: APIMessageBody
}

struct APIMessageBody: Decodable {
    let content: String
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
    }
}
