import Foundation
#if canImport(FoundationNetworking) && canImport(FoundationXML)
import FoundationNetworking
import FoundationXML
#endif

public enum OpenAIError: Error {
    case networkError(code: Int)
    case genericError(error: Error)
    case decodingError(error: Error)
    case chatError(error: ChatError.Payload)
}

public class OpenAISwift {
    fileprivate let config: Config
    fileprivate let handler = ServerSentEventsHandler()
    fileprivate let responsesHandler = ResponsesServerSentEventsHandler()

    /// Configuration object for the client
    public struct Config {
        
        /// Initialiser
        /// - Parameter session: the session to use for network requests.
        public init(baseURL: String, endpointPrivider: OpenAIEndpointProvider, session: URLSession, authorizeRequest: @escaping (inout URLRequest) -> Void) {
            self.baseURL = baseURL
            self.endpointProvider = endpointPrivider
            self.authorizeRequest = authorizeRequest
            self.session = session
        }
        let baseURL: String
        let endpointProvider: OpenAIEndpointProvider
        let session:URLSession
        let authorizeRequest: (inout URLRequest) -> Void
        
        public static func makeDefaultOpenAI(apiKey: String) -> Self {
            .init(baseURL: "https://api.openai.com",
                  endpointPrivider: OpenAIEndpointProvider(source: .openAI),
                  session: .shared,
                  authorizeRequest: { request in
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            })
        }
    }
    
    public init(config: Config) {
        self.config = config
    }
}

extension OpenAISwift {
    /// Send a Completion to the OpenAI API
    /// - Parameters:
    ///   - prompt: The Text Prompt
    ///   - model: The AI Model to Use. Set to `OpenAIModelType.gpt3(.davinci)` by default which is the most capable model
    ///   - maxTokens: The limit character for the returned response, defaults to 16 as per the API
    ///   - completionHandler: Returns an OpenAI Data Model
    @available(*, deprecated, message: "Completions API is legacy. Prefer sendResponse(with:) with /v1/responses.")
    public func sendCompletion(with prompt: String, model: OpenAIModelType = .gpt3(.davinci), maxTokens: Int = 16, temperature: Double = 1, completionHandler: @escaping (Result<OpenAI<TextResult>, OpenAIError>) -> Void) {
        let endpoint = OpenAIEndpointProvider.API.completions
        let body = Command(prompt: prompt, model: model.modelName, maxTokens: maxTokens, temperature: temperature)
        let request = prepareRequest(endpoint, body: body)
        
        makeRequest(request: request) { result in
            switch result {
            case .success(let success):
                do {
                    let res = try JSONDecoder().decode(OpenAI<TextResult>.self, from: success)
                    completionHandler(.success(res))
                } catch {
                    completionHandler(.failure(.decodingError(error: error)))
                }
            case .failure(let failure):
                completionHandler(.failure(.genericError(error: failure)))
            }
        }
    }
    
    /// Send a Edit request to the OpenAI API
    /// - Parameters:
    ///   - instruction: The Instruction For Example: "Fix the spelling mistake"
    ///   - model: The Model to use, the only support model is `text-davinci-edit-001`
    ///   - input: The Input For Example "My nam is Adam"
    ///   - completionHandler: Returns an OpenAI Data Model
    @available(*, deprecated, message: "Edits API is legacy/deprecated. Prefer sendResponse(with:) with /v1/responses.")
    public func sendEdits(with instruction: String, model: OpenAIModelType = .feature(.davinci), input: String = "", completionHandler: @escaping (Result<OpenAI<TextResult>, OpenAIError>) -> Void) {
        let endpoint = OpenAIEndpointProvider.API.edits
        let body = Instruction(instruction: instruction, model: model.modelName, input: input)
        let request = prepareRequest(endpoint, body: body)
        
        makeRequest(request: request) { result in
            switch result {
            case .success(let success):
                do {
                    let res = try JSONDecoder().decode(OpenAI<TextResult>.self, from: success)
                    completionHandler(.success(res))
                } catch {
                    completionHandler(.failure(.decodingError(error: error)))
                }
            case .failure(let failure):
                completionHandler(.failure(.genericError(error: failure)))
            }
        }
    }
    
    /// Send a Moderation request to the OpenAI API
    /// - Parameters:
    ///   - input: The Input For Example "My nam is Adam"
    ///   - model: The Model to use
    ///   - completionHandler: Returns an OpenAI Data Model
    public func sendModerations(with input: String, model: OpenAIModelType = .moderation(.latest), completionHandler: @escaping (Result<OpenAI<ModerationResult>, OpenAIError>) -> Void) {
        let endpoint = OpenAIEndpointProvider.API.moderations
        let body = Moderation(input: input, model: model.modelName)
        let request = prepareRequest(endpoint, body: body)
        
        makeRequest(request: request) { result in
            switch result {
            case .success(let success):
                do {
                    let res = try JSONDecoder().decode(OpenAI<ModerationResult>.self, from: success)
                    completionHandler(.success(res))
                } catch {
                    completionHandler(.failure(.decodingError(error: error)))
                }
            case .failure(let failure):
                completionHandler(.failure(.genericError(error: failure)))
            }
        }
    }
    
    /// Send a Chat request to the OpenAI API
    /// - Parameters:
    ///   - messages: Array of `ChatMessages`
    ///   - model: The Model to use, the only support model is `gpt-3.5-turbo`
    ///   - user: A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse.
    ///   - temperature: What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or topProbabilityMass but not both.
    ///   - topProbabilityMass: The OpenAI api equivalent of the "top_p" parameter. An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.
    ///   - choices: How many chat completion choices to generate for each input message.
    ///   - stop: Up to 4 sequences where the API will stop generating further tokens.
    ///   - maxTokens: The maximum number of tokens allowed for the generated answer. By default, the number of tokens the model can return will be (4096 - prompt tokens).
    ///   - presencePenalty: Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.
    ///   - frequencyPenalty: Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.
    ///   - logitBias: Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID in the OpenAI Tokenizer—not English words) to an associated bias value from -100 to 100. Values between -1 and 1 should decrease or increase likelihood of selection; values like -100 or 100 should result in a ban or exclusive selection of the relevant token.
    ///   - completionHandler: Returns an OpenAI Data Model
    public func sendChat(with messages: [ChatMessage],
                         model: OpenAIModelType = .chat(.chatgpt),
                         user: String? = nil,
                         temperature: Double? = 1,
                         topProbabilityMass: Double? = 0,
                         choices: Int? = 1,
                         stop: [String]? = nil,
                         maxTokens: Int? = nil,
                         presencePenalty: Double? = 0,
                         frequencyPenalty: Double? = 0,
                         logitBias: [Int: Double]? = nil,
                         tools: [ChatTool]? = nil,
                         toolChoice: ChatToolChoice? = nil,
                         responseFormat: ChatResponseFormat? = nil,
                         maxCompletionTokens: Int? = nil,
                         reasoningEffort: ChatReasoningEffort? = nil,
                         parallelToolCalls: Bool? = nil,
                         store: Bool? = nil,
                         serviceTier: ChatServiceTier? = nil,
                         completionHandler: @escaping (Result<OpenAI<MessageResult>, OpenAIError>) -> Void) {
        let normalized = normalizeChatTokenFields(
            modelName: model.modelName,
            maxTokens: maxTokens,
            maxCompletionTokens: maxCompletionTokens
        )
        let endpoint = OpenAIEndpointProvider.API.chat
        let body = ChatConversation(user: user,
                                    messages: messages,
                                    model: model.modelName,
                                    temperature: temperature,
                                    topProbabilityMass: topProbabilityMass,
                                    choices: choices,
                                    stop: stop,
                                    maxTokens: normalized.maxTokens,
                                    presencePenalty: presencePenalty,
                                    frequencyPenalty: frequencyPenalty,
                                    logitBias: logitBias,
                                    stream: false,
                                    tools: tools,
                                    toolChoice: toolChoice,
                                    responseFormat: responseFormat,
                                    maxCompletionTokens: normalized.maxCompletionTokens,
                                    reasoningEffort: reasoningEffort,
                                    parallelToolCalls: parallelToolCalls,
                                    store: store,
                                    serviceTier: serviceTier,
                                    streamOptions: nil)

        let request = prepareRequest(endpoint, body: body)
        
        makeRequest(request: request) { result in
            switch result {
            case .success(let success):
                if let chatErr = try? JSONDecoder().decode(ChatError.self, from: success) as ChatError {
                    completionHandler(.failure(.chatError(error: chatErr.error)))
                    return
                }
                
                do {
                    let res = try JSONDecoder().decode(OpenAI<MessageResult>.self, from: success)
                    completionHandler(.success(res))
                } catch {
                    completionHandler(.failure(.decodingError(error: error)))
                }
                
            case .failure(let failure):
                completionHandler(.failure(.genericError(error: failure)))
            }
        }
    }
    
    /// Send a Embeddings request to the OpenAI API
    /// - Parameters:
    ///   - input: The Input For Example "The food was delicious and the waiter..."
    ///   - model: The Model to use, the only support model is `text-embedding-ada-002`
    ///   - completionHandler: Returns an OpenAI Data Model
    public func sendEmbeddings(with input: String,
                               model: OpenAIModelType = .embedding(.ada),
                               completionHandler: @escaping (Result<OpenAI<EmbeddingResult>, OpenAIError>) -> Void) {
        let endpoint = OpenAIEndpointProvider.API.embeddings
        let body = EmbeddingsInput(input: input,
                                   model: model.modelName)

        let request = prepareRequest(endpoint, body: body)
        makeRequest(request: request) { result in
            switch result {
                case .success(let success):
                    do {
                        let res = try JSONDecoder().decode(OpenAI<EmbeddingResult>.self, from: success)
                        completionHandler(.success(res))
                    } catch {
                        completionHandler(.failure(.decodingError(error: error)))
                    }
                case .failure(let failure):
                    completionHandler(.failure(.genericError(error: failure)))
            }
        }
    }
    
    /// Send a Chat request to the OpenAI API with stream enabled
    /// - Parameters:
    ///   - messages: Array of `ChatMessages`
    ///   - model: The Model to use, the only support model is `gpt-3.5-turbo`
    ///   - user: A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse.
    ///   - temperature: What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or topProbabilityMass but not both.
    ///   - topProbabilityMass: The OpenAI api equivalent of the "top_p" parameter. An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.
    ///   - choices: How many chat completion choices to generate for each input message.
    ///   - stop: Up to 4 sequences where the API will stop generating further tokens.
    ///   - maxTokens: The maximum number of tokens allowed for the generated answer. By default, the number of tokens the model can return will be (4096 - prompt tokens).
    ///   - presencePenalty: Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.
    ///   - frequencyPenalty: Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.
    ///   - logitBias: Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID in the OpenAI Tokenizer—not English words) to an associated bias value from -100 to 100. Values between -1 and 1 should decrease or increase likelihood of selection; values like -100 or 100 should result in a ban or exclusive selection of the relevant token.
    ///   - onEventReceived: Called Multiple times, returns an OpenAI Data Model
    ///   - onComplete: Triggers when sever complete sending the message
    public func sendStreamingChat(with messages: [ChatMessage],
                                  model: OpenAIModelType = .chat(.chatgpt),
                                  user: String? = nil,
                                  temperature: Double? = 1,
                                  topProbabilityMass: Double? = 0,
                                  choices: Int? = 1,
                                  stop: [String]? = nil,
                                  maxTokens: Int? = nil,
                                  presencePenalty: Double? = 0,
                                  frequencyPenalty: Double? = 0,
                                  logitBias: [Int: Double]? = nil,
                                  tools: [ChatTool]? = nil,
                                  toolChoice: ChatToolChoice? = nil,
                                  responseFormat: ChatResponseFormat? = nil,
                                  maxCompletionTokens: Int? = nil,
                                  reasoningEffort: ChatReasoningEffort? = nil,
                                  parallelToolCalls: Bool? = nil,
                                  store: Bool? = nil,
                                  serviceTier: ChatServiceTier? = nil,
                                  streamOptions: ChatStreamOptions? = nil,
                                  onEventReceived: ((Result<OpenAI<StreamMessageResult>, OpenAIError>) -> Void)? = nil,
                                  onComplete: (() -> Void)? = nil) {
        let normalized = normalizeChatTokenFields(
            modelName: model.modelName,
            maxTokens: maxTokens,
            maxCompletionTokens: maxCompletionTokens
        )
        let endpoint = OpenAIEndpointProvider.API.chat
        let body = ChatConversation(user: user,
                                    messages: messages,
                                    model: model.modelName,
                                    temperature: temperature,
                                    topProbabilityMass: topProbabilityMass,
                                    choices: choices,
                                    stop: stop,
                                    maxTokens: normalized.maxTokens,
                                    presencePenalty: presencePenalty,
                                    frequencyPenalty: frequencyPenalty,
                                    logitBias: logitBias,
                                    stream: true,
                                    tools: tools,
                                    toolChoice: toolChoice,
                                    responseFormat: responseFormat,
                                    maxCompletionTokens: normalized.maxCompletionTokens,
                                    reasoningEffort: reasoningEffort,
                                    parallelToolCalls: parallelToolCalls,
                                    store: store,
                                    serviceTier: serviceTier,
                                    streamOptions: streamOptions)
        let request = prepareRequest(endpoint, body: body)
        handler.onEventReceived = onEventReceived
        handler.onComplete = onComplete
        handler.connect(with: request)
    }

    /// Send a Responses API request to the OpenAI API
    /// - Parameters:
    ///   - requestBody: The full request payload for /v1/responses
    ///   - completionHandler: Returns a ResponseObject
    public func sendResponse(with requestBody: ResponseRequest,
                             completionHandler: @escaping (Result<ResponseObject, OpenAIError>) -> Void) {
        let endpoint = OpenAIEndpointProvider.API.responses
        let request = prepareRequest(endpoint, body: requestBody)

        makeRequest(request: request) { result in
            switch result {
            case .success(let success):
                if let apiError = try? JSONDecoder().decode(ChatError.self, from: success) {
                    completionHandler(.failure(.chatError(error: apiError.error)))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(ResponseObject.self, from: success)
                    completionHandler(.success(response))
                } catch {
                    completionHandler(.failure(.decodingError(error: error)))
                }
            case .failure(let failure):
                completionHandler(.failure(.genericError(error: failure)))
            }
        }
    }

    /// Convenience helper for simple text inputs with Responses API
    /// - Parameters:
    ///   - input: A plain text input
    ///   - model: The model name
    ///   - instructions: Optional high-level instructions
    ///   - previousResponseID: Optional ID for multi-turn chaining
    ///   - store: Optional stateful storage flag
    ///   - completionHandler: Returns a ResponseObject
    public func sendResponse(with input: String,
                             model: OpenAIModelType = .other("gpt-5"),
                             instructions: String? = nil,
                             previousResponseID: String? = nil,
                             store: Bool? = nil,
                             completionHandler: @escaping (Result<ResponseObject, OpenAIError>) -> Void) {
        let requestBody = ResponseRequest(
            model: model.modelName,
            input: .text(input),
            instructions: instructions,
            previousResponseID: previousResponseID,
            store: store
        )
        sendResponse(with: requestBody, completionHandler: completionHandler)
    }

    /// Send a streaming Responses API request to the OpenAI API
    /// - Parameters:
    ///   - requestBody: The request payload for /v1/responses
    ///   - onEventReceived: Called for each decoded stream event
    ///   - onComplete: Triggers when the stream completes
    public func sendStreamingResponse(with requestBody: ResponseRequest,
                                      onEventReceived: ((Result<ResponseStreamEvent, OpenAIError>) -> Void)? = nil,
                                      onComplete: (() -> Void)? = nil) {
        let endpoint = OpenAIEndpointProvider.API.responses
        var requestBody = requestBody
        requestBody.stream = true
        let request = prepareRequest(endpoint, body: requestBody)
        responsesHandler.onEventReceived = onEventReceived
        responsesHandler.onComplete = onComplete
        responsesHandler.connect(with: request)
    }

    /// Retrieve a stored response by ID.
    /// - Parameters:
    ///   - responseID: Response identifier.
    ///   - completionHandler: Returns a ResponseObject.
    public func getResponse(with responseID: String,
                            completionHandler: @escaping (Result<ResponseObject, OpenAIError>) -> Void) {
        let basePath = config.endpointProvider.getPath(api: .responses)
        let request = prepareRequest(
            path: basePath + "/\(escapedPathComponent(responseID))",
            method: "GET"
        )

        makeRequest(request: request) { result in
            switch result {
            case .success(let success):
                do {
                    let response = try JSONDecoder().decode(ResponseObject.self, from: success)
                    completionHandler(.success(response))
                } catch {
                    completionHandler(.failure(.decodingError(error: error)))
                }
            case .failure(let failure):
                completionHandler(.failure(.genericError(error: failure)))
            }
        }
    }

    /// Delete a stored response by ID.
    /// - Parameters:
    ///   - responseID: Response identifier.
    ///   - completionHandler: Returns deletion result.
    public func deleteResponse(with responseID: String,
                               completionHandler: @escaping (Result<ResponseDeletionResult, OpenAIError>) -> Void) {
        let basePath = config.endpointProvider.getPath(api: .responses)
        let request = prepareRequest(
            path: basePath + "/\(escapedPathComponent(responseID))",
            method: "DELETE"
        )

        makeRequest(request: request) { result in
            switch result {
            case .success(let success):
                do {
                    let response = try JSONDecoder().decode(ResponseDeletionResult.self, from: success)
                    completionHandler(.success(response))
                } catch {
                    completionHandler(.failure(.decodingError(error: error)))
                }
            case .failure(let failure):
                completionHandler(.failure(.genericError(error: failure)))
            }
        }
    }

    /// List response input items for a stored response.
    /// - Parameters:
    ///   - responseID: Response identifier.
    ///   - completionHandler: Returns input items page.
    public func listResponseInputItems(for responseID: String,
                                       completionHandler: @escaping (Result<ResponseInputItemsList, OpenAIError>) -> Void) {
        let basePath = config.endpointProvider.getPath(api: .responses)
        let request = prepareRequest(
            path: basePath + "/\(escapedPathComponent(responseID))/input_items",
            method: "GET"
        )

        makeRequest(request: request) { result in
            switch result {
            case .success(let success):
                do {
                    let response = try JSONDecoder().decode(ResponseInputItemsList.self, from: success)
                    completionHandler(.success(response))
                } catch {
                    completionHandler(.failure(.decodingError(error: error)))
                }
            case .failure(let failure):
                completionHandler(.failure(.genericError(error: failure)))
            }
        }
    }

    /// Send a Image generation request to the OpenAI API
    /// - Parameters:
    ///   - prompt: The Text Prompt
    ///   - numImages: The number of images to generate, defaults to 1
    ///   - size: The size of the image, defaults to 1024x1024. There are two other options: 512x512 and 256x256
    ///   - user: An optional unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse.
    ///   - completionHandler: Returns an OpenAI Data Model
    public func sendImages(with prompt: String, numImages: Int = 1, size: ImageSize = .size1024, user: String? = nil, completionHandler: @escaping (Result<OpenAI<UrlResult>, OpenAIError>) -> Void) {
        let endpoint = OpenAIEndpointProvider.API.images
        let body = ImageGeneration(prompt: prompt, n: numImages, size: size, user: user)
        let request = prepareRequest(endpoint, body: body)

        makeRequest(request: request) { result in
            switch result {
                case .success(let success):
                    do {
                        let res = try JSONDecoder().decode(OpenAI<UrlResult>.self, from: success)
                        completionHandler(.success(res))
                    } catch {
                        completionHandler(.failure(.decodingError(error: error)))
                    }
                case .failure(let failure):
                    completionHandler(.failure(.genericError(error: failure)))
                }
        }
    }
    
    private func makeRequest(request: URLRequest, completionHandler: @escaping (Result<Data, Error>) -> Void) {
        let session = config.session
        let task = session.dataTask(with: request) { (data, response, error) in
            if let error = error {
                completionHandler(.failure(error))
            } else if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
                completionHandler(.failure(OpenAIError.networkError(code: response.statusCode)))
            } else if let data = data {
                completionHandler(.success(data))
            } else {
                let error = NSError(domain: "OpenAI", code: 6666, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
                completionHandler(.failure(OpenAIError.genericError(error: error)))
            }
        }
        task.resume()
    }
    
    private func prepareRequest<BodyType: Encodable>(_ endpoint: OpenAIEndpointProvider.API, body: BodyType) -> URLRequest {
        let encoder = JSONEncoder()
        let encoded = try? encoder.encode(body)
        return prepareRequest(
            path: config.endpointProvider.getPath(api: endpoint),
            method: config.endpointProvider.getMethod(api: endpoint),
            body: encoded
        )
    }

    private func prepareRequest(path: String, method: String, body: Data? = nil) -> URLRequest {
        var urlComponents = URLComponents(url: URL(string: config.baseURL)!, resolvingAgainstBaseURL: true)
        urlComponents?.path = path
        var request = URLRequest(url: urlComponents!.url!)
        request.httpMethod = method

        config.authorizeRequest(&request)

        request.setValue("application/json", forHTTPHeaderField: "content-type")

        if let body {
            request.httpBody = body
        }

        return request
    }

    private func escapedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func normalizeChatTokenFields(modelName: String, maxTokens: Int?, maxCompletionTokens: Int?) -> (maxTokens: Int?, maxCompletionTokens: Int?) {
        // GPT-5/o-series style models reject `max_tokens` and require `max_completion_tokens`.
        guard maxCompletionTokens == nil, let maxTokens else {
            return (maxTokens, maxCompletionTokens)
        }

        if requiresMaxCompletionTokens(modelName: modelName) {
            return (nil, maxTokens)
        }
        return (maxTokens, nil)
    }

    private func requiresMaxCompletionTokens(modelName: String) -> Bool {
        let lower = modelName.lowercased()
        return lower.hasPrefix("gpt-5") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4")
    }
}

extension OpenAISwift {
    /// Send a Completion to the OpenAI API
    /// - Parameters:
    ///   - prompt: The Text Prompt
    ///   - model: The AI Model to Use. Set to `OpenAIModelType.gpt3(.davinci)` by default which is the most capable model
    ///   - maxTokens: The limit character for the returned response, defaults to 16 as per the API
    ///   - temperature: Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. Defaults to 1
    /// - Returns: Returns an OpenAI Data Model
    @available(*, deprecated, message: "Completions API is legacy. Prefer sendResponse(with:) with /v1/responses.")
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendCompletion(with prompt: String, model: OpenAIModelType = .gpt3(.davinci), maxTokens: Int = 16, temperature: Double = 1) async throws -> OpenAI<TextResult> {
        return try await withCheckedThrowingContinuation { continuation in
            sendCompletion(with: prompt, model: model, maxTokens: maxTokens, temperature: temperature) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Send a Edit request to the OpenAI API
    /// - Parameters:
    ///   - instruction: The Instruction For Example: "Fix the spelling mistake"
    ///   - model: The Model to use, the only support model is `text-davinci-edit-001`
    ///   - input: The Input For Example "My nam is Adam"
    /// - Returns: Returns an OpenAI Data Model
    @available(*, deprecated, message: "Edits API is legacy/deprecated. Prefer sendResponse(with:) with /v1/responses.")
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendEdits(with instruction: String, model: OpenAIModelType = .feature(.davinci), input: String = "") async throws -> OpenAI<TextResult> {
        return try await withCheckedThrowingContinuation { continuation in
            sendEdits(with: instruction, model: model, input: input) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Send a Chat request to the OpenAI API
    /// - Parameters:
    ///   - messages: Array of `ChatMessages`
    ///   - model: The Model to use, the only support model is `gpt-3.5-turbo`
    ///   - user: A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse.
    ///   - temperature: What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or topProbabilityMass but not both.
    ///   - topProbabilityMass: The OpenAI api equivalent of the "top_p" parameter. An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.
    ///   - choices: How many chat completion choices to generate for each input message.
    ///   - stop: Up to 4 sequences where the API will stop generating further tokens.
    ///   - maxTokens: The maximum number of tokens allowed for the generated answer. By default, the number of tokens the model can return will be (4096 - prompt tokens).
    ///   - presencePenalty: Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.
    ///   - frequencyPenalty: Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.
    ///   - logitBias: Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID in the OpenAI Tokenizer—not English words) to an associated bias value from -100 to 100. Values between -1 and 1 should decrease or increase likelihood of selection; values like -100 or 100 should result in a ban or exclusive selection of the relevant token.
    ///   - completionHandler: Returns an OpenAI Data Model
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendChat(with messages: [ChatMessage],
                         model: OpenAIModelType = .chat(.chatgpt),
                         user: String? = nil,
                         temperature: Double? = 1,
                         topProbabilityMass: Double? = 0,
                         choices: Int? = 1,
                         stop: [String]? = nil,
                         maxTokens: Int? = nil,
                         presencePenalty: Double? = 0,
                         frequencyPenalty: Double? = 0,
                         logitBias: [Int: Double]? = nil,
                         tools: [ChatTool]? = nil,
                         toolChoice: ChatToolChoice? = nil,
                         responseFormat: ChatResponseFormat? = nil,
                         maxCompletionTokens: Int? = nil,
                         reasoningEffort: ChatReasoningEffort? = nil,
                         parallelToolCalls: Bool? = nil,
                         store: Bool? = nil,
                         serviceTier: ChatServiceTier? = nil) async throws -> OpenAI<MessageResult> {
        return try await withCheckedThrowingContinuation { continuation in
            sendChat(with: messages,
                     model: model,
                     user: user,
                     temperature: temperature,
                     topProbabilityMass: topProbabilityMass,
                     choices: choices,
                     stop: stop,
                     maxTokens: maxTokens,
                     presencePenalty: presencePenalty,
                     frequencyPenalty: frequencyPenalty,
                     logitBias: logitBias,
                     tools: tools,
                     toolChoice: toolChoice,
                     responseFormat: responseFormat,
                     maxCompletionTokens: maxCompletionTokens,
                     reasoningEffort: reasoningEffort,
                     parallelToolCalls: parallelToolCalls,
                     store: store,
                     serviceTier: serviceTier) { result in
                switch result {
                    case .success: continuation.resume(with: result)
                    case .failure(let failure): continuation.resume(throwing: failure)
                }
            }
        }
    }
    
    
    /// Send a Chat request to the OpenAI API with stream enabled
    /// - Parameters:
    ///   - messages: Array of `ChatMessages`
    ///   - model: The Model to use, the only support model is `gpt-3.5-turbo`
    ///   - user: A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse.
    ///   - temperature: What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or topProbabilityMass but not both.
    ///   - topProbabilityMass: The OpenAI api equivalent of the "top_p" parameter. An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.
    ///   - choices: How many chat completion choices to generate for each input message.
    ///   - stop: Up to 4 sequences where the API will stop generating further tokens.
    ///   - maxTokens: The maximum number of tokens allowed for the generated answer. By default, the number of tokens the model can return will be (4096 - prompt tokens).
    ///   - presencePenalty: Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.
    ///   - frequencyPenalty: Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.
    ///   - logitBias: Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID in the OpenAI Tokenizer—not English words) to an associated bias value from -100 to 100. Values between -1 and 1 should decrease or increase likelihood of selection; values like -100 or 100 should result in a ban or exclusive selection of the relevant token.
    /// - Returns: Returns an OpenAI Data Model
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendStreamingChat(with messages: [ChatMessage],
                                  model: OpenAIModelType = .chat(.chatgpt),
                                  user: String? = nil,
                                  temperature: Double? = 1,
                                  topProbabilityMass: Double? = 0,
                                  choices: Int? = 1,
                                  stop: [String]? = nil,
                                  maxTokens: Int? = nil,
                                  presencePenalty: Double? = 0,
                                  frequencyPenalty: Double? = 0,
                                  logitBias: [Int: Double]? = nil,
                                  tools: [ChatTool]? = nil,
                                  toolChoice: ChatToolChoice? = nil,
                                  responseFormat: ChatResponseFormat? = nil,
                                  maxCompletionTokens: Int? = nil,
                                  reasoningEffort: ChatReasoningEffort? = nil,
                                  parallelToolCalls: Bool? = nil,
                                  store: Bool? = nil,
                                  serviceTier: ChatServiceTier? = nil,
                                  streamOptions: ChatStreamOptions? = nil) -> AsyncStream<Result<OpenAI<StreamMessageResult>, OpenAIError>> {
        return AsyncStream { continuation in
            sendStreamingChat(
                with: messages,
                model: model,
                user: user,
                temperature: temperature,
                topProbabilityMass: topProbabilityMass,
                choices: choices,
                stop: stop,
                maxTokens: maxTokens,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty,
                logitBias: logitBias,
                tools: tools,
                toolChoice: toolChoice,
                responseFormat: responseFormat,
                maxCompletionTokens: maxCompletionTokens,
                reasoningEffort: reasoningEffort,
                parallelToolCalls: parallelToolCalls,
                store: store,
                serviceTier: serviceTier,
                streamOptions: streamOptions,
                onEventReceived: { result in
                    continuation.yield(result)
                }) {
                    continuation.finish()
                }
        }
    }

    /// Send a Embeddings request to the OpenAI API
    /// - Parameters:
    ///   - input: The Input For Example "The food was delicious and the waiter..."
    ///   - model: The Model to use, the only support model is `text-embedding-ada-002`
    ///   - completionHandler: Returns an OpenAI Data Model
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendEmbeddings(with input: String,
                               model: OpenAIModelType = .embedding(.ada)) async throws -> OpenAI<EmbeddingResult> {
        return try await withCheckedThrowingContinuation { continuation in
            sendEmbeddings(with: input) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Send a Moderation request to the OpenAI API
    /// - Parameters:
    ///   - input: The Input For Example "My nam is Adam"
    ///   - model: The Model to use
    /// - Returns: Returns an OpenAI Data Model
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendModerations(with input: String = "", model: OpenAIModelType = .moderation(.latest)) async throws -> OpenAI<ModerationResult> {
        return try await withCheckedThrowingContinuation { continuation in
            sendModerations(with: input, model: model) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Send a Image generation request to the OpenAI API
    /// - Parameters:
    ///   - prompt: The Text Prompt
    ///   - numImages: The number of images to generate, defaults to 1
    ///   - size: The size of the image, defaults to 1024x1024. There are two other options: 512x512 and 256x256
    ///   - user: An optional unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse.
    /// - Returns: Returns an OpenAI Data Model
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendImages(with prompt: String, numImages: Int = 1, size: ImageSize = .size1024, user: String? = nil) async throws -> OpenAI<UrlResult> {
        return try await withCheckedThrowingContinuation { continuation in
            sendImages(with: prompt, numImages: numImages, size: size, user: user) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Send a Responses API request to the OpenAI API
    /// - Parameters:
    ///   - requestBody: The full request payload for /v1/responses
    /// - Returns: A ResponseObject
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendResponse(with requestBody: ResponseRequest) async throws -> ResponseObject {
        return try await withCheckedThrowingContinuation { continuation in
            sendResponse(with: requestBody) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Convenience helper for simple text inputs with Responses API
    /// - Parameters:
    ///   - input: A plain text input
    ///   - model: The model name
    ///   - instructions: Optional high-level instructions
    ///   - previousResponseID: Optional ID for multi-turn chaining
    ///   - store: Optional stateful storage flag
    /// - Returns: A ResponseObject
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendResponse(with input: String,
                             model: OpenAIModelType = .other("gpt-5"),
                             instructions: String? = nil,
                             previousResponseID: String? = nil,
                             store: Bool? = nil) async throws -> ResponseObject {
        return try await withCheckedThrowingContinuation { continuation in
            sendResponse(with: input,
                         model: model,
                         instructions: instructions,
                         previousResponseID: previousResponseID,
                         store: store) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Retrieve a stored response by ID.
    /// - Parameter responseID: Response identifier.
    /// - Returns: A ResponseObject.
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func getResponse(with responseID: String) async throws -> ResponseObject {
        return try await withCheckedThrowingContinuation { continuation in
            getResponse(with: responseID) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Delete a stored response by ID.
    /// - Parameter responseID: Response identifier.
    /// - Returns: Deletion result.
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func deleteResponse(with responseID: String) async throws -> ResponseDeletionResult {
        return try await withCheckedThrowingContinuation { continuation in
            deleteResponse(with: responseID) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// List input items for a stored response.
    /// - Parameter responseID: Response identifier.
    /// - Returns: A paginated response input item list.
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func listResponseInputItems(for responseID: String) async throws -> ResponseInputItemsList {
        return try await withCheckedThrowingContinuation { continuation in
            listResponseInputItems(for: responseID) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Send a streaming Responses API request to the OpenAI API
    /// - Parameter requestBody: The request payload for /v1/responses
    /// - Returns: Stream of response events
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendStreamingResponse(with requestBody: ResponseRequest) -> AsyncStream<Result<ResponseStreamEvent, OpenAIError>> {
        return AsyncStream { continuation in
            sendStreamingResponse(
                with: requestBody,
                onEventReceived: { result in
                    continuation.yield(result)
                },
                onComplete: {
                    continuation.finish()
                }
            )
        }
    }

    /// Collect output text from a Responses API event stream.
    /// - Parameter stream: A stream of response events.
    /// - Returns: Aggregated output text from `response.output_text.*` events.
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func collectOutputText(from stream: AsyncStream<Result<ResponseStreamEvent, OpenAIError>>) async throws -> String {
        var accumulator = ResponseStreamTextAccumulator()
        for await result in stream {
            switch result {
            case .success(let event):
                accumulator.apply(event)
            case .failure(let error):
                throw error
            }
        }
        return accumulator.outputText
    }

    /// Send a streaming Responses API request and return aggregated output text.
    /// - Parameter requestBody: The request payload for /v1/responses.
    /// - Returns: Aggregated output text from `response.output_text.*` events.
    @available(swift 5.5)
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func sendStreamingResponseAndCollectText(with requestBody: ResponseRequest) async throws -> String {
        let stream = sendStreamingResponse(with: requestBody)
        return try await collectOutputText(from: stream)
    }
}
