import SwiftUI

/// The Board (Setups) — the home screen.
///
/// Renders whatever the API returns, exactly like the web board:
///   guest  → counts only, locked, member-only notice
///   free   → live/near as counts when the server lock is on
///            (BOARD_FOR_ALL is currently on server-side, so Free usually
///            sees full rows — the client handles both)
///   pro    → full rows everywhere
/// The rule: rows when present; when a group is empty but its count is
/// > 0, show the locked-count card. The client never decides the tier.
@MainActor
final class BoardViewModel: ObservableObject {
    @Published private(set) var board: BoardResponse?
    @Published private(set) var info: InfoResponse?
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let api: APIClient

    init(api: APIClient = .shared) { self.api = api }

    func load() async {
        if board == nil { isLoading = true }
        error = nil
        do {
            async let boardTask = api.board()
            async let infoTask = api.info()
            let (b, i) = try await (boardTask, infoTask)
            board = b
            info = i
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct BoardView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var vm = BoardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if vm.isLoading && vm.board == nil {
                    LoadingView(message: "Loading the board…")
                } else if let error = vm.error, vm.board == nil {
                    ErrorStateView(message: error) { Task { await vm.load() } }
                } else if let board = vm.board {
                    content(board)
                }
            }
            .padding(.horizontal, NSLayout.screenPadding)
            .padding(.bottom, 24)
        }
        .background(NSColor.paper)
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .navigationTitle("Setups")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if session.isSignedIn {
                    Text(session.me?.firstName ?? "")
                        .font(.system(size: 13, weight: .700))
                        .frame(width: 36, height: 36)
                        .background(NSColor.ink)
                        .foregroundStyle(NSColor.paper)
                        .clipShape(Circle())
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let updated = ServerDate.updatedLine(vm.board?.updated) {
                Text("\(updated) · Pull to refresh")
                    .font(.system(size: 13))
                    .foregroundStyle(NSColor.muted)
            }
            if let regime = vm.board?.regime, regime.regime != nil {
                regimeBanner(regime)
            }
            if session.isGuest {
                guestBanner
            }
        }
    }

    /// Regime from /api/board (NOT /api/info — the spec was wrong here;
    /// live code puts it on the board payload). Display only.
    private func regimeBanner(_ regime: Regime) -> some View {
        HStack(spacing: 10) {
            Text(regime.isDown ? "↓" : "↑")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(regime.isDown ? NSColor.down : NSColor.up)
            VStack(alignment: .leading, spacing: 2) {
                Text(regime.isDown ? "Market: Downtrend" : "Market: Uptrend")
                    .font(.system(size: 13, weight: .700))
                Text(regimeLine(regime))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            Spacer()
        }
        .padding(12)
        .background(Color.black)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func regimeLine(_ regime: Regime) -> String {
        let index = regime.index ?? "SPY"
        let days = regime.days ?? 50
        if regime.isDown {
            return "\(index) below its \(days)-day — alerts & paper on shorts only today."
        } else {
            return "\(index) above its \(days)-day — alerts & paper on longs only today."
        }
    }

    private var guestBanner: some View {
        NSCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("You're browsing as a guest")
                    .font(.system(size: 14, weight: .700))
                Text("Counts only — sign in to see your board, your watchlist and your alerts.")
                    .font(.system(size: 13))
                    .foregroundStyle(NSColor.muted)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func content(_ board: BoardResponse) -> some View {
        // Breaking out now — live rows, or the locked count.
        SectionLabel(title: "Breaking out now",
                     trailing: countLabel(board.live?.count, board.liveCount, singular: "live"))
        if let live = board.live, !live.isEmpty {
            NSCard {
                VStack(spacing: 0) {
                    ForEach(live) { row in
                        NavigationLink { ShelfCardView(symbol: row.symbol ?? "", row: row) } label: {
                            BoardRowView(row: row)
                        }
                        .buttonStyle(.plain)
                        if row.id != live.last?.id { Divider() }
                    }
                }
            }
        } else {
            lockedCard(count: board.liveCount, what: "live right now")
        }

        // At the hub edge — near rows, or the locked count.
        SectionLabel(title: "At the hub edge",
                     trailing: countLabel(board.near?.count, board.nearCount, singular: "near"))
        if let near = board.near, !near.isEmpty {
            NSCard {
                VStack(spacing: 0) {
                    ForEach(near) { row in
                        NavigationLink { ShelfCardView(symbol: row.symbol ?? "", row: row) } label: {
                            BoardRowView(row: row)
                        }
                        .buttonStyle(.plain)
                        if row.id != near.last?.id { Divider() }
                    }
                }
            }
        } else {
            lockedCard(count: board.nearCount, what: "at the edge")
        }

        // Resting in a hub — forming rows as chips.
        SectionLabel(title: "Resting in a hub",
                     trailing: countLabel(board.forming?.count, board.formingCount, singular: "forming"))
        if let forming = board.forming, !forming.isEmpty {
            FlowChips(rows: forming)
        } else if let count = board.formingCount, count > 0 {
            Text("\(count) stocks resting in hubs.")
                .font(.subheadline)
                .foregroundStyle(NSColor.muted)
        } else {
            Text("Nothing resting in a hub right now.")
                .font(.subheadline)
                .foregroundStyle(NSColor.muted)
        }

        // Recent — follow-through / snap-back / stalled.
        if let recent = board.recent, !recent.isEmpty {
            SectionLabel(title: "Recent", trailing: "\(recent.count) finished")
            NSCard {
                VStack(spacing: 0) {
                    ForEach(recent) { row in
                        NavigationLink { ShelfCardView(symbol: row.symbol ?? "", row: row) } label: {
                            BoardRowView(row: row)
                        }
                        .buttonStyle(.plain)
                        if row.id != recent.last?.id { Divider() }
                    }
                }
            }
        }

        // Other setups — non-hub patterns, one row each.
        if let setups = board.setups, !setups.isEmpty {
            SectionLabel(title: "Other setups", trailing: "\(setups.count) live")
            NSCard {
                VStack(spacing: 0) {
                    ForEach(setups) { setup in
                        SetupRowView(setup: setup)
                        if setup.id != setups.last?.id { Divider() }
                    }
                }
            }
        } else if let locked = board.setupsLocked, locked > 0 {
            lockedCard(count: locked, what: "timely setups")
        }

        Text("The close is the trigger — not the wick. 1:30 PM is the verdict candle, 4:00 PM confirms.")
            .font(.system(size: 12))
            .foregroundStyle(NSColor.muted)
            .padding(.top, 16)
    }

    private func countLabel(_ rows: Int?, _ count: Int?, singular: String) -> String? {
        if let rows { return "\(rows) \(singular)" }
        if let count { return "\(count) \(singular)" }
        return nil
    }

    /// A group the API locked: show the count, not the rows.
    private func lockedCard(count: Int?, what: String) -> some View {
        NSCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let count {
                        Text("\(count) \(what)")
                            .font(.system(size: 14, weight: .700))
                    }
                    Text("Members see every row. Pro sees them live.")
                        .font(.system(size: 13))
                        .foregroundStyle(NSColor.muted)
                }
                Spacer()
                Button("See Pro") {
                    if let url = URL(string: "https://nextshelfapp.com/pricing") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 13, weight: .700))
                .foregroundStyle(NSColor.blue)
            }
        }
    }
}

// MARK: - Rows

struct BoardRowView: View {
    let row: BoardRow

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.symbol ?? "—")
                        .font(.system(size: 15, weight: .800))
                    stateBadge
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(row.lastClose?.price ?? "—")
                    .font(.system(size: 14, weight: .700))
                if let target = row.target {
                    Text("Target \(target.price)")
                        .font(.system(size: 11, weight: .700))
                        .foregroundStyle(NSColor.muted)
                } else if let pct = row.toTargetPct {
                    DirectionPercent(pct)
                }
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if let hub = row.hub {
            let range = "\(hub.low?.price ?? "—") – \(hub.high?.price ?? "—")"
            let sessions = hub.sessions.map { " · \($0) sessions" } ?? ""
            return "Hub \(range)\(sessions)"
        }
        return row.label ?? ""
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch row.state {
        case "breakout_up":
            StateBadge(text: "BREAKOUT ↑", tone: .up)
        case "breakdown":
            StateBadge(text: "SHORT ↓", tone: .down)
        case "forming":
            if row.nearEdge != nil {
                StateBadge(text: "AT EDGE", tone: .blue)
            } else {
                StateBadge(text: "FORMING", tone: .neutral)
            }
        case "watching":
            StateBadge(text: "WATCHING", tone: .neutral)
        case "follow-through":
            StateBadge(text: "FOLLOWED THROUGH", tone: .up)
        case "snap-back":
            StateBadge(text: "SNAPPED BACK", tone: .down)
        case "stalled":
            StateBadge(text: "STALLED", tone: .neutral)
        default:
            EmptyView()
        }
    }
}

struct SetupRowView: View {
    let setup: SetupRow

    var body: some View {
        NavigationLink {
            ShelfCardView(symbol: setup.symbol ?? "", row: nil, setup: setup)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(setup.name ?? setup.kind ?? "Setup")
                            .font(.system(size: 15, weight: .700))
                        setupBadge
                    }
                    Text(setupSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(NSColor.muted)
                }
                Spacer()
                if let target = setup.target {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Target \(target.price)")
                            .font(.system(size: 12, weight: .700))
                        if let pct = setup.toTargetPct { DirectionPercent(pct) }
                    }
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var setupSubtitle: String {
        var bits: [String] = []
        if let edge = setup.edge { bits.append("Edge \(edge.price)") }
        if let sessions = setup.sessions { bits.append("\(sessions) sessions") }
        if let touches = setup.touches { bits.append("\(touches) touches") }
        if let gap = setup.gapPct { bits.append("Gap +\(gap)%") }
        return bits.joined(separator: " · ")
    }

    @ViewBuilder
    private var setupBadge: some View {
        switch setup.state {
        case "breakout_up": StateBadge(text: "BREAKOUT ↑", tone: .up)
        case "breakdown": StateBadge(text: "BREAKDOWN ↓", tone: .down)
        case "testing": StateBadge(text: "TESTING", tone: .blue)
        case "forming": StateBadge(text: "FORMING", tone: .neutral)
        default: EmptyView()
        }
    }
}

/// Wrapping chips for the "Resting in a hub" group.
struct FlowChips: View {
    let rows: [BoardRow]

    var body: some View {
        // Simple wrapping layout via a LazyVGrid with adaptive columns.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                NavigationLink { ShelfCardView(symbol: row.symbol ?? "", row: row) } label: {
                    HStack(spacing: 4) {
                        Text(row.symbol ?? "—").font(.system(size: 12, weight: .700))
                        Text("· \(row.hub?.sessions ?? 0) sess")
                            .font(.system(size: 12))
                            .foregroundStyle(NSColor.muted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(NSColor.card)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(NSColor.line))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
