import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported JSON value"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public enum ResponseInputRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case developer
    case tool
}

public struct ResponseInputMessage: Codable, Sendable {
    public let role: ResponseInputRole
    public let content: String

    public init(role: ResponseInputRole, content: String) {
        self.role = role
        self.content = content
    }
}

public enum ResponseInputItem: Codable, Sendable {
    case message(ResponseInputMessage)
    case functionCallOutput(callID: String, output: String)
    case reasoning(id: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case role
        case content
        case callID = "call_id"
        case output
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "message":
            let role = try container.decode(ResponseInputRole.self, forKey: .role)
            let content = try container.decode(String.self, forKey: .content)
            self = .message(.init(role: role, content: content))
        case "function_call_output":
            let callID = try container.decode(String.self, forKey: .callID)
            let output = try container.decode(String.self, forKey: .output)
            self = .functionCallOutput(callID: callID, output: output)
        case "reasoning":
            let id = try container.decode(String.self, forKey: .id)
            self = .reasoning(id: id)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported input item type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let message):
            try container.encode("message", forKey: .type)
            try container.encode(message.role, forKey: .role)
            try container.encode(message.content, forKey: .content)
        case .functionCallOutput(let callID, let output):
            try container.encode("function_call_output", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(output, forKey: .output)
        case .reasoning(let id):
            try container.encode("reasoning", forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}

public enum ResponseInput: Codable, Sendable {
    case text(String)
    case items([ResponseInputItem])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .items(try container.decode([ResponseInputItem].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .items(let items):
            try container.encode(items)
        }
    }
}

public struct ResponseTextConfiguration: Codable, Sendable {
    public let format: Format?
    public let verbosity: Verbosity?

    public init(format: Format? = nil, verbosity: Verbosity? = nil) {
        self.format = format
        self.verbosity = verbosity
    }

    public enum Verbosity: String, Codable, Sendable {
        case low
        case medium
        case high
    }

    public enum Format: Codable, Sendable {
        case text
        case jsonObject
        case jsonSchema(
            name: String,
            schema: [String: JSONValue],
            description: String? = nil,
            strict: Bool? = nil
        )

        private enum CodingKeys: String, CodingKey {
            case type
            case name
            case schema
            case description
            case strict
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text
            case "json_object":
                self = .jsonObject
            case "json_schema":
                self = .jsonSchema(
                    name: try container.decode(String.self, forKey: .name),
                    schema: try container.decode([String: JSONValue].self, forKey: .schema),
                    description: try container.decodeIfPresent(String.self, forKey: .description),
                    strict: try container.decodeIfPresent(Bool.self, forKey: .strict)
                )
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown text format: \(type)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text:
                try container.encode("text", forKey: .type)
            case .jsonObject:
                try container.encode("json_object", forKey: .type)
            case .jsonSchema(let name, let schema, let description, let strict):
                try container.encode("json_schema", forKey: .type)
                try container.encode(name, forKey: .name)
                try container.encode(schema, forKey: .schema)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encodeIfPresent(strict, forKey: .strict)
            }
        }
    }
}

public struct ResponseReasoning: Codable, Sendable {
    public let effort: Effort?
    public let summary: Summary?

    public init(effort: Effort? = nil, summary: Summary? = nil) {
        self.effort = effort
        self.summary = summary
    }

    public enum Effort: String, Codable, Sendable {
        case none
        case minimal
        case low
        case medium
        case high
    }

    public enum Summary: String, Codable, Sendable {
        case auto
        case concise
        case detailed
    }
}

public enum ResponseToolChoice: Codable, Sendable {
    case none
    case auto
    case required
    case function(name: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }

    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self) {
            let type = try keyed.decode(String.self, forKey: .type)
            switch type {
            case "function":
                self = .function(name: try keyed.decode(String.self, forKey: .name))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: keyed,
                    debugDescription: "Unknown tool choice object: \(type)"
                )
            }
        } else {
            let container = try decoder.singleValueContainer()
            switch try container.decode(String.self) {
            case "none": self = .none
            case "auto": self = .auto
            case "required": self = .required
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown tool choice")
            }
        }
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
            try c.encode(name, forKey: .name)
        }
    }
}

public enum ResponseTool: Codable, Sendable {
    case function(Function)
    case webSearch
    case fileSearch(vectorStoreIDs: [String])
    case codeInterpreter
    case computerUsePreview(displayWidth: Int, displayHeight: Int, environment: String)
    case imageGeneration
    case mcp(serverURL: String, label: String? = nil)
    case shell
    case applyPatch

    public struct Function: Codable, Sendable {
        public let name: String
        public let description: String?
        public let parameters: [String: JSONValue]
        public let strict: Bool

        public init(name: String, description: String? = nil, parameters: [String: JSONValue], strict: Bool = true) {
            self.name = name
            self.description = description
            self.parameters = parameters
            self.strict = strict
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case description
        case parameters
        case strict
        case vectorStoreIDs = "vector_store_ids"
        case displayWidth = "display_width"
        case displayHeight = "display_height"
        case environment
        case serverURL = "server_url"
        case label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "function":
            self = .function(.init(
                name: try c.decode(String.self, forKey: .name),
                description: try c.decodeIfPresent(String.self, forKey: .description),
                parameters: try c.decode([String: JSONValue].self, forKey: .parameters),
                strict: try c.decodeIfPresent(Bool.self, forKey: .strict) ?? true
            ))
        case "web_search":
            self = .webSearch
        case "file_search":
            self = .fileSearch(vectorStoreIDs: try c.decode([String].self, forKey: .vectorStoreIDs))
        case "code_interpreter":
            self = .codeInterpreter
        case "computer_use_preview":
            self = .computerUsePreview(
                displayWidth: try c.decode(Int.self, forKey: .displayWidth),
                displayHeight: try c.decode(Int.self, forKey: .displayHeight),
                environment: try c.decode(String.self, forKey: .environment)
            )
        case "image_generation":
            self = .imageGeneration
        case "mcp":
            self = .mcp(
                serverURL: try c.decode(String.self, forKey: .serverURL),
                label: try c.decodeIfPresent(String.self, forKey: .label)
            )
        case "shell":
            self = .shell
        case "apply_patch":
            self = .applyPatch
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown tool type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .function(let fn):
            try c.encode("function", forKey: .type)
            try c.encode(fn.name, forKey: .name)
            try c.encodeIfPresent(fn.description, forKey: .description)
            try c.encode(fn.parameters, forKey: .parameters)
            try c.encode(fn.strict, forKey: .strict)
        case .webSearch:
            try c.encode("web_search", forKey: .type)
        case .fileSearch(let ids):
            try c.encode("file_search", forKey: .type)
            try c.encode(ids, forKey: .vectorStoreIDs)
        case .codeInterpreter:
            try c.encode("code_interpreter", forKey: .type)
        case .computerUsePreview(let width, let height, let environment):
            try c.encode("computer_use_preview", forKey: .type)
            try c.encode(width, forKey: .displayWidth)
            try c.encode(height, forKey: .displayHeight)
            try c.encode(environment, forKey: .environment)
        case .imageGeneration:
            try c.encode("image_generation", forKey: .type)
        case .mcp(let serverURL, let label):
            try c.encode("mcp", forKey: .type)
            try c.encode(serverURL, forKey: .serverURL)
            try c.encodeIfPresent(label, forKey: .label)
        case .shell:
            try c.encode("shell", forKey: .type)
        case .applyPatch:
            try c.encode("apply_patch", forKey: .type)
        }
    }
}

public struct ResponseRequest: Codable, Sendable {
    public let model: String
    public let input: ResponseInput
    public let instructions: String?
    public let previousResponseID: String?
    public let store: Bool?
    public var stream: Bool?
    public let text: ResponseTextConfiguration?
    public let tools: [ResponseTool]?
    public let toolChoice: ResponseToolChoice?
    public let parallelToolCalls: Bool?
    public let reasoning: ResponseReasoning?
    public let include: [String]?
    public let temperature: Double?
    public let topP: Double?
    public let maxOutputTokens: Int?
    public let user: String?

    public init(
        model: String,
        input: ResponseInput,
        instructions: String? = nil,
        previousResponseID: String? = nil,
        store: Bool? = nil,
        stream: Bool? = nil,
        text: ResponseTextConfiguration? = nil,
        tools: [ResponseTool]? = nil,
        toolChoice: ResponseToolChoice? = nil,
        parallelToolCalls: Bool? = nil,
        reasoning: ResponseReasoning? = nil,
        include: [String]? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxOutputTokens: Int? = nil,
        user: String? = nil
    ) {
        self.model = model
        self.input = input
        self.instructions = instructions
        self.previousResponseID = previousResponseID
        self.store = store
        self.stream = stream
        self.text = text
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.reasoning = reasoning
        self.include = include
        self.temperature = temperature
        self.topP = topP
        self.maxOutputTokens = maxOutputTokens
        self.user = user
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case previousResponseID = "previous_response_id"
        case store
        case stream
        case text
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning
        case include
        case temperature
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
        case user
    }
}

public struct ResponseObject: Decodable, Sendable {
    public let id: String
    public let object: String
    public let createdAt: Int?
    public let model: String?
    public let status: String?
    public let output: [ResponseOutputItem]
    public let previousResponseID: String?
    public let usage: ResponseUsage?
    public let error: ResponseAPIError?
    public let incompleteDetails: ResponseIncompleteDetails?

    public var outputText: String {
        output.compactMap { item in
            if case .message(let message) = item {
                return message.content.compactMap { part in
                    if case .outputText(let text) = part {
                        return text
                    }
                    return nil
                }.joined()
            }
            return nil
        }.joined()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case object
        case createdAt = "created_at"
        case model
        case status
        case output
        case previousResponseID = "previous_response_id"
        case usage
        case error
        case incompleteDetails = "incomplete_details"
    }
}

public struct ResponseDeletionResult: Decodable, Sendable {
    public let id: String
    public let object: String?
    public let deleted: Bool
}

public struct ResponseInputItemsList: Decodable, Sendable {
    public let object: String?
    public let data: [ResponseInputItem]?
    public let firstID: String?
    public let lastID: String?
    public let hasMore: Bool?

    private enum CodingKeys: String, CodingKey {
        case object
        case data
        case firstID = "first_id"
        case lastID = "last_id"
        case hasMore = "has_more"
    }
}

public enum ResponseOutputItem: Decodable, Sendable {
    case message(ResponseOutputMessage)
    case functionCall(ResponseFunctionCall)
    case reasoning(ResponseReasoningItem)
    case webSearchCall(ResponseToolCall)
    case fileSearchCall(ResponseToolCall)
    case computerCall(ResponseToolCall)
    case codeInterpreterCall(ResponseToolCall)
    case imageGenerationCall(ResponseToolCall)
    case mcpCall(ResponseToolCall)
    case shellCall(ResponseToolCall)
    case applyPatchCall(ResponseToolCall)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "message":
            self = .message(try ResponseOutputMessage(from: decoder))
        case "function_call":
            self = .functionCall(try ResponseFunctionCall(from: decoder))
        case "reasoning":
            self = .reasoning(try ResponseReasoningItem(from: decoder))
        case "web_search_call":
            self = .webSearchCall(try ResponseToolCall(from: decoder))
        case "file_search_call":
            self = .fileSearchCall(try ResponseToolCall(from: decoder))
        case "computer_call":
            self = .computerCall(try ResponseToolCall(from: decoder))
        case "code_interpreter_call":
            self = .codeInterpreterCall(try ResponseToolCall(from: decoder))
        case "image_generation_call":
            self = .imageGenerationCall(try ResponseToolCall(from: decoder))
        case "mcp_call":
            self = .mcpCall(try ResponseToolCall(from: decoder))
        case "shell_call":
            self = .shellCall(try ResponseToolCall(from: decoder))
        case "apply_patch_call":
            self = .applyPatchCall(try ResponseToolCall(from: decoder))
        default:
            self = .unknown(type)
        }
    }
}

public struct ResponseOutputMessage: Decodable, Sendable {
    public let id: String?
    public let role: String?
    public let status: String?
    public let content: [Content]

    public enum Content: Decodable, Sendable {
        case outputText(String)
        case refusal(String)
        case unknown

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case refusal
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "output_text":
                self = .outputText((try? c.decode(String.self, forKey: .text)) ?? "")
            case "refusal":
                self = .refusal((try? c.decode(String.self, forKey: .refusal)) ?? "")
            default:
                self = .unknown
            }
        }
    }
}

public struct ResponseFunctionCall: Decodable, Sendable {
    public let id: String?
    public let callID: String?
    public let name: String?
    public let arguments: String?
    public let status: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case callID = "call_id"
        case name
        case arguments
        case status
    }
}

public struct ResponseReasoningItem: Decodable, Sendable {
    public struct Summary: Decodable, Sendable {
        public let text: String?
    }

    public let id: String?
    public let summary: [Summary]?
}

public struct ResponseToolCall: Decodable, Sendable {
    public let id: String?
    public let type: String?
    public let status: String?
}

public struct ResponseUsage: Decodable, Sendable {
    public struct OutputTokenDetails: Decodable, Sendable {
        public let reasoningTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }

    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let outputTokenDetails: OutputTokenDetails?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case outputTokenDetails = "output_tokens_details"
    }
}

public struct ResponseAPIError: Decodable, Sendable {
    public let message: String
    public let type: String
    public let param: String?
    public let code: String?
}

public struct ResponseIncompleteDetails: Decodable, Sendable {
    public let reason: String?
}

public struct ResponseStreamEvent: Decodable, Sendable {
    public let type: String
    public let sequenceNumber: Int?
    public let response: ResponseObject?
    public let outputIndex: Int?
    public let itemID: String?
    public let contentIndex: Int?
    public let item: ResponseOutputItem?
    public let delta: String?
    public let text: String?
    public let summaryText: String?
    public let arguments: String?
    public let error: ResponseAPIError?

    private enum CodingKeys: String, CodingKey {
        case type
        case sequenceNumber = "sequence_number"
        case response
        case outputIndex = "output_index"
        case itemID = "item_id"
        case contentIndex = "content_index"
        case item
        case delta
        case text
        case summaryText = "summary_text"
        case arguments
        case error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        sequenceNumber = try c.decodeIfPresent(Int.self, forKey: .sequenceNumber)
        response = try c.decodeIfPresent(ResponseObject.self, forKey: .response)
        outputIndex = try c.decodeIfPresent(Int.self, forKey: .outputIndex)
        itemID = try c.decodeIfPresent(String.self, forKey: .itemID)
        contentIndex = try c.decodeIfPresent(Int.self, forKey: .contentIndex)
        item = try? c.decodeIfPresent(ResponseOutputItem.self, forKey: .item)
        delta = try c.decodeIfPresent(String.self, forKey: .delta)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        summaryText = try c.decodeIfPresent(String.self, forKey: .summaryText)
        arguments = try c.decodeIfPresent(String.self, forKey: .arguments)
        error = try c.decodeIfPresent(ResponseAPIError.self, forKey: .error)
    }

    public var outputTextDelta: String? {
        guard type == "response.output_text.delta" else { return nil }
        return delta
    }

    public var outputTextDone: String? {
        guard type == "response.output_text.done" else { return nil }
        return text
    }

    public var reasoningSummaryDelta: String? {
        guard type == "response.reasoning_summary_text.delta" else { return nil }
        return delta ?? summaryText
    }
}

public struct ResponseStreamTextAccumulator: Sendable {
    public private(set) var outputText = ""

    public init() {}

    public mutating func apply(_ event: ResponseStreamEvent) {
        if let delta = event.outputTextDelta {
            outputText += delta
        }

        if let done = event.outputTextDone {
            if outputText.isEmpty {
                outputText = done
            } else if done.count > outputText.count && done.hasPrefix(outputText) {
                outputText = done
            }
        }
    }
}
