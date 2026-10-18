// A Calendar event on one day in the Agenda: a bar in its calendar's colour, its start (or All day, or "until"
// its end) and its title, with "Day n of m" for an all-day event spanning days. Clicking or tapping opens Calendar.
import SwiftUI
import TaDaCore
#if os(macOS)
import AppKit
#endif

/// Today's rows dim once an event has ended; Upcoming's are a little smaller on the Mac and wider in time on iPhone.
enum IntegrationRowContext { case today, upcoming }

struct EventRow: View {
    let event: DayEvent
    let day: LocalDate
    let context: IntegrationRowContext
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    #if os(macOS)
    @State private var isHovered = false
    #else
    @Environment(PhoneNavigation.self) private var nav
    #endif

    var body: some View {
        if context == .today, !event.placement.isAllDay {
            TimelineView(.everyMinute) { timeline in
                button(ended: event.event.hasEnded(now: timeline.date))
            }
        } else {
            button(ended: false)
        }
    }

    private func button(ended: Bool) -> some View {
        Button { CalendarApp.open(on: day, openURL: openURL) } label: {
            content.opacity(ended ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(ended: ended))
        #if os(macOS)
        .onHover { isHovered = $0 }
        .help("Open Calendar")
        #else
        // Picking rows leaves events alone.
        .disabled(nav.isPicking)
        #endif
    }

    private func accessibilityText(ended: Bool) -> String {
        #if os(macOS)
        var parts = ["Open Calendar: \(event.event.title)", event.timeText]
        #else
        var parts = ["Open Calendar on \(day.formatted(.weekdayDayMonth)): \(event.event.title)", event.timeText]
        #endif
        if let span = event.spanText { parts.append(span) }
        if ended { parts.append("ended") }
        return parts.joined(separator: ", ")
    }

    #if os(macOS)
    private var content: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(calendarHex: event.event.color))
                .frame(width: 3, height: context == .today ? 14 : 13)
            Text(event.timeText)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.color(\.muted))
                .frame(width: 84, alignment: .leading)
            Text(event.event.title)
                .font(.system(size: context == .today ? 13.5 : 13))
                .foregroundStyle(theme.color(\.fg))
                .lineLimit(1)
            if let span = event.spanText {
                Text(span).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted)).fixedSize()
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.color(\.muted))
                .opacity(isHovered ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: context == .today ? 26 : 24)
        .background(isHovered ? theme.color(\.code) : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
    }
    #else
    private var content: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(calendarHex: event.event.color))
                .frame(width: 4, height: 16)
                .frame(width: 22)
            HStack(spacing: 10) {
                Text(event.timeText)
                    .scaledFont(size: 13)
                    .monospacedDigit()
                    .foregroundStyle(theme.color(\.muted))
                    .frame(width: context == .today ? 64 : 96, alignment: .leading)
                Text(event.event.title)
                    .scaledFont(size: 16)
                    .foregroundStyle(theme.color(\.fg))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let span = event.spanText {
                    Text(span).scaledFont(size: 13).foregroundStyle(theme.color(\.muted)).fixedSize()
                }
            }
            .padding(.trailing, 16)
            .scaledMinHeight(40)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .padding(.leading, 16)
        .contentShape(.rect)
    }
    #endif
}

extension DayEvent {
    /// "9:30 am", "All day" or "until 10:00 am".
    var timeText: String {
        switch placement {
        case let .time(start): start.formatted(date: .omitted, time: .shortened)
        case .allDay: "All day"
        case let .until(end): "until \(end.formatted(date: .omitted, time: .shortened))"
        }
    }

    /// "Day 2 of 3" for an all-day event spanning days.
    var spanText: String? {
        dayOfSpan.map { "Day \($0.day) of \($0.of)" }
    }
}

/// Opens Calendar: on iPhone on `day`, on the Mac on the day it shows.
enum CalendarApp {
    static func open(on day: LocalDate, openURL: OpenURLAction) {
        #if os(macOS)
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        #else
        // `calshow:` takes seconds since 1 January 2001.
        openURL(URL(string: "calshow:\(Int(day.date().timeIntervalSinceReferenceDate))")!)
        #endif
    }
}
