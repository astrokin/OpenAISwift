import XCTest
@testable import OpenAISwift

final class OpenAISwiftTests: XCTestCase {
    func testResponseRequestEncodingIncludesCoreFields() throws {
        let request = ResponseRequest(
            model: "gpt-5",
            input: .text("Hello"),
            instructions: "You are helpful",
            previousResponseID: "resp_prev",
            store: true,
            text: .init(format: .text),
            toolChoice: .auto
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "gpt-5")
        XCTAssertEqual(json["input"] as? String, "Hello")
        XCTAssertEqual(json["instructions"] as? String, "You are helpful")
        XCTAssertEqual(json["previous_response_id"] as? String, "resp_prev")
        XCTAssertEqual(json["store"] as? Bool, true)
        XCTAssertEqual(json["tool_choice"] as? String, "auto")
        XCTAssertNotNil(json["text"])
    }

    func testChatConversationEncodingIncludesToolsAndStructuredOutput() throws {
        let tool = ChatTool(function: .init(
            name: "get_weather",
            description: "weather",
            parameters: ["type": .string("object")],
            strict: true
        ))

        let chat = ChatConversation(
            user: "u1",
            messages: [.init(role: .user, content: "Hi")],
            model: "gpt-4o",
            temperature: 0.2,
            topProbabilityMass: 1,
            choices: 1,
            stop: nil,
            maxTokens: 100,
            presencePenalty: 0,
            frequencyPenalty: 0,
            logitBias: nil,
            stream: false,
            tools: [tool],
            toolChoice: .function(name: "get_weather"),
            responseFormat: .jsonSchema(name: "obj", schema: ["type": .string("object")]),
            maxCompletionTokens: 200,
            reasoningEffort: .medium,
            parallelToolCalls: true,
            store: true,
            serviceTier: .auto,
            streamOptions: .init(includeUsage: true)
        )

        let data = try JSONEncoder().encode(chat)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["tools"])
        XCTAssertNotNil(json["tool_choice"])
        XCTAssertNotNil(json["response_format"])
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 200)
        XCTAssertEqual(json["parallel_tool_calls"] as? Bool, true)
        XCTAssertEqual(json["store"] as? Bool, true)
    }

    func testResponseObjectOutputTextAggregation() throws {
        let raw = """
        {
          "id": "resp_1",
          "object": "response",
          "created_at": 1,
          "model": "gpt-5",
          "status": "completed",
          "output": [
            {
              "id": "msg_1",
              "type": "message",
              "role": "assistant",
              "status": "completed",
              "content": [
                { "type": "output_text", "text": "Hello " },
                { "type": "output_text", "text": "world!" }
              ]
            }
          ]
        }
        """
        let data = raw.data(using: .utf8)!
        let response = try JSONDecoder().decode(ResponseObject.self, from: data)
        XCTAssertEqual(response.outputText, "Hello world!")
    }

    func testChatMessageToolCallRoundTrip() throws {
        let message = ChatMessage(
            role: .assistant,
            content: nil,
            toolCalls: [
                .init(
                    id: "call_1",
                    function: .init(name: "get_weather", arguments: "{\"city\":\"Paris\"}")
                )
            ],
            toolCallID: nil
        )

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: encoded)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.toolCalls?.first?.function.name, "get_weather")
    }

    func testResponseStreamEventDecodesFunctionArgumentsDelta() throws {
        let raw = """
        {
          "type": "response.function_call_arguments.delta",
          "sequence_number": 7,
          "item_id": "fc_1",
          "output_index": 0,
          "delta": "{\\"city\\":\\"Pa",
          "arguments": "{\\"city\\":\\"Pa"
        }
        """

        let data = try XCTUnwrap(raw.data(using: .utf8))
        let event = try JSONDecoder().decode(ResponseStreamEvent.self, from: data)
        XCTAssertEqual(event.type, "response.function_call_arguments.delta")
        XCTAssertEqual(event.sequenceNumber, 7)
        XCTAssertEqual(event.itemID, "fc_1")
        XCTAssertEqual(event.outputIndex, 0)
        XCTAssertEqual(event.arguments, "{\"city\":\"Pa")
    }

    func testResponseInputItemsListDecoding() throws {
        let raw = """
        {
          "object": "list",
          "data": [
            { "type": "message", "role": "user", "content": "Hi" },
            { "type": "function_call_output", "call_id": "call_1", "output": "{\\"ok\\":true}" }
          ],
          "first_id": "item_1",
          "last_id": "item_2",
          "has_more": false
        }
        """

        let data = try XCTUnwrap(raw.data(using: .utf8))
        let page = try JSONDecoder().decode(ResponseInputItemsList.self, from: data)
        XCTAssertEqual(page.object, "list")
        XCTAssertEqual(page.hasMore, false)
        XCTAssertEqual(page.data?.count, 2)
    }

    func testResponseStreamEventDecodesOutputTextDone() throws {
        let raw = """
        {
          "type": "response.output_text.done",
          "sequence_number": 12,
          "item_id": "msg_1",
          "output_index": 0,
          "content_index": 0,
          "text": "Hello world"
        }
        """

        let data = try XCTUnwrap(raw.data(using: .utf8))
        let event = try JSONDecoder().decode(ResponseStreamEvent.self, from: data)
        XCTAssertEqual(event.type, "response.output_text.done")
        XCTAssertEqual(event.outputTextDone, "Hello world")
        XCTAssertEqual(event.itemID, "msg_1")
    }

    func testResponseStreamTextAccumulator() throws {
        let d1 = try JSONDecoder().decode(
            ResponseStreamEvent.self,
            from: Data(#"{"type":"response.output_text.delta","delta":"Hello "}"#.utf8)
        )
        let d2 = try JSONDecoder().decode(
            ResponseStreamEvent.self,
            from: Data(#"{"type":"response.output_text.delta","delta":"world"}"#.utf8)
        )
        let done = try JSONDecoder().decode(
            ResponseStreamEvent.self,
            from: Data(#"{"type":"response.output_text.done","text":"Hello world!"}"#.utf8)
        )

        var acc = ResponseStreamTextAccumulator()
        acc.apply(d1)
        acc.apply(d2)
        XCTAssertEqual(acc.outputText, "Hello world")
        acc.apply(done)
        XCTAssertEqual(acc.outputText, "Hello world!")
    }
}
