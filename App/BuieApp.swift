import SwiftUI
import UniformTypeIdentifiers
import BuieCore

@main
struct BuieApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ZipDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var instruction = ""
    @Published var modelName: String?
    @Published var status = "Importeer een GGUF-instructiemodel om te beginnen."
    @Published var busy = false
    @Published var canCancel = false
    @Published var document: ZipDocument?
    private var task: Task<Void, Never>?
    private let modelURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        modelURL = directory.appendingPathComponent("model.gguf")
        if FileManager.default.fileExists(atPath: modelURL.path) {
            modelName = UserDefaults.standard.string(forKey: "modelName") ?? "model.gguf"
            status = "Model gereed. Beschrijf je opdracht."
        }
    }

    func importModel(_ url: URL) {
        guard url.pathExtension.lowercased() == "gguf" else {
            status = "Selecteer een .gguf-bestand."
            return
        }
        busy = true
        canCancel = false
        status = "Model importeren…"
        let destination = modelURL
        task = Task {
            do {
                try await Task.detached {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let manager = FileManager.default
                    try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
                    defer { try? manager.removeItem(at: temporary) }
                    try manager.copyItem(at: url, to: temporary)
                    if manager.fileExists(atPath: destination.path) {
                        _ = try manager.replaceItemAt(destination, withItemAt: temporary)
                    } else {
                        try manager.moveItem(at: temporary, to: destination)
                    }
                    var storedURL = destination
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    try? storedURL.setResourceValues(values)
                }.value
                modelName = url.lastPathComponent
                UserDefaults.standard.set(modelName, forKey: "modelName")
                document = nil
                status = "Model gereed. Beschrijf je opdracht."
            } catch {
                status = "Import mislukt: \(error.localizedDescription)"
            }
            busy = false
        }
    }

    func run() {
        let prompt = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, modelName != nil else { return }
        busy = true
        canCancel = true
        document = nil
        status = "Het model werkt lokaal aan je opdracht…"
        let url = modelURL
        let work = Task.detached(priority: .userInitiated) {
            let output = try Inference.generate(modelURL: url, instruction: prompt)
            return try GeneratedProject.parse(output).zipData()
        }
        task = Task {
            do {
                let data = try await withTaskCancellationHandler(operation: {
                    try await work.value
                }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                document = ZipDocument(data: data)
                status = "Klaar. Exporteer de broncode als zip."
            } catch is CancellationError {
                status = "Opdracht gestopt."
            } catch {
                status = error.localizedDescription
            }
            busy = false
            canCancel = false
        }
    }

    func cancel() { task?.cancel() }
}

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var importing = false
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Lokaal model") {
                    Text(state.modelName ?? "Geen model geselecteerd")
                    Button("Importeer GGUF-model") { importing = true }.disabled(state.busy)
                    Text("Het model blijft op dit apparaat. Gebruik een instructiemodel dat in het beschikbare geheugen past.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Opdracht") {
                    TextEditor(text: $state.instruction).frame(minHeight: 180).disabled(state.busy)
                    Button("Voer opdracht uit") { state.run() }
                        .disabled(state.busy || state.modelName == nil || state.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if state.busy {
                        ProgressView()
                        if state.canCancel {
                            Button("Stop") { state.cancel() }
                        }
                    }
                }
                Section("Resultaat") {
                    Text(state.status)
                    if state.document != nil {
                        Button("Exporteer zip") { exporting = true }
                    }
                }
            }
            .navigationTitle("Buie")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url): state.importModel(url)
                case .failure(let error): state.status = "Import mislukt: \(error.localizedDescription)"
                }
            }
            .fileExporter(isPresented: $exporting, document: state.document, contentType: .zip, defaultFilename: "Buie-project") { result in
                if case .failure(let error) = result { state.status = "Export mislukt: \(error.localizedDescription)" }
            }
        }
    }
}
