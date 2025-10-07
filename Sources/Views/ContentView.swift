import SwiftUI

struct ContentView: View {
    @State private var showPicker = false
    @State private var selectedURLs: [URL] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Button("Seleziona clip video") { showPicker = true }
                if !selectedURLs.isEmpty {
                    Text("Clip selezionate: \(selectedURLs.count)")
                    NavigationLink("Apri Editor") {
                        EditorView(urls: selectedURLs)
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("SubEdit")
            .sheet(isPresented: $showPicker) {
                VideoPicker(urls: $selectedURLs)
            }
        }
    }
}