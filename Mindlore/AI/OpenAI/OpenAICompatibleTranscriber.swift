import Foundation

// POST /audio/transcriptions. OpenAI doesn't accept CAF, so anything that isn't already m4a is
// converted first. Long recordings are split by AudioChunker before they get here.
struct OpenAICompatibleTranscriber: Transcriber {
    nonisolated static let requestTimeout: TimeInterval = 600
    nonisolated static let maxUploadBytes = 25 * 1024 * 1024
    // OpenAI's documented limit is size, but requests over about 1400 seconds fail in practice.
    nonisolated static let chunkTargetSeconds: Double = 20 * 60

    nonisolated let baseURL: URL
    nonisolated let apiKey: String
    nonisolated let model: String
    nonisolated let http: any HTTPClient
    nonisolated let prompt: String?

    init(baseURL: URL, apiKey: String, model: String, http: any HTTPClient, prompt: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.http = http
        self.prompt = prompt
    }

    @concurrent
    nonisolated func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        let audio = try Self.m4aData(for: audioFileURL)
        var form = MultipartFormData()
        form.addField("model", model)
        form.addField("response_format", "json")
        if let language = locale.language.languageCode?.identifier {
            form.addField("language", language)
        }
        if let prompt, !prompt.isEmpty {
            form.addField("prompt", prompt)
        }
        form.addFile("file", filename: "audio.m4a", mimeType: "audio/m4a", contents: audio)

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")

        let response = try await http.send(request, body: form.finalized())
        guard (200..<300).contains(response.status) else { throw OpenAIErrorMapper.map(response) }
        struct Transcription: Decodable { let text: String }
        guard let result = try? JSONDecoder().decode(Transcription.self, from: response.data) else { throw AIError.invalidResponse }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.noSpeechDetected }
        return text
    }

    // Finds the uploaded file part in a multipart body and checks it is an MPEG-4 container.
    nonisolated static func isM4AUpload(_ body: Data) -> Bool {
        guard let marker = body.range(of: Data("Content-Type: audio/m4a\r\n\r\n".utf8)) else { return false }
        return isM4A(body.subdata(in: marker.upperBound..<body.endIndex))
    }

    nonisolated static func isM4A(_ data: Data) -> Bool {
        data.count >= 8 && data.dropFirst(4).prefix(4) == Data("ftyp".utf8)
    }

    nonisolated static func m4aData(for url: URL) throws -> Data {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AIError.invalidResponse
        }
        if isM4A(data) { return data }
        do {
            return try AudioConverter.convertToAAC(url).data
        } catch {
            throw TranscriptionError.analysisFailed("conversion")
        }
    }
}
