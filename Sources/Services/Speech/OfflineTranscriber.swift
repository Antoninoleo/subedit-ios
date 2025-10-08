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
    private var recognitionTask: SFSpeechRecognitionTask?

    func transcribeAudioFile(
        _ audioURL: URL,
        locale: Locale = Locale(identifier: "it-IT"),
        completion: @escaping (Result<[SubtitleSegment], Error>) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            let deliver: (Result<[SubtitleSegment], Error>) -> Void = { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }

            guard status == .authorized else { return deliver(.failure(OfflineTranscriberError.notAuthorized)) }

            guard let recognizer = SFSpeechRecognizer(locale: locale) else {
                return deliver(.failure(OfflineTranscriberError.recognizerUnavailable))
            }
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.requiresOnDeviceRecognition = true    // <— offline

            self.recognitionTask?.cancel()
            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                if let error = error {
                    self.recognitionTask = nil
                    return deliver(.failure(error))
                }
                guard let result = result, result.isFinal else { return }

                let segs: [SubtitleSegment] = result.bestTranscription.segments.map {
                    SubtitleSegment(
                        start: $0.timestamp,
                        end: $0.timestamp + $0.duration,
                        text: $0.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                self.recognitionTask = nil
                deliver(.success(segs))
            }
        }
    }
}
