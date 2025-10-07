import SwiftUI
import PhotosUI

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var urls: [URL]

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 0
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        init(_ parent: VideoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.urls.removeAll()
            let group = DispatchGroup()
            for r in results {
                group.enter()
                r.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                    if let url = url {
                        let dst = FileManager.default.temporaryDirectory
                          .appendingPathComponent(UUID().uuidString + ".mov")
                        try? FileManager.default.copyItem(at: url, to: dst)
                        DispatchQueue.main.async { self.parent.urls.append(dst) }
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { picker.dismiss(animated: true) }
        }
    }
}
