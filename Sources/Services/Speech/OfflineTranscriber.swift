import Foundation
import Speech

enum OfflineTranscriberError: LocalizedError {
    case notAuthorized, recognizerUnavailable
    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Autorizzazione al riconoscimento vocale negata."
        case .recognizerUnavailable: return "Riconoscitore offline non disponibile per la lingua selezionata."
        }
    }
}

final class OfflineTranscriber {
    func transcribeAudioFile(
        _ audioURL: URL,
        locale: Locale = Locale(identifier: "it-IT"),
        completion: @escaping (Result<[SubtitleSegment], Error>) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return completion(.failure(OfflineTranscriberError.notAuthorized)) }

            guard let recognizer = SFSpeechRecognizer(locale: locale) else {
                return completion(.failure(OfflineTranscriberError.recognizerUnavailable))
            }
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.requiresOnDeviceRecognition = true    // <— offline

            recognizer.recognitionTask(with: request) { result, error in
                if let error = error { return completion(.failure(error)) }
                guard let result = result, result.isFinal else { return }

                let segs: [SubtitleSegment] = result.bestTranscription.segments.map {
                    SubtitleSegment(
                        start: $0.timestamp,
                        end: $0.timestamp + $0.duration,
                        text: $0.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                completion(.success(segs))
            }
        }
    }
}
