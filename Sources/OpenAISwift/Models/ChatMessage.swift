//
//  File.swift
//
//
//  Created by Bogdan Farca on 02.03.2023.
//

import Foundation

/// An enumeration of possible roles in a chat conversation.
public enum ChatRole: String, Codable {
    /// The role for the system that manages the chat interface.
    case system
    /// The role for the human user who initiates the chat.
    case user
    /// The role for the artificial assistant who responds to the user.
    case assistant
    /// Developer role for newer reasoning-capable models.
    case developer
    /// Tool role for function/tool outputs in chat completions.
    case tool
}

/// A structure that represents a single message in a chat conversation.
public struct ChatMessage: Codable, Identifiable {
    // uuid to conform to Identifiable protocol
    public var id = UUID()
    /// The role of the sender of the message.
    public let role: ChatRole?
    /// The content of the message.
    public let content: String?
    /// Tool calls emitted by assistant messages.
    public let toolCalls: [ChatToolCall]?
    /// Correlates tool output messages with a prior assistant tool call.
    public let toolCallID: String?

    /// Creates a new chat message with a given role and content.
    /// - Parameters:
    ///   - role: The role of the sender of the message.
    ///   - content: The content of the message.
    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
        self.toolCalls = nil
        self.toolCallID = nil
    }

    public init(role: ChatRole, content: String? = nil, toolCalls: [ChatToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<ChatMessage.CodingKeys> = try decoder.container(keyedBy: ChatMessage.CodingKeys.self)

        self.id = UUID()
        self.role = try container.decodeIfPresent(ChatRole.self, forKey: ChatMessage.CodingKeys.role)
        self.content = try container.decodeIfPresent(String.self, forKey: ChatMessage.CodingKeys.content)
        self.toolCalls = try container.decodeIfPresent([ChatToolCall].self, forKey: ChatMessage.CodingKeys.toolCalls)
        self.toolCallID = try container.decodeIfPresent(String.self, forKey: ChatMessage.CodingKeys.toolCallID)

    }

    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<ChatMessage.CodingKeys> = encoder.container(keyedBy: ChatMessage.CodingKeys.self)

        try container.encodeIfPresent(self.role, forKey: ChatMessage.CodingKeys.role)
        try container.encodeIfPresent(self.content, forKey: ChatMessage.CodingKeys.content)
        try container.encodeIfPresent(self.toolCalls, forKey: ChatMessage.CodingKeys.toolCalls)
        try container.encodeIfPresent(self.toolCallID, forKey: ChatMessage.CodingKeys.toolCallID)
    }
}

public struct ChatToolCall: Codable, Sendable {
    public struct Function: Codable, Sendable {
        public let name: String
        public let arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }

    public let id: String
    public let type: String
    public let function: Function

    public init(id: String, type: String = "function", function: Function) {
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct ChatFunctionDefinition: Encodable, Sendable {
    public let name: String
    public let description: String?
    public let parameters: [String: JSONValue]
    public let strict: Bool?

    public init(name: String, description: String? = nil, parameters: [String: JSONValue], strict: Bool? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }
}

public struct ChatTool: Encodable, Sendable {
    public let type: String
    public let function: ChatFunctionDefinition

    public init(function: ChatFunctionDefinition) {
        self.type = "function"
        self.function = function
    }
}

public enum ChatToolChoice: Encodable, Sendable {
    case none
    case auto
    case required
    case function(name: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case function
        case name
    }

    private struct ToolFunctionName: Encodable {
        let name: String
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .none:
            var c = encoder.singleValueContainer()
            try c.encode("none")
        case .auto:
            var c = encoder.singleValueContainer()
            try c.encode("auto")
        case .required:
            var c = encoder.singleValueContainer()
            try c.encode("required")
        case .function(let name):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("function", forKey: .type)
            try c.encode(ToolFunctionName(name: name), forKey: .function)
        }
    }
}

public enum ChatReasoningEffort: String, Encodable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
}

public enum ChatServiceTier: String, Encodable, Sendable {
    case auto
    case `default`
    case flex
    case priority
}

public struct ChatResponseFormat: Encodable, Sendable {
    public let type: String
    public let jsonSchema: JSONSchemaFormat?

    public init(type: String, jsonSchema: JSONSchemaFormat? = nil) {
        self.type = type
        self.jsonSchema = jsonSchema
    }

    public static func text() -> ChatResponseFormat {
        .init(type: "text")
    }

    public static func jsonObject() -> ChatResponseFormat {
        .init(type: "json_object")
    }

    public static func jsonSchema(name: String, schema: [String: JSONValue], description: String? = nil, strict: Bool? = nil) -> ChatResponseFormat {
        .init(
            type: "json_schema",
            jsonSchema: .init(name: name, schema: schema, description: description, strict: strict)
        )
    }

    public struct JSONSchemaFormat: Encodable, Sendable {
        public let name: String
        public let schema: [String: JSONValue]
        public let description: String?
        public let strict: Bool?

        public init(name: String, schema: [String: JSONValue], description: String? = nil, strict: Bool? = nil) {
            self.name = name
            self.schema = schema
            self.description = description
            self.strict = strict
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

public struct ChatStreamOptions: Encodable, Sendable {
    public let includeUsage: Bool?

    public init(includeUsage: Bool? = nil) {
        self.includeUsage = includeUsage
    }

    private enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

/// A structure that represents a chat conversation.
public struct ChatConversation: Encodable {
    /// The name or identifier of the user who initiates the chat. Optional if not provided by the user interface.
    let user: String?

    /// The messages to generate chat completions for. Ordered chronologically from oldest to newest.
    let messages: [ChatMessage]

    /// The ID of the model used by the assistant to generate responses. See OpenAI documentation for details on which models work with the Chat API.
    let model: String

    /// A parameter that controls how random or deterministic the responses are, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. Optional, defaults to 1.
    let temperature: Double?

    /// A parameter that controls how diverse or narrow-minded the responses are, between 0 and 1. Higher values like 0.9 mean only the tokens comprising the top 90% probability mass are considered, while lower values like 0.1 mean only the top 10%. Optional, defaults to 1.
    let topProbabilityMass: Double?

    /// How many chat completion choices to generate for each input message. Optional, defaults to 1.
    let choices: Int?

    /// An array of up to 4 sequences where the API will stop generating further tokens. Optional.
    let stop: [String]?

    /// The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length. Optional.
    let maxTokens: Int?

    /// A parameter that penalizes new tokens based on whether they appear in the text so far, between -2 and 2. Positive values increase the model's likelihood to talk about new topics. Optional if not specified by default or by user input. Optional, defaults to 0.
    let presencePenalty: Double?

    /// A parameter that penalizes new tokens based on their existing frequency in the text so far, between -2 and 2. Positive values decrease the model's likelihood to repeat the same line verbatim. Optional if not specified by default or by user input. Optional, defaults to 0.
    let frequencyPenalty: Double?

    /// Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID in the OpenAI Tokenizer—not English words) to an associated bias value from -100 to 100. Values between -1 and 1 should decrease or increase likelihood of selection; values like -100 or 100 should result in a ban or exclusive selection of the relevant token.
    let logitBias: [Int: Double]?

    /// If you're generating long completions, waiting for the response can take many seconds. To get responses sooner, you can 'stream' the completion as it's being generated. This allows you to start printing or processing the beginning of the completion before the full completion is finished.
    /// https://github.com/openai/openai-cookbook/blob/main/examples/How_to_stream_completions.ipynb
    let stream: Bool?
    /// Chat tools array for function calling.
    let tools: [ChatTool]?
    /// Tool selection strategy.
    let toolChoice: ChatToolChoice?
    /// Structured output format for chat responses.
    let responseFormat: ChatResponseFormat?
    /// Max completion tokens for newer reasoning-capable models.
    let maxCompletionTokens: Int?
    /// Reasoning effort for supported chat models.
    let reasoningEffort: ChatReasoningEffort?
    /// Allow parallel tool calls.
    let parallelToolCalls: Bool?
    /// Request storage behavior.
    let store: Bool?
    /// Service tier selection.
    let serviceTier: ChatServiceTier?
    /// Stream options payload.
    let streamOptions: ChatStreamOptions?

    enum CodingKeys: String, CodingKey {
        case user
        case messages
        case model
        case temperature
        case topProbabilityMass = "top_p"
        case choices = "n"
        case stop
        case maxTokens = "max_tokens"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case logitBias = "logit_bias"
        case stream
        case tools
        case toolChoice = "tool_choice"
        case responseFormat = "response_format"
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
        case parallelToolCalls = "parallel_tool_calls"
        case store
        case serviceTier = "service_tier"
        case streamOptions = "stream_options"
    }
}

public struct ChatError: Codable {
    public struct Payload: Codable {
        public let message, type: String
        public let param, code: String?
    }

    public let error: Payload
}
