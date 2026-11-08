import SwiftUI

/// The shelf card — ticker detail.
///
/// Data comes from three endpoints, loaded in parallel:
///   /api/chart/{symbol}   — status (hub, target, stop) + stats
///   /api/options/{symbol} — options plan (403 when the gate is off)
///   /api/gamma/{symbol}   — call/put walls (fail-open: walls may be null)
///   /api/earnings         — blackout badge (≤ 7 days)
/// The chart area is the live ticker page in a WKWebView (TickerWebView).
/// A native chart is post-v1.
struct ShelfCardView: View {
    let symbol: String
    /// Board row when navigating from the board (gives hub/target at once).
    let row: BoardRow?
    /// Non-hub setup row when navigating from "Other setups".
    let setup: SetupRow?

    init(symbol: String, row: BoardRow? = nil, setup: SetupRow? = nil) {
        self.symbol = symbol
        self.row = row
        self.setup = setup
    }

    @EnvironmentObject private var session: SessionStore
    @State private var chart: ChartResponse?
    @State private var options: OptionsPlanResponse?
    @State private var optionsUnavailable = false
    @State private var gamma: GammaResponse?
    @State private var earnings: EarningsEntry?
    @State private var isLoading = true
    @State private var error: String?
    @State private var watching: Bool?
    @State private var watchError: String?

    private var api: APIClient { .shared }

    /// Prefer the fresh chart status; fall back to the board row.
    private var status: BoardRow? { chart?.status ?? row }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isLoading && chart == nil {
                    LoadingView(message: "Loading \(symbol)…")
                } else if let error, chart == nil {
                    ErrorStateView(message: error) { Task { await load() } }
                } else {
                    header
                    badges
                    if let watchError {
                        Text(watchError)
                            .font(.subheadline)
                            .foregroundStyle(NSColor.down)
                    }
                    chartSection
                    hubSection
                    triggersSection
                    gammaSection
                    optionsSection
                    earningsSection
                    brokerSection
                    rulesFooter
                }
            }
            .padding(.horizontal, NSLayout.screenPadding)
            .padding(.bottom, 28)
        }
        .background(NSColor.paper)
        .navigationTitle(symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                watchButton
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Load

    private func load() async {
        if chart == nil { isLoading = true }
        error = nil
        optionsUnavailable = false
        do {
            async let chartTask = api.chart(symbol: symbol)
            async let gammaTask = api.gamma(symbol: symbol)
            async let earningsTask = api.earnings(symbols: [symbol])
            let (c, g, e) = try await (chartTask, gammaTask, earningsTask)
            chart = c
            gamma = g
            earnings = e[symbol]
            watching = c.watching ?? row?.watching
            // Options plan: 403 when the server gate is off for this
            // member (OPTIONS_FOR_ALL defaults on — most members get it).
            do {
                options = try await api.options(symbol: symbol)
            } catch let e as APIError where e.status == 403 {
                optionsUnavailable = true
                options = nil
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(symbol)
                    .font(.system(size: 26, weight: .800))
                Text(exchangeLine)
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(status?.lastClose?.price ?? "—")
                    .font(.system(size: 20, weight: .700))
                Text(status?.label ?? "")
                    .font(.system(size: 12, weight: .600))
                    .foregroundStyle(NSColor.muted)
            }
        }
    }

    private var exchangeLine: String {
        let ex = (chart?.exchange ?? row?.exchange ?? "").uppercased()
        return ex.isEmpty ? "US ticker" : ex
    }

    private var badges: some View {
        HStack(spacing: 6) {
            if let state = status?.state {
                switch state {
                case "breakout_up": StateBadge(text: "BREAKOUT ↑", tone: .up)
                case "breakdown": StateBadge(text: "BREAKDOWN ↓", tone: .down)
                case "forming": StateBadge(text: "FORMING", tone: .neutral)
                case "watching": StateBadge(text: "WATCHING", tone: .neutral)
                default: StateBadge(text: state.uppercased(), tone: .neutral)
                }
            }
            if let setup, let kind = setup.name {
                StateBadge(text: kind.uppercased(), tone: .blue)
            }
            GradeBadge(grade: status?.hub?.grade, score: status?.hub?.score)
            if let earnings, let days = earnings.days, days <= 7 {
                StateBadge(text: "EARNINGS · \(days)D", tone: .amber)
            }
        }
    }

    // MARK: - Chart (web view)

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("4H CANDLES · NY TIME")
                    .font(.system(size: 11, weight: .800))
                    .foregroundStyle(NSColor.muted)
                Spacer()
                Text("Live ticker page")
                    .font(.system(size: 11, weight: .600))
                    .foregroundStyle(NSColor.muted)
            }
            TickerWebView(symbol: symbol)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: NSLayout.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: NSLayout.cornerRadius).stroke(NSColor.line))
        }
    }

    // MARK: - Hub

    private var hubSection: some View {
        Group {
            if let hub = status?.hub {
                NSCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("HUB")
                                .font(.system(size: 11, weight: .800))
                                .foregroundStyle(NSColor.muted)
                            Spacer()
                            Text("\(hub.sessions ?? 0) sessions")
                                .font(.system(size: 12, weight: .600))
                                .foregroundStyle(NSColor.muted)
                        }
                        HStack {
                            Text(hub.low?.price ?? "—")
                            Text("–")
                            Text(hub.high?.price ?? "—")
                        }
                        .font(.system(size: 22, weight: .800))
                        if let pos = status?.pos {
                            // Position inside the hub: 0 = low, 1 = high.
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(NSColor.line).frame(height: 7)
                                    Capsule().fill(NSColor.blue)
                                        .frame(width: geo.size.width * CGFloat(min(max(pos, 0), 1)), height: 7)
                                }
                            }
                            .frame(height: 7)
                            Text(positionLine(pos))
                                .font(.system(size: 12))
                                .foregroundStyle(NSColor.muted)
                        }
                        if let toHigh = status?.toHighPct, let toLow = status?.toLowPct {
                            HStack {
                                Text("\(toHigh.signedPercent) to hub high")
                                Spacer()
                                Text("\(toLow.signedPercent) to hub low")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(NSColor.muted)
                        }
                    }
                }
            }
        }
    }

    private func positionLine(_ pos: Double) -> String {
        if pos >= 0.75 { return "Near the top of the hub — watch the high." }
        if pos <= 0.25 { return "Near the bottom of the hub — watch the low." }
        return "Resting inside the hub."
    }

    // MARK: - Triggers

    private var triggersSection: some View {
        Group {
            if let st = status, let hub = st.hub {
                let upTarget = st.shelfUp?.level ?? st.target
                let downTarget = st.shelfDown?.level ?? st.target
                HStack(spacing: 8) {
                    NSCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LONG TRIGGER")
                                .font(.system(size: 10, weight: .800))
                                .foregroundStyle(NSColor.muted)
                            Text("Close > \(hub.high?.price ?? "—")")
                                .font(.system(size: 15, weight: .700))
                            Text("Target \(upTarget?.price ?? "—")")
                                .font(.system(size: 12))
                                .foregroundStyle(NSColor.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    NSCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SHORT TRIGGER")
                                .font(.system(size: 10, weight: .800))
                                .foregroundStyle(NSColor.muted)
                            Text("Close < \(hub.low?.price ?? "—")")
                                .font(.system(size: 15, weight: .700))
                            Text("Target \(downTarget?.price ?? "—")")
                                .font(.system(size: 12))
                                .foregroundStyle(NSColor.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let target = st.target, let kind = st.targetKind {
                    Text("Live target \(target.price) — \(kind == "shelf" ? "next shelf" : "1× ATR"). Stop: a 4H close back inside the hub.")
                        .font(.system(size: 12))
                        .foregroundStyle(NSColor.muted)
                }
            }
        }
    }

    // MARK: - Gamma

    @ViewBuilder
    private var gammaSection: some View {
        if let walls = gamma?.walls {
            NSCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("GAMMA WALLS")
                            .font(.system(size: 11, weight: .800))
                            .foregroundStyle(NSColor.muted)
                        Spacer()
                        if let expiry = walls.expiry {
                            Text("Exp \(expiry)")
                                .font(.system(size: 12))
                                .foregroundStyle(NSColor.muted)
                        }
                    }
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Call wall").font(.system(size: 12)).foregroundStyle(NSColor.muted)
                            Text(walls.callWall?.price ?? "—").font(.system(size: 16, weight: .700))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Put wall").font(.system(size: 12)).foregroundStyle(NSColor.muted)
                            Text(walls.putWall?.price ?? "—").font(.system(size: 16, weight: .700))
                        }
                        if let flip = walls.flip {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Flip").font(.system(size: 12)).foregroundStyle(NSColor.muted)
                                Text(flip.price).font(.system(size: 16, weight: .700))
                            }
                        }
                    }
                    if let line = row?.gammaLine, !line.isEmpty {
                        Text(line).font(.system(size: 12)).foregroundStyle(NSColor.muted)
                    }
                    if row?.gammaCapped == true {
                        Text("The wall caps the target — take profit at the wall, not the shelf.")
                            .font(.system(size: 12, weight: .600))
                            .foregroundStyle(NSColor.amber)
                    }
                }
            }
        } else if let line = row?.gammaLine, !line.isEmpty {
            NSCard {
                Text(line).font(.system(size: 13)).foregroundStyle(NSColor.muted)
            }
        }
    }

    // MARK: - Options plan

    @ViewBuilder
    private var optionsSection: some View {
        if optionsUnavailable {
            NSCard {
                Text("Options plans are a Pro feature. The plan for this setup lives on the web.")
                    .font(.subheadline)
                    .foregroundStyle(NSColor.muted)
            }
        } else if let options, let plans = options.plans, !plans.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plans) { plan in
                    OptionsPlanCard(plan: plan)
                }
                if let message = options.message {
                    Text(message).font(.system(size: 12)).foregroundStyle(NSColor.muted)
                }
            }
        } else if let message = options?.message {
            NSCard {
                Text(message).font(.subheadline).foregroundStyle(NSColor.muted)
            }
        }
    }

    // MARK: - Earnings

    @ViewBuilder
    private var earningsSection: some View {
        if let earnings, let days = earnings.days, days <= 21 {
            NSCard {
                HStack(spacing: 10) {
                    Text("📅").font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Earnings \(earnings.label ?? earnings.date ?? "")")
                            .font(.system(size: 14, weight: .700))
                        Text(days <= 7
                             ? "Blackout: no new alerts into the print. Exit before it — holding through is a separate bet."
                             : "Reports in \(days) days. The run-up is the trade; never hold through the print.")
                            .font(.system(size: 12))
                            .foregroundStyle(NSColor.muted)
                    }
                }
            }
        }
    }

    // MARK: - Brokers

    private var brokerSection: some View {
        HStack(spacing: 8) {
            if let url = APIClient.webullURL(symbol: symbol, exchange: chart?.exchange ?? row?.exchange) {
                Link(destination: url) {
                    Text("Open in Webull")
                        .font(.system(size: 14, weight: .700))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(NSColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NSColor.line))
                }
                .buttonStyle(.plain)
            }
            if let url = APIClient.robinhoodURL(symbol: symbol) {
                Link(destination: url) {
                    Text("Open in Robinhood")
                        .font(.system(size: 14, weight: .700))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(NSColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NSColor.line))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rulesFooter: some View {
        Text("Rules: take profit at the shelf · exit on a 4H close back inside · size small. The close is the trigger, not the wick. Not financial advice.")
            .font(.system(size: 12))
            .foregroundStyle(NSColor.muted)
    }

    // MARK: - Watch / unwatch

    @ViewBuilder
    private var watchButton: some View {
        if session.isSignedIn {
            Button {
                Task { await toggleWatch() }
            } label: {
                Image(systemName: (watching ?? false) ? "star.fill" : "star")
                    .foregroundStyle((watching ?? false) ? NSColor.amber : NSColor.ink)
            }
            .disabled(watching == nil && chart == nil)
        }
    }

    private func toggleWatch() async {
        watchError = nil
        do {
            if watching == true {
                _ = try await api.removeTicker(symbol)
                watching = false
            } else {
                _ = try await api.addTicker(symbol)
                watching = true
            }
        } catch {
            watchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Options plan card

struct OptionsPlanCard: View {
    let plan: OptionsPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("OPTIONS PLAN")
                    .font(.system(size: 11, weight: .800))
                    .foregroundStyle(Color(red: 0.58, green: 0.77, blue: 1.0))
                Spacer()
                if let first = plan.contracts?.first, let iv = first.iv {
                    Text("IV \(String(format: "%.1f%%", iv))")
                        .font(.system(size: 11, weight: .700))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            if let contract = plan.contracts?.first, let expiry = plan.expiry {
                Text("\(expiryLabel(expiry)) \(contract.strike?.price ?? "") \(plan.side ?? "")s · \(contract.mid?.price ?? "") mid")
                    .font(.system(size: 14, weight: .700))
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Max loss").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7))
                        Text(contract.cost.map { String.money($0, digits: 2) } ?? "—")
                            .font(.system(size: 14, weight: .700))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Est. at aim").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7))
                        if let pct = contract.atShelfPct {
                            Text(String(format: "%+.0f%%", pct))
                                .font(.system(size: 14, weight: .700))
                                .foregroundStyle(NSColor.up)
                        } else {
                            Text("—").font(.system(size: 14, weight: .700))
                        }
                    }
                    if let count = plan.contracts?.count, count > 1 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Also").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7))
                            Text("\(count) contracts").font(.system(size: 14, weight: .700))
                        }
                    }
                }
                if let history = plan.history, let n = history.n, n > 0 {
                    Text("Reached the aim in \(history.reached ?? 0) of \(n) past setups like this.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                if contract.wideSpread == true {
                    Text("Wide spread — size down or wait for a tighter quote.")
                        .font(.system(size: 12, weight: .600))
                        .foregroundStyle(NSColor.amber)
                }
                if contract.estimated == true {
                    Text("Quote estimated with the stock at the hub edge, not where it is now.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            } else {
                Text("No listed options found for this setup.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .padding(14)
        .background(Color(red: 0.06, green: 0.09, blue: 0.16))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: NSLayout.cornerRadius))
    }

    private func expiryLabel(_ iso: String) -> String {
        ServerDate.shortDate(iso) ?? iso
    }
}
