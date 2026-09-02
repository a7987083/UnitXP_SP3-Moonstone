import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Import a local copy. Some Files providers return read-only URLs when
        // opened in-place, which looked selectable but never produced a usable file.
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        controller.allowsMultipleSelection = false
        controller.shouldShowFileExtensions = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            DispatchQueue.main.async { self.onPick(url) }
        }
    }
}
