import Foundation
import AVFoundation

enum AudioExtractor {
    enum Error: Swift.Error { case noAudioTrack, exportFailed }

    /// Estrae l'audio in un file .m4a (AAC) a partire da un video.
    static func extractM4A(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw Error.noAudioTrack }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Error.exportFailed
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: outURL)
        exporter.outputURL = outURL
        exporter.outputFileType = .m4a
        let duration = try await asset.load(.duration)
        exporter.timeRange = CMTimeRange(start: .zero, duration: duration)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }

        guard exporter.status == .completed else { throw Error.exportFailed }
        return outURL
    }
}
