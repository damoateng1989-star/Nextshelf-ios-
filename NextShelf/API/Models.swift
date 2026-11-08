import Foundation

// MARK: - Decoding helpers
//
// The server is FastAPI + snake_case JSON. The client decodes with
// `.convertFromSnakeCase` (see APIClient), so Swift properties use
// camelCase and no per-field CodingKeys are needed — except where a key
// contains a hyphen (`follow-through`), which is handled with explicit
// CodingKeys on that one struct.
//
// Two fields are loosely typed on the server and need a flexible read:
// `chase` is an int (0/1) in the record's DB rows and a bool in live
// engine output. `decodeFlexibleBool` accepts either.

extension KeyedDecodingContainer {
    func decodeFlexibleBool(forKey key: Key) throws -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key), let b { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i.map { $0 != 0 } }
        return nil
    }
}

// MARK: - Auth

/// GET /auth/config — {google, free_limit, signups_open}
struct AuthConfig: Decodable {
    var google: Bool?
    var freeLimit: Int?
    var signupsOpen: Bool?
}

/// GET /api/me — guest: {guest, plan: "guest", is_admin, ticker_limit}.
/// Signed in: everything below. All fields optional so a guest payload
/// and a signed-in payload decode through the same model.
struct MeResponse: Decodable {
    var guest: Bool?
    var email: String?
    var name: String?
    /// "guest" | "free" | "pro"
    var plan: String?
    var isAdmin: Bool?
    /// Free tier cap; nil for Pro (unlimited). Guest: the free limit.
    var tickerLimit: Int?
    var telegram: TelegramInfo?
    var phone: String?
    var callsAvailable: Bool?
    var hasPassword: Bool?
    var google: Bool?
    /// Style keys the member currently watches (e.g. ["hub"]).
    var styles: [String]?
    /// Options plans available to this member (Pro, or all while
    /// OPTIONS_FOR_ALL is on server-side).
    var options: Bool?
    var brief: Bool?
    var recap: Bool?
    var recapTime: String?
    /// "HH:MM-HH:MM" or "".
    var quiet: String?
    /// "both" (both closes) or "midday" (1:30 PM close only).
    var closes: String?
    var briefTime: String?
    var emailOn: Bool?
    var stylesPicked: [String]?
    var styleOptions: [StyleOption]?

    var isGuest: Bool { guest == true || plan == "guest" }
    var isPro: Bool { plan == "pro" }
    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let email { return email }
        return "Member"
    }
    var firstName: String { displayName.split(separator: " ").first.map(String.init) ?? displayName }
}

struct TelegramInfo: Decodable {
    var enabled: Bool?
    var linked: Bool?
    /// t.me/<bot>?start=<code> — open in Safari to link.
    var link: String?
}

struct StyleOption: Decodable, Identifiable {
    var key: String
    var name: String
    var about: String
    var id: String { key }
}

// MARK: - Board

/// GET /api/board — regime comes from HERE, not /api/info (the spec said
/// /api/info; live code puts it on the board payload).
/// Guest: counts only (live/near/forming empty, *_count set, locked).
/// Free with the lock on: live/near empty, live_count/near_count set,
/// setups filtered to non-timely states, setups_locked counted.
struct BoardResponse: Decodable {
    var updated: String?
    var universe: Int?
    var guest: Bool?
    var locked: Bool?
    var liveCount: Int?
    var nearCount: Int?
    var formingCount: Int?
    var live: [BoardRow]?
    var near: [BoardRow]?
    var forming: [BoardRow]?
    var recent: [BoardRow]?
    var setups: [SetupRow]?
    var setupsLocked: Int?
    var regime: Regime?
}

/// Stored market regime: {"regime": "up"|"down", "close", "sma",
/// "index": "SPY", "days": 50, "as_of"}. Display only — the client
/// never computes it.
struct Regime: Decodable {
    var regime: String?
    var close: Double?
    var sma: Double?
    var index: String?
    var days: Int?
    var asOf: String?

    var isDown: Bool { regime == "down" }
    var isUp: Bool { regime == "up" }
}

/// One board row. This is `engine.current_status` + `_board_status`,
/// with `symbol`/`watching`/`exchange`/gamma fields added by `board()`.
/// `symbol` is optional because the same shape is reused for
/// /api/tickers `status` (where the symbol sits beside it).
struct BoardRow: Decodable, Identifiable {
    var symbol: String?
    var lastClose: Double?
    var lastCandle: String?
    var lastCandleClose: String?
    /// none | forming | watching | breakout_up | breakdown |
    /// follow-through | snap-back | stalled
    var state: String?
    var label: String?
    var hub: Hub?
    var spark: [Double]?
    var shelfUp: Shelf?
    var shelfDown: Shelf?
    var target: Double?
    /// "up" | "down" (breakout direction)
    var direction: String?
    /// "shelf" | "atr"
    var targetKind: String?
    var targetZone: PriceZone?
    /// 0 = at hub low, 1 = at hub high (forming/watching only).
    var pos: Double?
    var toHighPct: Double?
    var toLowPct: Double?
    /// "up" | "down" | null — price within 25% of an edge.
    var nearEdge: String?
    var toTargetPct: Double?
    /// Relative volume on the breakout candle (info only).
    var rvol: Double?
    var oldHigh: Double?
    var oldLow: Double?
    var watching: Bool?
    /// Webull slug: "nasdaq" | "nyse" | "nysearca" | "amex" | null.
    var exchange: String?
    var gammaLine: String?
    var gammaCapped: Bool?
    var gammaWall: Double?
    /// 20-day average daily dollar volume (rounded), when measurable.
    var dv20: Double?
    /// Market cap in dollars, when known (ETFs exempt).
    var mc: Double?
    /// Non-hub setups on this symbol (present on /api/tickers status,
    /// stripped from /api/board hub rows).
    var setups: [SetupRow]?

    var id: String { symbol ?? UUID().uuidString }

    var isBreakout: Bool { state == "breakout_up" || state == "breakdown" }
    var isShort: Bool { state == "breakdown" || direction == "down" }
}

struct Hub: Decodable {
    var low: Double?
    var high: Double?
    var sessions: Int?
    /// "warehouse" | "ledge"
    var grade: String?
    /// 0–6 (Patch 28 grading).
    var score: Double?
    var start: String?
    var end: String?
    var sparkFrom: Int?
    var sparkTo: Int?
}

struct Shelf: Decodable {
    var low: Double?
    var high: Double?
    /// The take-profit level of this shelf.
    var level: Double?
    var sparkFrom: Int?
    var sparkTo: Int?
    /// True when this shelf is the trade's target.
    var target: Bool?
}

struct PriceZone: Decodable {
    var low: Double?
    var high: Double?
}

/// One non-hub setup row (patterns.live_json). Only the fields the UI
/// shows are modelled; chart-line points are omitted (v1 chart is a web
/// view). Every field optional — rows vary by kind and state.
struct SetupRow: Decodable, Identifiable {
    /// Present on /api/board's `setups` group (added by board()).
    var symbol: String?
    var kind: String?
    var name: String?
    var style: String?
    /// breakout_up | breakdown | testing | forming | between
    var state: String?
    var edge: Double?
    var target: Double?
    var targetKind: String?
    var candles: Int?
    var since: String?
    var toTargetPct: Double?
    var touches: Int?
    var stop: Double?
    var gapPct: Double?
    var gapDay: String?
    var candlesUnit: String?
    var near: String?
    var upper: Double?
    var lower: Double?
    var upperTouches: Int?
    var lowerTouches: Int?
    var sessions: Int?
    var nearEdge: String?
    var neck: Double?
    var peak: Double?
    var trigger: String?
    var polePct: Double?
    var daysLeft: Int?
    var sessionsUnit: String?

    var id: String { "\(symbol ?? "?")-\(kind ?? "?")-\(state ?? "?")" }
}

// MARK: - Info

/// GET /api/info — public facts for the board header. Note: NO regime
/// here (it lives on /api/board). preclose_times is [] for non-Pro.
struct InfoResponse: Decodable {
    var storageOk: Bool?
    var universeName: String?
    var universeSize: Int?
    var liquidSymbols: [String]?
    var skippedIlliquid: Int?
    var skippedSmallcap: Int?
    var provider: String?
    var telegram: Bool?
    var telegramLinked: Bool?
    var phone: Bool?
    var callOn: [String]?
    var scanTimes: [String]?
    var precloseTimes: [String]?
    var entryTimes: [String]?
    var boardTimes: [String]?
    var settings: InfoSettings?
}

struct InfoSettings: Decodable {
    var minSessions: Int?
    var k: Double?
    var horizon: Int?
    var targetAtr: Double?
    var shelfMinAtr: Double?
}

// MARK: - Chart

/// GET /api/chart/{symbol}?tf=4h — candles + hubs + trades + status +
/// stats. v1 uses the candles only indirectly: the chart itself is the
/// ticker page in a WKWebView. The native card reads `status` + `stats`.
struct ChartResponse: Decodable {
    var symbol: String?
    var tf: String?
    var candles: [Candle]?
    var hubs: [ChartHub]?
    var trades: [ChartTrade]?
    var status: BoardRow?
    var stats: ChartStats?
    var watching: Bool?
    var guest: Bool?
    var exchange: String?
}

struct Candle: Decodable {
    /// UTC seconds (labels read in New York time).
    var time: Int?
    var open: Double?
    var high: Double?
    var low: Double?
    var close: Double?
    var volume: Int?
}

struct ChartHub: Decodable {
    var start: Int?
    var end: Int?
    var low: Double?
    var high: Double?
    var sessions: Int?
    var active: Bool?
}

struct ChartTrade: Decodable {
    var time: Int?
    var direction: Int?
    var target: Double?
    var outcome: String?
    var chase: Bool?
    var outcomeTime: Int?

    enum CodingKeys: String, CodingKey {
        case time, direction, target, outcome, chase
        case outcomeTime = "outcome_time"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decodeIfPresent(Int.self, forKey: .time)
        direction = try c.decodeIfPresent(Int.self, forKey: .direction)
        target = try c.decodeIfPresent(Double.self, forKey: .target)
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        chase = try c.decodeFlexibleBool(forKey: .chase)
        outcomeTime = try c.decodeIfPresent(Int.self, forKey: .outcomeTime)
    }
}

struct ChartStats: Decodable {
    var n: Int?
    var followThrough: Double?
    var snapBack: Double?
    var stalled: Double?
    var avgFwdPct: Double?
    var trades: Int?
    var winRate: Double?
    var avgWinPct: Double?
    var avgLossPct: Double?
    var expectancyPct: Double?
    var up: ChartStatsDirection?
    var down: ChartStatsDirection?

    enum CodingKeys: String, CodingKey {
        case n, trades, up, down
        case followThrough = "follow-through"
        case snapBack = "snap-back"
        case stalled
        case avgFwdPct = "avg_fwd_pct"
        case winRate = "win_rate"
        case avgWinPct = "avg_win_pct"
        case avgLossPct = "avg_loss_pct"
        case expectancyPct = "expectancy_pct"
    }
}

struct ChartStatsDirection: Decodable {
    var n: Int?
    var followThrough: Double?

    enum CodingKeys: String, CodingKey {
        case n
        case followThrough = "follow-through"
    }
}

// MARK: - Options plan

/// GET /api/options/{symbol} — 403 "Options plans are a Pro feature"
/// when the server gate is off (OPTIONS_FOR_ALL defaults on, so most
/// signed-in members get plans today; the client handles 403 anyway).
struct OptionsPlanResponse: Decodable {
    var symbol: String?
    var price: Double?
    var demo: Bool?
    var plans: [OptionsPlan]?
    /// "live" | "prep" | "none"
    var mode: String?
    var earnings: EarningsEntry?
    /// Set when there is no plan (e.g. "No breakout or hub right now…").
    var message: String?
    var marketOpen: Bool?
    var asOf: String?
    var session: String?
    var timing: [String: Double]?
}

struct OptionsPlan: Decodable, Identifiable {
    var direction: Int?
    /// "call" | "put"
    var side: String?
    var setup: String?
    /// "live" | "prep"
    var mode: String?
    var entry: Double?
    var edge: Double?
    var target: Double?
    var targetKind: String?
    var targetPct: Double?
    var expiry: String?
    var dte: Int?
    var contracts: [OptionContract]?
    var history: OptionsHistory?
    var daysToTarget: Double?
    var failPx: Double?

    var id: String { "\(side ?? "?")-\(expiry ?? "?")-\(mode ?? "?")" }
    var isCall: Bool { direction == 1 }
}

struct OptionContract: Decodable, Identifiable {
    var label: String?
    var symbol: String?
    var strike: Double?
    var bid: Double?
    var ask: Double?
    var mid: Double?
    var delta: Double?
    /// Percent (e.g. 50.6), not a decimal.
    var iv: Double?
    var breakeven: Double?
    /// Max loss per contract, dollars.
    var cost: Double?
    var atShelf: Double?
    var atShelfPct: Double?
    var atFail: Double?
    var atFailPct: Double?
    var wideSpread: Bool?
    var quoteNow: Double?
    /// True when the quote is estimated (prep mode, stock at the edge).
    var estimated: Bool?

    var id: String { "\(label ?? "?")-\(strike ?? 0)" }
}

struct OptionsHistory: Decodable {
    var n: Int?
    var reached: Int?
    var reachedPct: Double?
    var medianDays: Double?
    var slowestDays: Double?
}

// MARK: - Gamma

/// GET /api/gamma/{symbol} — {symbol, walls}. Fail-open: walls is null
/// when there is no chain or no spot.
struct GammaResponse: Decodable {
    var symbol: String?
    var walls: GammaWalls?
}

struct GammaWalls: Decodable {
    var callWall: Double?
    var putWall: Double?
    var flip: Double?
    var expiry: String?
}

// MARK: - Earnings

/// GET /api/earnings?symbols=A,B — {SYM: {date, days, when, label}}.
/// Only symbols reporting within ~3 weeks appear.
struct EarningsEntry: Decodable {
    var date: String?
    var days: Int?
    /// "bmo" | "amc" | "" (before market open / after market close).
    var when: String?
    var label: String?
}

// MARK: - Watchlist

/// GET /api/tickers — [{symbol, scanned_at, status}]. `status` is the
/// board-status dict for the symbol (same shape as BoardRow).
struct WatchlistItem: Decodable, Identifiable {
    var symbol: String
    var scannedAt: String?
    var status: BoardRow?

    var id: String { symbol }
}

/// POST /api/tickers — {symbol, status, created}. 402 when the Free
/// cap is hit ("Free accounts can watch N tickers…").
struct AddTickerResponse: Decodable {
    var symbol: String?
    var status: BoardRow?
    var created: Bool?
}

// MARK: - Record

/// GET /api/record?pattern=hub — signed-in only (guests get 401; the
/// guest record view uses /api/public/summary instead).
struct RecordResponse: Decodable {
    var since: String?
    var stats: RecordStats?
    /// Up to 200 most recent signals.
    var signals: [RecordSignal]?
    var pattern: String?
    var patterns: [String: PatternSummary]?
    var bySymbol: [SymbolRecord]?
}

struct RecordStats: Decodable {
    var signals: Int?
    var closed: Int?
    var open: Int?
    var chases: Int?
    var againstTrend: Int?
    var winRate: Double?
    var avgRet: Double?
    var avgWin: Double?
    var avgLoss: Double?
    var byOutcome: [String: Int]?
    var byVolume: [String: SplitStats]?
    var byGrade: [String: SplitStats]?
}

struct SplitStats: Decodable {
    var n: Int?
    var reached: Int?
    var winRate: Double?
    var avgRet: Double?
}

struct PatternSummary: Decodable {
    var signals: Int?
    var closed: Int?
    /// Reached-the-shelf percent.
    var reached: Double?
    var winRate: Double?
    var avgRet: Double?
    var name: String?
}

struct SymbolRecord: Decodable, Identifiable {
    var symbol: String?
    var n: Int?
    var wins: Int?
    var winRate: Double?
    var avgRet: Double?
    var id: String { symbol ?? UUID().uuidString }
}

/// One logged setup. `chase` arrives as 0/1 from the DB.
struct RecordSignal: Decodable, Identifiable {
    var id: String?
    var pattern: String?
    var symbol: String?
    var direction: Int?
    var hubLow: Double?
    var hubHigh: Double?
    var hubSessions: Int?
    var breakoutTime: String?
    var entry: Double?
    var target: Double?
    var targetKind: String?
    var outcome: String?
    var outcomeTime: String?
    var retPct: Double?
    var chase: Bool?
    var regime: String?
    var grade: String?
    var rvol: Double?

    enum CodingKeys: String, CodingKey {
        case id, pattern, symbol, direction, outcome, regime, grade, rvol
        case hubLow = "hub_low"
        case hubHigh = "hub_high"
        case hubSessions = "hub_sessions"
        case breakoutTime = "breakout_time"
        case entry, target
        case targetKind = "target_kind"
        case outcomeTime = "outcome_time"
        case retPct = "ret_pct"
        case chase
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        direction = try c.decodeIfPresent(Int.self, forKey: .direction)
        hubLow = try c.decodeIfPresent(Double.self, forKey: .hubLow)
        hubHigh = try c.decodeIfPresent(Double.self, forKey: .hubHigh)
        hubSessions = try c.decodeIfPresent(Int.self, forKey: .hubSessions)
        breakoutTime = try c.decodeIfPresent(String.self, forKey: .breakoutTime)
        entry = try c.decodeIfPresent(Double.self, forKey: .entry)
        target = try c.decodeIfPresent(Double.self, forKey: .target)
        targetKind = try c.decodeIfPresent(String.self, forKey: .targetKind)
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        outcomeTime = try c.decodeIfPresent(String.self, forKey: .outcomeTime)
        retPct = try c.decodeIfPresent(Double.self, forKey: .retPct)
        chase = try c.decodeFlexibleBool(forKey: .chase)
        regime = try c.decodeIfPresent(String.self, forKey: .regime)
        grade = try c.decodeIfPresent(String.self, forKey: .grade)
        rvol = try c.decodeIfPresent(Double.self, forKey: .rvol)
    }
}

/// GET /api/public/summary — public record strip for the guest view.
struct PublicSummary: Decodable {
    var updated: String?
    var universe: Int?
    var forming: Int?
    var live: Int?
    var near: Int?
    var signals: Int?
    var closed: Int?
    var open: Int?
    var reached: Int?
    var reachedPct: Int?
    var winRate: Double?
    var avgRet: Double?
    var next: String?
    var times: [String]?
}

// MARK: - Paper (admin only)
//
// GET /api/paper requires Admin on the server. The client calls it
// ONLY when me.is_admin is true; everyone else never sees the section.

struct PaperSummary: Decodable {
    var enabled: Bool?
    var broker: String?
    var tradeUsd: Double?
    var allowShort: Bool?
    var source: String?
    var dailyMax: Int?
    var maxOpen: Int?
    var goal: Int?
    var stats: PaperStats?
    var open: [PaperTrade]?
    var closed: [PaperTrade]?
}

struct PaperStats: Decodable {
    var closed: Int?
    var wins: Int?
    var winRate: Double?
    var totalPnl: Double?
    var avgPct: Double?
}

struct PaperTrade: Decodable, Identifiable {
    var id: String?
    var symbol: String?
    var direction: Int?
    var qty: Double?
    var entryPrice: Double?
    var target: Double?
    var status: String?
    var pnl: Double?
    var pnlPct: Double?
    var lastPrice: Double?
    var unrealPct: Double?
    var unreal: Double?
    var openedAt: String?
    var closedAt: String?
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case id, symbol, direction, qty, status, pnl, reason
        case entryPrice = "entry_price"
        case target
        case pnlPct = "pnl_pct"
        case lastPrice = "last_price"
        case unrealPct = "unreal_pct"
        case unreal
        case openedAt = "opened_at"
        case closedAt = "closed_at"
    }
}

// MARK: - Small request bodies

struct LoginRequest: Encodable {
    var email: String
    var password: String
}

struct SignupRequest: Encodable {
    var email: String
    var password: String
    var name: String
    var invite: String
}

struct EmailRequest: Encodable {
    var email: String
}

struct ResetRequest: Encodable {
    var token: String
    var password: String
}

struct BoolRequest: Encodable {
    var on: Bool
}

struct ClosesRequest: Encodable {
    var closes: String
}

struct QuietRequest: Encodable {
    var on: Bool
    var start: String
    var end: String
}

struct StylesRequest: Encodable {
    var styles: [String]
}

struct PhoneRequest: Encodable {
    var phone: String
}

struct AddTickerRequest: Encodable {
    var symbol: String
}

/// FastAPI error body: {"detail": "..."} — or, for validation errors,
/// {"detail": [{"msg": "...", ...}]}.
struct ErrorBody: Decodable {
    var detail: DetailValue?

    enum DetailValue: Decodable {
        case string(String)
        case list([ValidationError])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .string(s); return }
            if let l = try? c.decode([ValidationError].self) { self = .list(l); return }
            self = .string("Something went wrong.")
        }

        var message: String {
            switch self {
            case .string(let s): return s
            case .list(let l): return l.first?.msg ?? "Something went wrong."
            }
        }
    }

    struct ValidationError: Decodable {
        var msg: String?
    }
}
