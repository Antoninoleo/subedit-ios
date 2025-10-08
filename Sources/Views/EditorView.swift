import SwiftUI
import AVFoundation

@available(iOS 16.0, *)
struct EditorView: View {
    let urls: [URL]
    @State private var status: String = "Pronto"
    @State private var captions: [Caption] = []
    @State private var exportURL: URL?

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

                Button("Unisci & Export con sottotitoli") {
                    Task { await mergeAndExport() }
                }
                .disabled(captions.isEmpty || urls.isEmpty)
            }

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
        .padding()
        .navigationTitle("Editor")
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
        } catch {
            status = "Errore unione: \(error.localizedDescription)"
        }
    }
}
