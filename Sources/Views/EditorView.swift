import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers

@MainActor
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
        VStack {
            videoPreview
            commandBar
            segmentList
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText]) { result in
            switch result {
            case .success(let url):
                if let data = try? Data(contentsOf: url),
                   let s = String(data: data, encoding: .utf8) {
                    segments = [SubtitleSegment].fromSRT(s)
                }
            case .failure(let err):
                errorMsg = err.localizedDescription
            }
        }
        .alert("Errore", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMsg ?? "") }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Aggiungi riga") { addEmptyRow() }
                    Button("Ordina per tempo") { segments.sort { $0.start < $1.start } }
                    Button("Pulisci") { segments.removeAll() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Helpers
    var activeCaption: SubtitleSegment? {
        segments.first(where: { $0.start <= currentTime && currentTime <= $0.end })
    }

    @ViewBuilder
    private var videoPreview: some View {
        ZStack(alignment: .bottom) {
            VideoPlayer(player: player)
                .frame(height: 280)
                .onAppear { setupPlayer() }
                .onDisappear {
                    if let token = observingToken {
                        player.removeTimeObserver(token)
                        observingToken = nil
                    }
                }

            if let cap = activeCaption {
                Text(cap.text)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 24)
                    .transition(cap.animation.transition)
                    .id(cap.id)
            }
        }
    }

    @ViewBuilder
    private var commandBar: some View {
        HStack(spacing: 12) {
            Button { showImporter = true } label: {
                Label("Importa SRT", systemImage: "tray.and.arrow.down")
            }

            Button {
                do {
                    exportURL = try exportSRT()
                } catch {
                    errorMsg = error.localizedDescription
                }
            } label: {
                Label("Esporta SRT", systemImage: "arrow.up.doc")
            }

            if let url = exportURL {
                ShareLink(item: url) {
                    Label("Condividi SRT", systemImage: "square.and.arrow.up")
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var segmentList: some View {
        List {
            ForEach($segments) { $seg in
                SubtitleSegmentRow(seg: $seg)
            }
            .onDelete { segments.remove(atOffsets: $0) }
        }
    }

    func setupPlayer() {
        if let u = urls.first {
            if let token = observingToken {
                player.removeTimeObserver(token)
                observingToken = nil
            }
            player.replaceCurrentItem(with: AVPlayerItem(url: u))
            let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
            observingToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                currentTime = time.seconds
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
@MainActor
struct TimeField: View {
    let title: String
    @Binding var seconds: Double

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
        return f
    }()

    var body: some View {
        HStack {
            Text(title)
            TextField("0.0", value: $seconds, formatter: Self.formatter)
                .keyboardType(.decimalPad)
                .frame(width: 80)
        }
    }
}

@MainActor
private struct SubtitleSegmentRow: View {
    @Binding var seg: SubtitleSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Testo", text: $seg.text, axis: .vertical)
            HStack {
                TimeField(title: "Start", seconds: $seg.start)
                TimeField(title: "End", seconds: $seg.end)
                Picker("", selection: $seg.animation) {
                    ForEach(CaptionAnimation.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
