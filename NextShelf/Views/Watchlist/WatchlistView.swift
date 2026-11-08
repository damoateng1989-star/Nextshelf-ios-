import SwiftUI

/// Watchlist — add/remove tickers, per-ticker hub state.
/// Respects the Free tier cap from /api/me (402 on add when hit).
struct WatchlistView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var items: [WatchlistItem] = []
    @State private var earnings: [String: EarningsEntry] = [:]
    @State private var newSymbol = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var addError: String?
    @State private var isAdding = false

    private var api: APIClient { .shared }

    private var cap: Int? { session.me?.tickerLimit }
    private var capLine: String? {
        guard let cap else { return nil }
        return "\(items.count) of \(cap) tickers · Free is capped by plan."
    }

    var body: some View {
        Group {
            if !session.isSignedIn && !session.isGuest {
                EmptyStateView(title: "Sign in to keep a watchlist",
                               message: "Your watchlist lives on your account. Sign in and your tickers will be here.")
            } else if session.isGuest {
                EmptyStateView(title: "Watchlists need an account",
                               message: "Guests can browse the board. Sign in (free) to watch tickers and get alerted.")
            } else {
                list
            }
        }
        .navigationTitle("Watchlist")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
    }

    private var list: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("Add a ticker — try AMZN, NVDA…", text: $newSymbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await add() } }
                    Button {
                        Task { await add() }
                    } label: {
                        if isAdding { ProgressView() } else { Text("Add").fontWeight(.semibold) }
                    }
                    .disabled(newSymbol.cleanedTicker.isEmpty || isAdding)
                }
                if let capLine {
                    Text(capLine).font(.system(size: 12)).foregroundStyle(NSColor.muted)
                }
                if let addError {
                    Text(addError).font(.subheadline).foregroundStyle(NSColor.down)
                }
            }

            if isLoading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            } else if items.isEmpty {
                Text("Nothing watched yet. Add a ticker above — it joins your hub watch and you get alerted when it forms or breaks.")
                    .font(.subheadline)
                    .foregroundStyle(NSColor.muted)
            } else {
                Section("Watching for a hub") {
                    ForEach(items) { item in
                        NavigationLink {
                            ShelfCardView(symbol: item.symbol, row: item.status)
                        } label: {
                            WatchlistRow(item: item, earnings: earnings[item.symbol])
                        }
                    }
                    .onDelete { indexSet in
                        Task { await remove(at: indexSet) }
                    }
                }
                Text("Swipe to remove. Removing a ticker stops its alerts instantly. It doesn't delete past setups from the record.")
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)
            }

            if let error {
                Text(error).font(.subheadline).foregroundStyle(NSColor.down)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NSColor.paper)
    }

    // MARK: - Data

    private func load() async {
        if items.isEmpty { isLoading = true }
        error = nil
        do {
            items = try await api.tickers()
            let syms = items.map(\.symbol)
            if !syms.isEmpty {
                earnings = try await api.earnings(symbols: syms)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func add() async {
        let sym = newSymbol.cleanedTicker
        guard !sym.isEmpty else { return }
        isAdding = true
        addError = nil
        defer { isAdding = false }
        do {
            _ = try await api.addTicker(sym)
            newSymbol = ""
            await load()
        } catch let e as APIError {
            // 402 is the Free cap — the server's message says it plainly.
            addError = e.errorDescription
        } catch {
            addError = error.localizedDescription
        }
    }

    private func remove(at indexSet: IndexSet) async {
        for index in indexSet {
            let item = items[index]
            do {
                _ = try await api.removeTicker(item.symbol)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        await load()
    }
}

struct WatchlistRow: View {
    let item: WatchlistItem
    let earnings: EarningsEntry?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.symbol).font(.system(size: 15, weight: .800))
                    if let earnings, let days = earnings.days, days <= 7 {
                        StateBadge(text: "EARNINGS", tone: .amber)
                    } else if let state = item.status?.state {
                        switch state {
                        case "breakout_up": StateBadge(text: "BREAKOUT ↑", tone: .up)
                        case "breakdown": StateBadge(text: "BREAKDOWN ↓", tone: .down)
                        case "forming": StateBadge(text: "NEAR", tone: .blue)
                        default: EmptyView()
                        }
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.status?.lastClose?.price ?? "—")
                    .font(.system(size: 14, weight: .700))
                if let earnings, let days = earnings.days, days <= 7 {
                    Text("Blackout ≤7d")
                        .font(.system(size: 11, weight: .700))
                        .foregroundStyle(NSColor.amber)
                } else if let sessions = item.status?.hub?.sessions {
                    Text("\(sessions) sessions")
                        .font(.system(size: 11))
                        .foregroundStyle(NSColor.muted)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if let earnings {
            return "Reports \(earnings.label ?? earnings.date ?? "")"
        }
        if let hub = item.status?.hub {
            return "Hub \(hub.low?.price ?? "—")–\(hub.high?.price ?? "—")"
        }
        return item.status?.label ?? "No hub right now"
    }
}
