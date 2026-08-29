import Foundation

public final class GeminiSuggestionEngine: Sendable {
    public init() {}

    public func generateSuggestions(
        currentPrompt: String,
        apiKey: String,
        modelName: String = "gemini-2.5-flash"
    ) async -> GeminiSuggestions {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanKey.isEmpty {
            return fallbackSuggestions(for: currentPrompt)
        }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(cleanKey)"
        guard let url = URL(string: endpoint) else {
            return fallbackSuggestions(for: currentPrompt)
        }

        let systemInstruction = """
        You are an elite music producer and DJ creating next-track recommendations.
        Given a text prompt describing a currently playing music track, generate exactly 3 concise, evocative prompts (under 25 words each) for the next track:
        1. 'similar': A natural, atmospheric continuation with compatible key, tempo, and vibe.
        2. 'fun': A lively, vibrant, or upbeat spin on the current style.
        3. 'wild': A dramatic, unexpected genre twist or surreal experimental departure.

        Return ONLY a raw JSON object with keys "similar", "fun", and "wild".
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "text": "Current playing track prompt:\n\"\(currentPrompt)\"\n\nSuggest the next 3 tracks in JSON format:"
                        ]
                    ]
                ]
            ],
            "systemInstruction": [
                "parts": [
                    ["text": systemInstruction]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.9,
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "similar": ["type": "STRING", "description": "Continuation prompt matching the vibe"],
                        "fun": ["type": "STRING", "description": "Lively or upbeat spin on the genre"],
                        "wild": ["type": "STRING", "description": "Wild, experimental genre clash"]
                    ],
                    "required": ["similar", "fun", "wild"]
                ]
            ]
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if let errorStr = String(data: data, encoding: .utf8) {
                    print("⚠️ Gemini API error response: \(errorStr)")
                }
                return fallbackSuggestions(for: currentPrompt)
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {

                let cleanedText = text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let parsedData = cleanedText.data(using: .utf8),
                   let suggestions = try? JSONDecoder().decode(GeminiSuggestions.self, from: parsedData) {
                    return suggestions
                }
            }
        } catch {
            print("⚠️ Gemini API error: \(error.localizedDescription)")
        }

        return fallbackSuggestions(for: currentPrompt)
    }

    public func fallbackSuggestions(for prompt: String) -> GeminiSuggestions {
        let base = prompt.isEmpty ? "Ambient electronic music" : prompt
        return GeminiSuggestions(
            similar: "Smooth continuation of \(base), dreamy textures and delicate reverb",
            fun: "Upbeat groovy remix of \(base) with punchy bassline and warm syncopation",
            wild: "Cinematic cyberpunk orchestral explosion with distorted synth leads and heavy 808s"
        )
    }
}
