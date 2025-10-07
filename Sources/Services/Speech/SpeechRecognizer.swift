import Foundation
import Speech
import AVFoundation

public struct Caption: Identifiable, Hashable {
    public let id = UUID()
    public var text: String
    public var start: CMTime
    public var duration: CMTime
}

final class SpeechRecognizer {

    enum SRSError: Error { case notAuthorized, recognizerUnavailable, failed }

    /// Trascrive un file audio locale in ITA **on-device** e ritorna una lista di Caption (raggruppati per frasi).
    static func transcribeToCaptions(audioURL: URL,
                                     localeId: String = "it-IT",
                                     lineMaxChars: Int = 42,
                                     maxLineDuration: Double = 3.0,
                                     newLineGap: Double = 0.6) async throws -> [Caption] {

        let auth: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard auth == .authorized else { throw SRSError.notAuthorized }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)),
              recognizer.isAvailable else { throw SRSError.recognizerUnavailable }

        let request = SFSpeechURLRecognitionRequest(audioURL)
        request.requiresOnDeviceRecognition = true // forza OFFLINE

        let asset = AVURLAsset(url: audioURL)
        let total = asset.duration

        let segments: [SFTranscriptionSegment] = try await withCheckedThrowingContinuation { cont in
            var latest: [SFTranscriptionSegment] = []
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error { cont.resume(throwing: error); return }
                if let r = result {
                    latest = r.bestTranscription.segments
                    if r.isFinal { cont.resume(returning: latest) }
                }
            }
            // Se serve, cancella il warning "unused variable":
            _ = task
        }

        guard !segments.isEmpty else { throw SRSError.failed }

        // Converte i segmenti parola-per-parola in righe (caption) con regole semplici:
        // - nuova riga se c'è una pausa > newLineGap
        // - o se la riga supera lineMaxChars
        // - o se la riga supera maxLineDuration
        var captions: [Caption] = []
        var currentText = ""
        var currentStart = CMTime.zero
        var lastEnd = CMTime.zero

        func flush(until end: CMTime) {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let dur = CMTimeSubtract(end, currentStart)
            captions.append(Caption(text: trimmed, start: currentStart, duration: dur))
            currentText = ""
        }

        for (idx, seg) in segments.enumerated() {
            let word = seg.substring
            let start = CMTime(seconds: seg.timestamp, preferredTimescale: 600)
            let nextStartSeconds: Double = {
                if idx + 1 < segments.count { return segments[idx+1].timestamp }
                else { return CMTimeGetSeconds(total) }
            }()
            let end = CMTime(seconds: nextStartSeconds, preferredTimescale: 600)

            // Se linea vuota, fissa lo start
            if currentText.isEmpty { currentStart = start }

            let gap = CMTimeGetSeconds(CMTimeSubtract(start, lastEnd))
            let currentDuration = CMTimeGetSeconds(CMTimeSubtract(end, currentStart))
            let wouldBeText = (currentText.isEmpty ? word : currentText + " " + word)

            if gap > newLineGap
                || wouldBeText.count > lineMaxChars
                || currentDuration > maxLineDuration {
                // chiudi riga precedente alla fine del segmento precedente
                flush(until: lastEnd == .zero ? start : lastEnd)
                currentText = word
                currentStart = start
            } else {
                currentText = wouldBeText
            }
            lastEnd = end
        }
        flush(until: lastEnd == .zero ? total : lastEnd)

        return captions
    }
}
