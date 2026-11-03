import Testing
@testable import TaDa

/// The bundled `Acknowledgements.txt` as the About page lists it.
struct AcknowledgementsTests {
    @Test func bundledFileListsEachPackageWithItsLicence() {
        let all = Acknowledgement.all
        #expect(all.map(\.name) == [
            "swift-markdown-engine-extended (the Live editor)", "Yams", "libyaml (inside Yams)",
            "Ayu (the Ayu Light and Ayu Mirage themes)", "TokyoNight (the TokyoNight Day and TokyoNight themes)",
            "Catppuccin (the Catppuccin Latte and Catppuccin Mocha themes)",
            "Sparkle (software updates)",
        ])
        #expect(all.map(\.url) == [
            "https://github.com/lobrenov/swift-markdown-engine-extended",
            "https://github.com/jpsim/Yams",
            "https://github.com/yaml/libyaml",
            "https://github.com/ayu-theme/ayu-colors",
            "https://github.com/folke/tokyonight.nvim",
            "https://github.com/catppuccin/palette",
            "https://github.com/sparkle-project/Sparkle",
        ])
        #expect(all.map(\.licence) == ["Apache License 2.0", "MIT", "MIT", "MIT", "Apache License 2.0", "MIT", "Sparkle"])
    }

    @Test func parsesSectionsAndTakesTheFirstLicenceHeading() {
        let text = """
        Intro line.

        ===
        A
        https://a
        ===

        --- NOTICE ---
        --- License (MIT) ---
        --- LICENSE (BSD) ---
        ===
        B
        https://b
        ===
        --- LICENSE (Apache License 2.0) ---
        """
        #expect(Acknowledgement.parse(text) == [
            Acknowledgement(name: "A", url: "https://a", licence: "MIT"),
            Acknowledgement(name: "B", url: "https://b", licence: "Apache License 2.0"),
        ])
    }
}
