import Foundation

/// LLM 提供者端口（ADR-0005 决策 2 工具形状）：任何供应商实现此协议即为大脑层的合法客户。
public protocol LLMProviding: Sendable {
    func complete(_ prompt: Prompt) async throws -> Response
}

/// 对话请求（值类型，Codable+Sendable）。
public struct Prompt: Equatable, Codable, Sendable {
    public let system: String
    public let user: String

    public init(system: String = "", user: String) {
        self.system = system
        self.user = user
    }
}

/// 对话响应（值类型）。reasoning 是 GLM 混合推理的副产品（ADR-0004 §4）。
public struct Response: Equatable, Codable, Sendable {
    public let content: String
    public let reasoning: String?

    public init(content: String, reasoning: String? = nil) {
        self.content = content
        self.reasoning = reasoning
    }
}

/// LLM 层错误（错误即数据）。
public enum LLMError: Error, Equatable, Codable, Sendable {
    case apiKeyMissing
    case networkError(String)
    case rateLimited
    case invalidResponse
}
