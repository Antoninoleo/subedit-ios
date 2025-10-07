import SwiftUI
import AVFoundation

struct EditorView: View {
    let urls: [URL]
    @State private var status: String = "Pronto"
    @State private var captions: [Caption] = []
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 12) {
            Text(status).font(.footnote)

            List {
                Section("Clip selezionate") {
                    ForEach(urls, id: \.self) { url in
                        Text(url.lastPathComponent).lineLimit(1)
                    }
                }
                if !captions.isEmpty {
                    Section("Sottotitoli") {
                        Text("Righe generate: \(captions.count)")
                        // Anteprima prime 3 righe
                        ForEach(Array(captions.prefix(3))) { c in
                            Text("• \(c.text)")
                                .lineLimit(2)
                        }
                    }
                }
            }.frame(height: 260)

            HStack {
                Button("Trascrivi offline (clip 1)") {
                    Task { await transcribeFirstClip() }
                }.buttonStyle(.borderedProminent)

                Button("Unisci & Export con sottotitoli") {
                    Task { await mergeAndExport() }
                }
                .disabled(captions.isEmpty && urls.count == 0)
            }

            if let url = exportURL {
                ShareLink("Condividi video", item: url).padding(.top, 8)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Editor")
    }

    private func transcribeFirstClip() async {
        guard let first = urls.first else { return }
        status = "Estrazione audio…"
        do {
            let audio = try await AudioExtractor.extractM4A(from: first)
            status = "Trascrizione offline…"
            let caps = try await SpeechRecognizer.transcribeToCaptions(audioURL: audio)
            await MainActor.run {
                self.captions = caps
                self.status = "Trascrizione completata (\(caps.count) righe)"
            }
        } catch {
            await MainActor.run { self.status = "Errore trascrizione: \(error.localizedDescription)" }
        }
    }

    private func mergeAndExport() async {
        status = "Unione clip…"
        let assets = urls.map { AVURLAsset(url: $0) }
        do {
            let comp = try VideoEditor.merge(clips: assets)
            status = "Export con sottotitoli…"
            let natural = assets.first?.tracks(withMediaType: .video).first?.naturalSize
                ?? CGSize(width: 1080, height: 1920)
            VideoEditor.exportWithSubtitles(asset: comp, renderSize: natural, captions: captions) { url in
                Task { @MainActor in
                    if let url = url {
                        self.exportURL = url
                        self.status = "Completato"
                    } else {
                        self.status = "Errore export"
                    }
                }
            }
        } catch {
            status = "Errore unione: \(error.localizedDescription)"
        }
    }
}
