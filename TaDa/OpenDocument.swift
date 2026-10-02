// The selected file's text. Every edit (typing, properties, checkboxes) changes `text`;
// AppModel reparses it into the index and saves it after a short pause.
import Foundation
import TaDaCore

@Observable final class OpenDocument {
    /// Vault-relative; changes when the file is renamed.
    var path: String {
        didSet { reparse() }
    }
    /// The whole file: frontmatter and body.
    var text: String {
        didSet {
            guard text != oldValue else { return }
            reparse()
            onChange?()
        }
    }
    /// The text as last read from or written to disk.
    var savedText: String
    /// The file's modification date when it was last read or written.
    var modified: Date?
    /// The text parsed; nil when it's no longer a Ta Da file.
    private(set) var item: Item?
    @ObservationIgnored var onChange: (() -> Void)?

    init(path: String, text: String, modified: Date?) {
        self.path = path
        self.text = text
        savedText = text
        self.modified = modified
        item = Item(parsing: text, path: path)
    }

    var isDirty: Bool { text != savedText }

    /// The body without its frontmatter: what the live editor edits.
    var body: String {
        get { FrontmatterSplitter.split(text).body }
        set { text = FrontmatterSplitter.split(text).block + newValue }
    }

    private func reparse() {
        item = Item(parsing: text, path: path)
    }
}
