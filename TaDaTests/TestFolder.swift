// A throwaway folder of files and its own settings for one test. The folder goes when the suite instance that
// holds it does, at the end of the test.
import Foundation
import TaDaCore
@testable import TaDa

final class TestFolder {
    let url = FileManager.default.temporaryDirectory.appending(path: "TaDaVault-\(UUID().uuidString)", directoryHint: .isDirectory)
    let defaults = TestSettings()

    /// `files` are paths in the folder and their text.
    init(_ files: KeyValuePairs<String, String> = [:]) throws {
        for (path, text) in files { try create(text, path) }
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes as another app would, making sure the modification date moves on.
    func write(_ text: String, _ path: String) throws {
        try create(text, path)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double.random(in: 1...1000))],
                                              ofItemAtPath: url.appending(path: path).path)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: url.appending(path: path), encoding: .utf8)
    }

    /// A model on the folder on 3 October 2026 unless `today` is given, with `path` selected and loaded.
    @MainActor
    func model(today: LocalDate = LocalDate("2026-10-03")!, selecting path: String? = nil) async -> AppModel {
        let model = AppModel(defaults: defaults)
        model.today = today
        await model.choose(url)
        if let path {
            model.selection = path
            await model.loading?.value
        }
        return model
    }

    private func create(_ text: String, _ path: String) throws {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
}
