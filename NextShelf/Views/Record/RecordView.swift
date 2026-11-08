import SwiftUI

/// Record — read-only. Numbers come from the API, never hardcoded.
///   signed in → GET /api/record?pattern=… (headline + by-volume +
///   by-grade + by-pattern splits)
///   guest     → GET /api/public/summary (public strip; /api/record is
///               signed-in only on the server)
///   admin     → + GET /api/paper (view-only; the endpoint 403s for
///               everyone else, so it is never called for them)
struct RecordView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var record: RecordResponse?
    @State private var summary: PublicSummary?
    @State private var paper: PaperSummary?
    @State private var pattern = "hub"
    @State private var isLoading = false
    @State private var error: String?

    private var api: APIClient { .shared }

    /// Pattern keys + names, from patterns.KINDS in the backend.
    private let patterns: [(String, String)] = [
        ("hub", "Hub"), ("triangle", "Symmetrical triangle"),
        ("channel_up", "Ascending channel"), ("channel_down", "Descending channel"),
        ("sr", "Support & resistance"), ("flag_bull", "Bull flag"),
        ("flag_bear", "Bear flag"), ("double_top", "Double top"),
        ("double_bottom", "Double bottom"), ("gapfade", "Post-earnings gap fade & rip"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if session.isGuest {
                    guestContent
                } else if !session.isSignedIn {
                    EmptyStateView(title: "Sign in to see the record",
                                   message: "The full track record is for members. Guests see the public strip below.")
                } else if isLoading && record == nil {
                    LoadingView(message: "Loading the record…")
                } else if let error, record == nil {
                    ErrorStateView(message: error) { Task { await load() } }
                } else if let record {
                    memberContent(record)
                }
            }
            .padding(.horizontal, NSLayout.screenPadding)
            .padding(.bottom, 28)
        }
        .background(NSColor.paper)
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: pattern) { _, _ in Task { await load() } }
    }

    // MARK: - Load

    private func load() async {
        if record == nil && summary == nil { isLoading = true }
        error = nil
        do {
            if session.isGuest || !session.isSignedIn {
                summary = try await api.publicSummary()
            } else {
                async let recordTask = api.record(pattern: pattern)
                if session.me?.isAdmin == true {
                    async let paperTask = api.paper()
                    let (r, p) = try await (recordTask, paperTask)
                    record = r
                    paper = p
                } else {
                    record = try await recordTask
                    paper = nil
                }
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Guest (public strip)

    private var guestContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Read-only. Same numbers as the web — nothing is recomputed in the app.")
                .font(.subheadline)
                .foregroundStyle(NSColor.muted)
            if let s = summary {
                HStack(spacing: 8) {
                    statTile(label: "COMPLETED", value: s.closed.map(String.init) ?? "—",
                             sub: "\(s.signals ?? 0) setups tracked")
                    statTile(label: "OPEN NOW", value: s.open.map(String.init) ?? "—",
                             sub: "\(s.live ?? 0) live · \(s.near ?? 0) near")
                }
                NSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        statRow(label: "Win rate", value: s.winRate.map { String(format: "%.1f%%", $0) } ?? "—")
                        statRow(label: "Avg per setup", value: s.avgRet.map { $0.signedPercent } ?? "—")
                        statRow(label: "Reached the shelf", value: s.reachedPct.map { "\($0)%" } ?? "—")
                        if let updated = ServerDate.updatedLine(s.updated) {
                            Text(updated).font(.system(size: 12)).foregroundStyle(NSColor.muted)
                        }
                    }
                }
            } else if isLoading {
                LoadingView(message: "Loading the public record…")
            }
            NSCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sign in for the full record")
                        .font(.system(size: 14, weight: .700))
                    Text("By-volume and by-grade splits, per-pattern and per-symbol tables.")
                        .font(.system(size: 13))
                        .foregroundStyle(NSColor.muted)
                }
            }
        }
    }

    // MARK: - Member (full record)

    private func memberContent(_ record: RecordResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Read-only. Same numbers as the web — nothing is recomputed in the app.")
                .font(.subheadline)
                .foregroundStyle(NSColor.muted)

            PillSegmentedControl(options: patterns, selection: $pattern)

            if let stats = record.stats {
                HStack(spacing: 8) {
                    statTile(label: "COMPLETED", value: stats.closed.map(String.init) ?? "—",
                             sub: "\(stats.signals ?? 0) setups tracked")
                    statTile(label: "OPEN NOW", value: stats.open.map(String.init) ?? "—",
                             sub: "pending outcomes")
                }
                NSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        statRow(label: "Win rate", value: stats.winRate.map { String(format: "%.1f%%", $0) } ?? "—")
                        statRow(label: "Avg per setup", value: stats.avgRet.map { $0.signedPercent } ?? "—")
                        statRow(label: "Avg win", value: stats.avgWin.map { $0.signedPercent } ?? "—")
                        statRow(label: "Avg loss", value: stats.avgLoss.map { $0.signedPercent } ?? "—")
                        if let by = stats.byOutcome {
                            statRow(label: "Reached the shelf", value: "\(by["follow-through"] ?? 0)")
                            statRow(label: "Snapped back", value: "\(by["snap-back"] ?? 0)")
                            statRow(label: "Stalled", value: "\(by["stalled"] ?? 0)")
                        }
                    }
                }

                if let byVolume = stats.byVolume, !byVolume.isEmpty {
                    SectionLabel(title: "By volume on the breakout candle")
                    NSCard {
                        VStack(spacing: 10) {
                            ForEach(["strong", "normal", "light"], id: \.self) { key in
                                if let split = byVolume[key] {
                                    splitRow(name: key.capitalized, split: split)
                                }
                            }
                        }
                    }
                }

                if let byGrade = stats.byGrade, !byGrade.isEmpty {
                    SectionLabel(title: "By hub grade")
                    NSCard {
                        VStack(spacing: 10) {
                            ForEach(["warehouse", "ledge"], id: \.self) { key in
                                if let split = byGrade[key] {
                                    splitRow(name: key.capitalized, split: split)
                                }
                            }
                        }
                    }
                    Text("Grade = sessions + width in ATRs + hub volume. The app shows the split — the gate stays off until the record proves it.")
                        .font(.system(size: 12))
                        .foregroundStyle(NSColor.muted)
                }
            }

            if let patterns = record.patterns, !patterns.isEmpty {
                SectionLabel(title: "By setup")
                NSCard {
                    VStack(spacing: 0) {
                        ForEach(patterns.sorted(by: { ($0.value.signals ?? 0) > ($1.value.signals ?? 0) }),
                                id: \.key) { pair in
                            let (key, summary) = pair
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.name ?? key).font(.system(size: 14, weight: .600))
                                    Text("\(summary.closed ?? 0) completed")
                                        .font(.system(size: 12)).foregroundStyle(NSColor.muted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(summary.avgRet.map { $0.signedPercent } ?? "—")
                                        .font(.system(size: 14, weight: .700))
                                        .foregroundStyle((summary.avgRet ?? 0) >= 0 ? NSColor.up : NSColor.down)
                                    Text(summary.winRate.map { String(format: "%.0f%% win", $0) } ?? "")
                                        .font(.system(size: 12)).foregroundStyle(NSColor.muted)
                                }
                            }
                            .padding(.vertical, 8)
                            if key != patterns.sorted(by: { ($0.value.signals ?? 0) > ($1.value.signals ?? 0) }).last?.key {
                                Divider()
                            }
                        }
                    }
                }
            }

            if let paper {
                paperSection(paper)
            }

            if let since = ServerDate.shortDate(record.since) {
                Text("Counting breakouts since \(since).")
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)
            }
        }
    }

    // MARK: - Paper (admin only, view-only)

    private func paperSection(_ paper: PaperSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Paper trades — view only")
            NSCard {
                VStack(alignment: .leading, spacing: 8) {
                    if let stats = paper.stats {
                        statRow(label: "Closed", value: stats.closed.map(String.init) ?? "—")
                        statRow(label: "Win rate", value: stats.winRate.map { String(format: "%.1f%%", $0) } ?? "—")
                        statRow(label: "Total P&L", value: stats.totalPnl.map { String.money($0) } ?? "—")
                        statRow(label: "Avg per trade", value: stats.avgPct.map { $0.signedPercent } ?? "—")
                    }
                    Text("~\(String.money(paper.tradeUsd ?? 1700, digits: 0)) per entry, target = next shelf, exit on snap-back / target / 10 candles. No orders from the phone.")
                        .font(.system(size: 12))
                        .foregroundStyle(NSColor.muted)
                    if let open = paper.open, !open.isEmpty {
                        Divider()
                        ForEach(open) { trade in
                            HStack {
                                Text(trade.symbol ?? "—").font(.system(size: 14, weight: .700))
                                Text(trade.direction == 1 ? "LONG" : "SHORT")
                                    .font(.system(size: 11, weight: .700))
                                    .foregroundStyle(trade.direction == 1 ? NSColor.up : NSColor.down)
                                Spacer()
                                if let pct = trade.unrealPct {
                                    Text(pct.signedPercent)
                                        .font(.system(size: 13, weight: .700))
                                        .foregroundStyle(pct >= 0 ? NSColor.up : NSColor.down)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func statTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .800))
                .tracking(0.07)
                .foregroundStyle(NSColor.muted)
            Text(value)
                .font(.system(size: 28, weight: .800))
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(NSColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(NSColor.card)
        .clipShape(RoundedRectangle(cornerRadius: NSLayout.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: NSLayout.cornerRadius).stroke(NSColor.line))
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14))
            Spacer()
            Text(value).font(.system(size: 14, weight: .700))
        }
    }

    private func splitRow(name: String, split: SplitStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.system(size: 14, weight: .600))
                Spacer()
                Text("\(split.n ?? 0) closed").font(.system(size: 12)).foregroundStyle(NSColor.muted)
            }
            HStack(spacing: 12) {
                Text("Reached \(split.reached ?? 0)")
                Text(split.winRate.map { String(format: "%.0f%% win", $0) } ?? "—")
                Text(split.avgRet.map { $0.signedPercent } ?? "—")
                    .foregroundStyle((split.avgRet ?? 0) >= 0 ? NSColor.up : NSColor.down)
            }
            .font(.system(size: 13))
            .foregroundStyle(NSColor.muted)
            if let n = split.n, n > 0, let reached = split.reached {
                GeometryReader { geo in
                    Capsule().fill(NSColor.blue)
                        .frame(width: geo.size.width * CGFloat(reached) / CGFloat(n), height: 7)
                }
                .frame(height: 7)
                .background(Capsule().fill(NSColor.line).frame(height: 7))
            }
        }
    }
}
