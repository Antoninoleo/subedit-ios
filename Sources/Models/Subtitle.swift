import Foundation
import SwiftUI

public struct SubtitleSegment: Identifiable, Hashable, Codable, Sendable {
    public var id = UUID()
    public var start: Double   // secondi
    public var end: Double
    public var text: String
    public var animation: CaptionAnimation = .fade

    public var duration: Double { max(0, end - start) }
}

public enum CaptionAnimation: String, CaseIterable, Codable, Hashable, Sendable {
    case fade, slideUp, pop
}

public extension CaptionAnimation {
    var transition: AnyTransition {
        switch self {
        case .fade:    return .opacity
        case .slideUp: return .move(edge: .bottom).combined(with: .opacity)
        case .pop:     return .scale.combined(with: .opacity)
        }
    }
}

// MARK: - SRT
private func srtTime(_ t: Double) -> String {
    let ms = Int(round(t * 1000))
    let h = ms / 3_600_000
    let m = (ms % 3_600_000) / 60_000
    let s = (ms % 60_000) / 1000
    let mm = ms % 1000
    return String(format: "%02d:%02d:%02d,%03d", h, m, s, mm)
}

extension Array where Element == SubtitleSegment {
    public func toSRT() -> String {
        let sorted = self.sorted { $0.start < $1.start }
        return sorted.enumerated().map { (i, seg) in
            """
            \(i + 1)
            \(srtTime(seg.start)) --> \(srtTime(seg.end))
            \(seg.text)

            """
        }.joined()
    }

    public static func fromSRT(_ s: String) -> [SubtitleSegment] {
        var out: [SubtitleSegment] = []
        let blocks = s.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        let timeRE = try! NSRegularExpression(
            pattern: #"(\d{2}):(\d{2}):(\d{2}),(\d{3})\s+-->\s+(\d{2}):(\d{2}):(\d{2}),(\d{3})"#
        )

        func parse(_ h:Int,_ m:Int,_ s:Int,_ ms:Int) -> Double {
            Double(h*3600 + m*60 + s) + Double(ms)/1000.0
        }

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count >= 2 else { continue }
            let timeLine = String(lines[1])
            if let m = timeRE.firstMatch(in: timeLine, options: [], range: NSRange(location: 0, length: timeLine.utf16.count)) {
                func g(_ i:Int) -> Int {
                    Int((timeLine as NSString).substring(with: m.range(at: i))) ?? 0
                }
                let start = parse(g(1), g(2), g(3), g(4))
                let end   = parse(g(5), g(6), g(7), g(8))
                let text  = lines.dropFirst(2).joined(separator: "\n")
                out.append(SubtitleSegment(start: start, end: end, text: text))
            }
        }
        return out
    }
}
