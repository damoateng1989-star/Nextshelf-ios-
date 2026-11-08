import SwiftUI

/// Alerts & settings.
///
/// Every toggle maps to a real endpoint on the server. Two rows the
/// mockup shows as switches do NOT have an API toggle, so they render
/// as status rows instead of fake switches:
///   - Breakout alerts: delivered for your watchlist via Telegram;
///     there is no per-user on/off in /api/me.
///   - Pre-close warnings: a Pro-only alert type, gated server-side.
/// Faking a switch that writes nothing would be worse than saying so.
struct AlertsSettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var me: MeResponse?
    @State private var isLoading = false
    @State private var error: String?
    @State private var notice: String?
    @State private var phoneDraft = ""
    @State private var selectedStyles: Set<String> = []
    @State private var quietOn = false
    @State private var quietStart = Date()
    @State private var quietEnd = Date()

    private var api: APIClient { .shared }

    var body: some View {
        Group {
            if !session.isSignedIn && !session.isGuest {
                EmptyStateView(title: "Sign in to manage alerts",
                               message: "Alert settings live on your account.")
            } else if session.isGuest {
                EmptyStateView(title: "Alerts need an account",
                               message: "Guests can browse the board. Sign in (free) to connect Telegram and set up alerts.")
            } else {
                form
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private var form: some View {
        List {
            if let notice {
                Section {
                    Text(notice)
                        .font(.subheadline)
                        .foregroundStyle(NSColor.blue)
                }
            }

            telegramSection
            notificationsSection
            quietSection
            stylesSection
            phoneSection
            planSection

            Section {
                Button("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
            }

            if let error {
                Section { Text(error).font(.subheadline).foregroundStyle(NSColor.down) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NSColor.paper)
    }

    // MARK: - Telegram

    private var telegramSection: some View {
        Section {
            if me?.telegram?.linked == true {
                HStack(spacing: 10) {
                    Text("✈️").font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Telegram — Connected ✓")
                            .font(.system(size: 14, weight: .700))
                        Text("Breakouts, pre-close warnings and paper entries land here today. Push joins it in M5 — no duplicates.")
                            .font(.system(size: 12))
                            .foregroundStyle(NSColor.muted)
                    }
                }
                Button("Disconnect Telegram", role: .destructive) {
                    Task {
                        do {
                            _ = try await api.unlinkTelegram()
                            notice = "Telegram disconnected. Your link code changed — reconnect to get alerts again."
                            await load()
                        } catch {
                            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }
            } else if let link = me?.telegram?.link, let url = URL(string: link) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Telegram — Not connected")
                        .font(.system(size: 14, weight: .700))
                    Text("Breakout alerts, pre-close warnings and the morning brief go to Telegram. Tap to link — it takes one message.")
                        .font(.system(size: 12))
                        .foregroundStyle(NSColor.muted)
                    Link("Connect Telegram →", destination: url)
                        .font(.system(size: 14, weight: .700))
                        .foregroundStyle(NSColor.blue)
                }
            } else {
                Text("Telegram isn't set up on the server yet.")
                    .font(.subheadline)
                    .foregroundStyle(NSColor.muted)
            }
        } header: {
            Text("How NextShelf reaches you")
        }
    }

    // MARK: - Notifications (real toggles)

    private var notificationsSection: some View {
        Section("Notifications") {
            if let me {
                Toggle("Breakout alerts", isOn: .constant(true))
                    .disabled(true)
                Text("On for your watchlist, on a 4H close through the edge. There is no per-user off switch — remove a ticker to stop its alerts.")
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)

                Toggle("Pre-close warning", isOn: .constant(me.isPro))
                    .disabled(true)
                Text(me.isPro
                     ? "Pro: 1:15 PM ET, before the verdict candle."
                     : "Pro only — 1:15 PM ET, before the verdict candle.")
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)

                Toggle("Morning brief", isOn: Binding(
                    get: { me.brief ?? false },
                    set: { v in Task { await saveBrief(v) } }))
                Text("Weekdays\(me.briefTime.map { " · \($0) ET" } ?? "") · Hubs forming now.")
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)

                Toggle("Evening recap", isOn: Binding(
                    get: { me.recap ?? false },
                    set: { v in Task { await saveRecap(v) } }))
                Text("Weekdays\(me.recapTime.map { " · \($0) ET" } ?? "") · What closed, what triggered.")
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)

                Picker("Alert closes", selection: Binding(
                    get: { me.closes ?? "both" },
                    set: { v in Task { await saveCloses(v) } })) {
                    Text("Both closes").tag("both")
                    Text("1:30 PM only").tag("midday")
                }
                Text("Both closes = 1:30 PM verdict + 4:00 PM confirmation. Midday only = the 1:30 PM close.")
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)
            }
        }
    }

    // MARK: - Quiet hours

    private var quietSection: some View {
        Section("Quiet hours") {
            Toggle("Quiet hours", isOn: Binding(
                get: { quietOn },
                set: { v in Task { await saveQuiet(on: v) } }))
            if quietOn {
                DatePicker("From", selection: $quietStart, displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: $quietEnd, displayedComponents: .hourAndMinute)
                Button("Save quiet hours") {
                    Task { await saveQuiet(on: true) }
                }
                .font(.system(size: 14, weight: .600))
            }
            Text("No alerts inside quiet hours. Pre-close warnings still fire — they are time-critical.")
                .font(.system(size: 12))
                .foregroundStyle(NSColor.muted)
        }
    }

    // MARK: - Setup styles

    private var stylesSection: some View {
        Section("Setup styles") {
            if let options = me?.styleOptions, !options.isEmpty {
                ForEach(options) { option in
                    Button {
                        if selectedStyles.contains(option.key) {
                            selectedStyles.remove(option.key)
                        } else {
                            selectedStyles.insert(option.key)
                        }
                        Task { await saveStyles() }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name).font(.system(size: 14, weight: .600))
                                Text(option.about).font(.system(size: 12)).foregroundStyle(NSColor.muted)
                            }
                            Spacer()
                            if selectedStyles.contains(option.key) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(NSColor.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("No setup styles to pick from.")
                    .font(.subheadline)
                    .foregroundStyle(NSColor.muted)
            }
        }
    }

    // MARK: - Phone (Pro)

    private var phoneSection: some View {
        Section("Phone calls — Pro") {
            if me?.isPro == true {
                TextField("Phone number", text: $phoneDraft)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                Button("Save number") {
                    Task {
                        do {
                            let out = try await api.setPhone(phoneDraft)
                            notice = "Number saved: \(out.phone ?? phoneDraft)."
                            await load()
                        } catch {
                            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }
                .font(.system(size: 14, weight: .600))
                Button("Test call") {
                    Task {
                        do {
                            _ = try await api.testCall()
                            notice = "Test call placed — your phone should ring in a moment."
                        } catch {
                            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }
                .font(.system(size: 14, weight: .600))
                Text("For live breakouts only. Calls are placed by the server — the app never dials.")
                    .font(.system(size: 12))
                    .foregroundStyle(NSColor.muted)
            } else {
                Text("Phone-call alerts are a Pro feature. Upgrade on the web to get a call when a live setup breaks out.")
                    .font(.subheadline)
                    .foregroundStyle(NSColor.muted)
                Link("See Pro on the web →", destination: URL(string: "https://nextshelfapp.com/pricing")!)
                    .font(.system(size: 14, weight: .700))
                    .foregroundStyle(NSColor.blue)
            }
        }
    }

    // MARK: - Plan

    private var planSection: some View {
        Section("Plan") {
            if let me {
                HStack {
                    Text("Plan").font(.system(size: 14, weight: .600))
                    Spacer()
                    StateBadge(text: (me.plan ?? "free").uppercased(), tone: me.isPro ? .up : .neutral)
                }
                if me.isPro {
                    Text("Pro is managed on the web — renewals and billing live there, not in the app.")
                        .font(.system(size: 12))
                        .foregroundStyle(NSColor.muted)
                } else {
                    Link("Upgrade to Pro on the web →", destination: URL(string: "https://nextshelfapp.com/pricing")!)
                        .font(.system(size: 14, weight: .700))
                        .foregroundStyle(NSColor.blue)
                }
                if let email = me.email {
                    Text(email).font(.system(size: 12)).foregroundStyle(NSColor.muted)
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        if me == nil { isLoading = true }
        error = nil
        do {
            let fresh = try await api.me()
            me = fresh
            await session.refreshMe()
            phoneDraft = fresh.phone ?? ""
            selectedStyles = Set(fresh.stylesPicked ?? [])
            parseQuiet(fresh.quiet)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func parseQuiet(_ quiet: String?) {
        guard let quiet, !quiet.isEmpty else {
            quietOn = false
            return
        }
        let parts = quiet.split(separator: "-").map(String.init)
        guard parts.count == 2 else { quietOn = false; return }
        quietOn = true
        quietStart = timeOfDay(parts[0]) ?? quietStart
        quietEnd = timeOfDay(parts[1]) ?? quietEnd
    }

    private func timeOfDay(_ hhmm: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.date(from: hhmm)
    }

    private func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func saveBrief(_ on: Bool) async {
        do { _ = try await api.setBrief(on: on); await load() }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    private func saveRecap(_ on: Bool) async {
        do { _ = try await api.setRecap(on: on); await load() }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    private func saveCloses(_ closes: String) async {
        do { _ = try await api.setCloses(closes); await load() }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    private func saveQuiet(on: Bool) async {
        do {
            _ = try await api.setQuiet(on: on, start: hhmm(quietStart), end: hhmm(quietEnd))
            await load()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveStyles() async {
        guard !selectedStyles.isEmpty else { return }
        do {
            _ = try await api.setStyles(Array(selectedStyles))
            await load()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
