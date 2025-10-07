import Foundation
import AVFoundation
import UIKit

enum VideoEditor {
    enum Error: Swift.Error { case videoTrackMissing, exportFailed }

    static func merge(clips: [AVAsset], includeOriginalAudio: Bool = true) throws -> AVMutableComposition {
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video,
                                                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Error.videoTrackMissing
        }
        var cursor = CMTime.zero

        for asset in clips {
            if let vt = asset.tracks(withMediaType: .video).first {
                try vTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: vt, at: cursor)
            }
            if includeOriginalAudio,
               let at = asset.tracks(withMediaType: .audio).first,
               let aTrack = comp.addMutableTrack(withMediaType: .audio,
                                                 preferredTrackID: kCMPersistentTrackID_Invalid) {
                try aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: at, at: cursor)
            }
            cursor = cursor + asset.duration
        }
        return comp
    }

    static func exportWithSubtitles(asset: AVAsset,
                                    renderSize: CGSize,
                                    captions: [Caption],
                                    completion: @escaping (URL?) -> Void) {
        let composition = AVMutableComposition()
        do {
            try composition.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: asset, at: .zero)
        } catch {
            completion(nil)
            return
        }

        // Impostiamo la video composition (30fps)
        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = renderSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)

        // Layers: video + overlay
        let parent = CALayer()
        let videoLayer = CALayer()
        parent.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = parent.frame
        parent.addSublayer(videoLayer)

        // Semplice stile sottotitoli (bianco con ombra) in alto; puoi cambiare y
        for cap in captions {
            let tl = CATextLayer()
            tl.string = cap.text
            tl.fontSize = max(28, min(renderSize.width * 0.04, 48))
            tl.alignmentMode = .center
            tl.isWrapped = true
            tl.foregroundColor = UIColor.white.cgColor
            tl.shadowOpacity = 0.9
            tl.shadowRadius = 3.0
            tl.shadowOffset = CGSize(width: 0, height: 2)
            let margin: CGFloat = 32
            tl.frame = CGRect(x: margin, y: margin, width: renderSize.width - margin*2, height: renderSize.height*0.25)
            tl.opacity = 0

            let begin = CMTimeGetSeconds(cap.start)
            let end = CMTimeGetSeconds(cap.start + cap.duration)

            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0; fadeIn.toValue = 1
            fadeIn.beginTime = begin
            fadeIn.duration = 0.2

            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1; fadeOut.toValue = 0
            fadeOut.beginTime = end
            fadeOut.duration = 0.2

            tl.add(fadeIn, forKey: "in-\(begin)")
            tl.add(fadeOut, forKey: "out-\(end)")
            parent.addSublayer(tl)
        }

        // Istruzioni base (un'unica traccia video)
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        if let vt = composition.tracks(withMediaType: .video).first {
            let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
            instr.layerInstructions = [layerInstr]
        }
        videoComp.instructions = [instr]
        videoComp.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)

        // Export
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil); return
        }
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)
        exporter.outputURL = outURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComp

        exporter.exportAsynchronously {
            completion(exporter.status == .completed ? outURL : nil)
        }
    }
}
