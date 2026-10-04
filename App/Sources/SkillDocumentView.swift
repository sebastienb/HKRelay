import Foundation
import SwiftUI
import UIKit

struct BundledSkill: Sendable {
    let title: String
    let summary: String
    let bundleSubdirectory: String

    static let restAPI = BundledSkill(
        title: "HKRelay REST API",
        summary: "Teaches AI agents to call the local REST API directly.",
        bundleSubdirectory: "hkrelay-api"
    )

    static let cli = BundledSkill(
        title: "HKRelay CLI",
        summary: "Teaches AI agents to use the local hkrelay command-line tool.",
        bundleSubdirectory: "hkrelay-cli"
    )

    func load() throws -> String {
        guard let url = Bundle.main.url(
            forResource: "SKILL",
            withExtension: "md",
            subdirectory: bundleSubdirectory
        ) else {
            throw SkillDocumentError.missingResource
        }

        return try String(contentsOf: url, encoding: .utf8)
    }
}

struct SkillDocumentView: View {
    let skill: BundledSkill

    @State private var content: String?
    @State private var copyCompleted = false
    @State private var exportFile: SkillExportFile?
    @State private var exportURLForCleanup: URL?
    @State private var loadErrorMessage: String?
    @State private var downloadErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(skill.title, systemImage: "doc.text")
                        .font(.headline)
                    Text(skill.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    copySkill()
                } label: {
                    Label(copyCompleted ? "Copied" : "Copy", systemImage: copyCompleted ? "checkmark" : "doc.on.doc")
                }
                .disabled(content == nil)
                .accessibilityHint("Copies this public AI skill as Markdown")

                Button {
                    downloadSkill()
                } label: {
                    Label("Download…", systemImage: "arrow.down.doc")
                }
                .disabled(content == nil)
                .accessibilityHint("Saves this public AI skill as SKILL.md")
            }

            Group {
                if let content {
                    ScrollView {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                    }
                    .scrollIndicators(.visible)
                } else if let loadErrorMessage {
                    ContentUnavailableView(
                        "Skill unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadErrorMessage)
                    )
                } else {
                    ProgressView("Loading skill…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 240, idealHeight: 320, maxHeight: 400)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            }

            Text("This is the public `SKILL.md` from the repository. It contains no API token, accessory names, identifiers, or HomeKit values.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: loadSkill)
        .sheet(item: $exportFile, onDismiss: cleanUpExportFile) { export in
            SkillExportPicker(fileURL: export.url) {
                exportFile = nil
            }
        }
        .alert("Download Failed", isPresented: downloadErrorPresented) {
            Button("OK") {
                downloadErrorMessage = nil
            }
        } message: {
            Text(downloadErrorMessage ?? "The skill could not be prepared for download.")
        }
    }

    private func loadSkill() {
        guard content == nil, loadErrorMessage == nil else { return }

        do {
            content = try skill.load()
        } catch {
            loadErrorMessage = "The bundled skill file could not be loaded."
        }
    }

    private func copySkill() {
        guard let content else { return }
        UIPasteboard.general.string = content
        copyCompleted = true
    }

    private func downloadSkill() {
        guard let content else { return }

        do {
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("HKRelay-SkillExport", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let fileURL = directoryURL.appendingPathComponent("SKILL.md", isDirectory: false)
            try Data(content.utf8).write(to: fileURL, options: .atomic)
            exportURLForCleanup = fileURL
            exportFile = SkillExportFile(url: fileURL)
        } catch {
            downloadErrorMessage = "The skill could not be prepared for download."
        }
    }

    private func cleanUpExportFile() {
        if let exportURLForCleanup {
            try? FileManager.default.removeItem(at: exportURLForCleanup)
        }
        exportURLForCleanup = nil
    }

    private var downloadErrorPresented: Binding<Bool> {
        Binding(
            get: { downloadErrorMessage != nil },
            set: { if !$0 { downloadErrorMessage = nil } }
        )
    }
}

private struct SkillExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SkillExportPicker: UIViewControllerRepresentable {
    let fileURL: URL
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forExporting: [fileURL],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onFinished: () -> Void

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onFinished()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinished()
        }
    }
}

private enum SkillDocumentError: Error {
    case missingResource
}
