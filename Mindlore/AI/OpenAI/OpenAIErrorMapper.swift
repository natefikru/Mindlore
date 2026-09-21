import Foundation

// Reads only the code, type, and param from an OpenAI-style error body. The message is ignored
// because it can quote the request, which may contain entry text.
nonisolated enum OpenAIErrorMapper {
    struct Details: Equatable {
        let code: String?
        let type: String?
        let param: String?
    }

    static func details(from data: Data) -> Details {
        struct Envelope: Decodable {
            struct Body: Decodable {
                let code: String?
                let type: String?
                let param: String?
            }
            let error: Body?
        }
        let body = (try? JSONDecoder().decode(Envelope.self, from: data))?.error
        return Details(code: body?.code, type: body?.type, param: body?.param)
    }

    static func map(_ response: HTTPResponse) -> AIError {
        let details = details(from: response.data)
        switch response.status {
        case 401:
            return .invalidKey
        case 403:
            return .permissionDenied
        case 413:
            return .requestTooLarge
        case 429:
            if details.code == "insufficient_quota" || details.type == "insufficient_quota" {
                return .quotaExceeded
            }
            return .rateLimited(retryAfter: response.header("retry-after").flatMap(TimeInterval.init))
        case 400 where details.code == "context_length_exceeded":
            return .contextTooLong
        case 500...599:
            return .serverError(status: response.status)
        default:
            return .badRequest(code: details.code ?? "http_\(response.status)")
        }
    }

    // The other 400 worth one more try: the server takes Chat Completions but not streaming, or
    // not stream_options. Either way the answer is still there without the flags.
    static func rejectsStreaming(_ response: HTTPResponse) -> Bool {
        guard response.status == 400 else { return false }
        let details = details(from: response.data)
        if details.param == "stream" || details.param == "stream_options" { return true }
        return (details.code ?? "").contains("stream")
    }

    // The one 400 worth retrying in JSON mode: the server doesn't support strict schemas.
    static func rejectsResponseFormat(_ response: HTTPResponse) -> Bool {
        guard response.status == 400 else { return false }
        let details = details(from: response.data)
        if details.param == "response_format" { return true }
        let code = details.code ?? ""
        return code.contains("response_format") || code.contains("json_schema")
    }
}
