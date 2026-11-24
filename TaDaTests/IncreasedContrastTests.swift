import Testing
@testable import TaDa

@MainActor @Suite struct IncreasedContrastTests {
    @Test func contrastRatioMatchesWCAG() {
        let theme = Theme.all[0]
        #expect(abs(Theme.contrastRatio(theme.bg, theme.bg) - 1) < 0.001)
        #expect(Theme.contrastRatio(theme.bg, theme.fg) == Theme.contrastRatio(theme.fg, theme.bg))
        // Ayu Light's #f8f9fa on #5c6166 is 5.9:1.
        #expect(abs(Theme.contrastRatio(theme.bg, theme.fg) - 5.9) < 0.1)
    }

    @Test(arguments: Theme.all)
    func mutedAndBorderReachWCAGOnBackground(theme: Theme) {
        let increased = theme.increasedContrast
        #expect(Theme.contrastRatio(increased.muted, increased.bg) >= 4.5, "\(theme.name) muted")
        #expect(Theme.contrastRatio(increased.border, increased.bg) >= 3, "\(theme.name) border")
    }

    @Test(arguments: Theme.all)
    func accentsReachThreeToOne(theme: Theme) {
        let increased = theme.increasedContrast
        for colour in [increased.accent, increased.due, increased.deadline, increased.done, increased.doing,
                       increased.blocked, increased.link] {
            #expect(Theme.contrastRatio(colour, increased.bg) >= 3, "\(theme.name)")
        }
    }

    @Test(arguments: Theme.all)
    func increasedContrastKeepsTheGroundAndText(theme: Theme) {
        let increased = theme.increasedContrast
        #expect(increased.bg == theme.bg && increased.side == theme.side)
        #expect(increased.fg == theme.fg && increased.strong == theme.strong)
        #expect(increased.name == theme.name && increased.isDark == theme.isDark)
    }

    @Test(arguments: Theme.all)
    func normalContrastIsUnchanged(theme: Theme) {
        #expect(theme.contrasted(false) == theme)
        #expect(theme.contrasted(true) == theme.increasedContrast)
    }
}
