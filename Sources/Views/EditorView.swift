import SwiftUI
import AVKit
import UniformTypeIdentifiers

@available(iOS 16.0, *)
struct EditorView: View {
    let urls: [URL]

    @State private var player = AVPlayer()
    @State private var currentTime: Double = 0
    @State private var segments: [SubtitleSegment] = []
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var errorMsg: String?
    @State private var observingToken: Any?

    var body: some View {
        VStack(spacing: 12) {
            Text(status)
                .font(.footnote)

            List {
                Section("Clip selezionate") {
                    ForEach(urls, id: \.self) { url in
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                    }
                }

                if !captions.isEmpty {
                    Section("Sottotitoli") {
                        Text("Righe generate: \(captions.count)")
                        ForEach(Array(captions.prefix(3))) { caption in
                            Text("• \(caption.text)")
                                .lineLimit(2)
                        }
                    }
                }
            }
            .frame(height: 260)

            HStack {
                Button("Trascrivi offline (clip 1)") {
                    Task { await transcribeFirstClip() }
                }
                .buttonStyle(.borderedProminent)

                if let url = exportURL {
                    ShareLink(item: url) { Label("Condividi SRT", systemImage: "square.and.arrow.up") }
                }
            }
            .padding(.vertical, 8)

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Condividi export", systemImage: "square.and.arrow.up")
                }
                .padding(.top, 8)
            } else if let first = urls.first {
                ShareLink(item: first) {
                    Label("Condividi video", systemImage: "square.and.arrow.up")
                }
                .padding(.top, 8)
            }
        }
    }

    @MainActor
    private func transcribeFirstClip() async {
        guard let first = urls.first else { return }
        status = "Estrazione audio…"
        do {
            let audio = try await AudioExtractor.extractM4A(from: first)
            status = "Trascrizione offline…"
            let newCaptions = try await SpeechRecognizer.transcribeToCaptions(audioURL: audio)
            captions = newCaptions
            status = "Trascrizione completata (\(newCaptions.count) righe)"
        } catch {
            status = "Errore trascrizione: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func mergeAndExport() async {
        guard !urls.isEmpty else { return }
        status = "Unione clip…"
        let assets = urls.map { AVURLAsset(url: $0) }
        do {
            let composition = try VideoEditor.merge(clips: assets)
            status = "Export con sottotitoli…"
            let naturalSize = assets.first?.tracks(withMediaType: .video).first?.naturalSize
                ?? CGSize(width: 1080, height: 1920)
            VideoEditor.exportWithSubtitles(asset: composition, renderSize: naturalSize, captions: captions) { url in
                Task { @MainActor in
                    if let url {
                        exportURL = url
                        status = "Completato"
                    } else {
                        status = "Errore export"
                    }
                }
            }
        }
    }

    func addEmptyRow() {
        let start = (segments.last?.end ?? 0)
        segments.append(SubtitleSegment(start: start, end: start + 2, text: "Nuovo sottotitolo"))
    }

    func exportSRT() throws -> URL {
        let srt = segments.sorted { $0.start < $1.start }.toSRT()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("captions.srt")
        try srt.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// Campo “tempo in secondi”
@available(iOS 16.0, *)
struct TimeField: View {
    let title: String
    @Binding var seconds: Double

    private let fmt: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
        return f
    }()

    var body: some View {
        HStack {
            Text(title)
            TextField("0.0", value: $seconds, formatter: fmt)
                .keyboardType(.decimalPad)
                .frame(width: 80)
        }
    }
}
