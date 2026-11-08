import SwiftUI

// MARK: - White-pill segmented control (the design bar)
//
// The web app's `.setup-tabs` / `.rec-tabs`: white pills on a grey track,
// selected pill white with a soft shadow. Sparrow's segmented control
// (vendored in Regulur) is the pattern ancestor; this is a fresh SwiftUI
// implementation — no UIKit code was lifted.
struct PillSegmentedControl<Selection: Hashable>: View {
    let options: [(Selection, String)]
    @Binding var selection: Selection

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.0) { option in
                    let (value, label) = option
                    Button {
                        selection = value
                    } label: {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selection == value ? Color.white : Color.clear)
                            .foregroundStyle(selection == value ? Color.black : NSColor.muted)
                            .clipShape(Capsule())
                            .shadow(color: selection == value ? Color.black.opacity(0.12) : .clear,
                                    radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }
}

// MARK: - Badges

/// Direction badge: green/red ONLY here and on percentage text.
/// `text` is the label ("SHORT ↓", "AT EDGE", "BREAKOUT ↑"); `tone`
/// is .up / .down / .neutral / .blue / .amber.
enum BadgeTone { case up, down, neutral, blue, amber }

struct StateBadge: View {
    let text: String
    let tone: BadgeTone

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .800))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch tone {
        case .up: return NSColor.up.opacity(0.14)
        case .down: return NSColor.down.opacity(0.12)
        case .neutral: return Color.primary.opacity(0.07)
        case .blue: return NSColor.blue.opacity(0.13)
        case .amber: return NSColor.amber.opacity(0.15)
        }
    }

    private var foreground: Color {
        switch tone {
        case .up: return NSColor.up
        case .down: return NSColor.down
        case .neutral: return NSColor.muted
        case .blue: return NSColor.blue
        case .amber: return NSColor.amber
        }
    }
}

/// Hub grade badge: "WAREHOUSE · 4/6" / "LEDGE · 2/6". Grade is a label,
/// never a direction — so it renders neutral.
struct GradeBadge: View {
    let grade: String?
    let score: Double?

    var body: some View {
        if let grade {
            let label = grade.capitalized
            let scoreText = score.map { " · \(Int($0))/6" } ?? ""
            StateBadge(text: "\(label.uppercased())\(scoreText)", tone: .neutral)
        }
    }
}

// MARK: - Direction text (the only place green/red appear as text)

/// A percentage with direction colour. `value` is a signed percent.
/// Pass `nil` and nothing renders.
struct DirectionPercent: View {
    let value: Double?
    let suffix: String

    init(_ value: Double?, suffix: String = "%") {
        self.value = value
        self.suffix = suffix
    }

    var body: some View {
        if let value {
            Text(String(format: "%+.1f%@", value, suffix))
                .font(.system(size: 12, weight: .700))
                .foregroundStyle(value >= 0 ? NSColor.up : NSColor.down)
        }
    }
}

// MARK: - Cards / sections

struct NSCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(13)
            .background(NSColor.card)
            .clipShape(RoundedRectangle(cornerRadius: NSLayout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: NSLayout.cornerRadius)
                    .stroke(NSColor.line, lineWidth: 1)
            )
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .800))
                .tracking(0.07)
                .foregroundStyle(NSColor.muted)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .600))
                    .foregroundStyle(NSColor.muted)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

// MARK: - States

struct LoadingView: View {
    var message = "Loading…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(NSColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(NSColor.muted)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(NSColor.muted)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Buttons

struct NSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .700))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(NSColor.ink)
            .foregroundStyle(NSColor.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct NSBlueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .700))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(NSColor.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension View {
    /// Inline error banner shown under a form when an API call fails.
    /// Appends the banner BELOW the view (not in place of it).
    func apiErrorBanner(_ message: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            self
            if let message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(NSColor.down)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(NSColor.down.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: NSLayout.smallRadius))
            }
        }
    }
}
