import SwiftUI

// MARK: - Welcome / sign in
//
// Flow adapts Regulur's LoginVC / SignUpVC / WelcomeLoginViewController
// / ForgotPasswordVC: welcome → login/signup → forgot password. Dropped:
// Facebook login and phone/SMS verification. NextShelf needs
// email/password + Google only. Session storage is the cookie session,
// not UserDefaults.

struct WelcomeView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showForgot = false
    @State private var showGoogle = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 28)

                // Brand mark (logo set: logo-app-icon for the hero tile).
                Image("AppIconTile")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 74, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)

                VStack(spacing: 6) {
                    Text("NextShelf")
                        .font(NSFont.serif(size: 30, weight: .bold))
                    Text("Hub-breakout scanner for swing traders with day jobs.")
                        .font(.subheadline)
                        .foregroundStyle(NSColor.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }

                VStack(spacing: 10) {
                    if session.authConfig?.google == true {
                        Button {
                            showGoogle = true
                        } label: {
                            HStack(spacing: 8) {
                                Text("G")
                                    .font(.system(size: 17, weight: .800))
                                    .foregroundStyle(NSColor.blue)
                                Text("Continue with Google")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(NSColor.card)
                            .foregroundStyle(NSColor.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(NSColor.line))
                        }
                        .buttonStyle(.plain)

                        HStack {
                            Rectangle().fill(NSColor.line).frame(height: 1)
                            Text("OR WITH EMAIL")
                                .font(.system(size: 11, weight: .700))
                                .foregroundStyle(NSColor.muted)
                            Rectangle().fill(NSColor.line).frame(height: 1)
                        }
                    }

                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(NSColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NSColor.line))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(12)
                        .background(NSColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NSColor.line))

                    Button {
                        Task { await session.signIn(email: email, password: password) }
                    } label: {
                        if session.isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Text("Sign in")
                        }
                    }
                    .buttonStyle(NSPrimaryButtonStyle())
                    .disabled(email.isEmpty || password.isEmpty || session.isBusy)

                    HStack {
                        Button("Forgot password?") { showForgot = true }
                            .foregroundStyle(NSColor.blue)
                        Spacer()
                        Button("Create account →") { showSignUp = true }
                            .foregroundStyle(NSColor.ink)
                    }
                    .font(.system(size: 13, weight: .600))
                }
                .apiErrorBanner(session.errorMessage)

                Button("Browse as a guest") {
                    session.enterAsGuest()
                }
                .font(.system(size: 13, weight: .600))
                .foregroundStyle(NSColor.muted)

                NSCard {
                    Text("Free to look around. ")
                        .font(.system(size: 13, weight: .700)) +
                    Text("Guests see counts. Free sees the board shape. Pro sees every live setup.")
                        .font(.system(size: 13))
                }
                .foregroundStyle(NSColor.ink)

                Text("By continuing you agree to Terms & Privacy.\nNot financial advice.")
                    .font(.system(size: 11))
                    .foregroundStyle(NSColor.muted)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .background(NSColor.paper)
        .sheet(isPresented: $showSignUp) { SignUpView() }
        .sheet(isPresented: $showForgot) { ForgotPasswordView() }
        .sheet(isPresented: $showGoogle) {
            GoogleAuthView(onDone: { showGoogle = false })
        }
    }
}

// MARK: - Sign up

struct SignUpView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var invite = ""

    private var signupsOpen: Bool { session.authConfig?.signupsOpen ?? true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Create your account")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !signupsOpen {
                        NSCard {
                            Text("Signups are invite-only right now. Enter your invite code below — or join the waitlist on the web.")
                                .font(.subheadline)
                        }
                    }

                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .padding(12).background(NSColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NSColor.line))
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(12).background(NSColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NSColor.line))
                    SecureField("Password (8+ characters)", text: $password)
                        .textContentType(.newPassword)
                        .padding(12).background(NSColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NSColor.line))
                    if !signupsOpen {
                        TextField("Invite code", text: $invite)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(12).background(NSColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(NSColor.line))
                    }

                    Button {
                        Task {
                            if await session.signUp(email: email, password: password,
                                                    name: name, invite: invite) {
                                dismiss()
                            }
                        }
                    } label: {
                        if session.isBusy { ProgressView().tint(.white) } else { Text("Create account") }
                    }
                    .buttonStyle(NSPrimaryButtonStyle())
                    .disabled(!email.isValidEmail || password.count < 8 || session.isBusy)
                }
                .apiErrorBanner(session.errorMessage)
                .padding(20)
            }
            .background(NSColor.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Forgot password

struct ForgotPasswordView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("Reset your password")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("We'll email you a reset link. It expires quickly — check your inbox (and spam) right away.")
                    .font(.subheadline)
                    .foregroundStyle(NSColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("Email address", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding(12).background(NSColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(NSColor.line))

                Button {
                    Task {
                        if await session.forgotPassword(email: email) { sent = true }
                    }
                } label: {
                    if session.isBusy { ProgressView().tint(.white) } else { Text("Send reset link") }
                }
                .buttonStyle(NSPrimaryButtonStyle())
                .disabled(!email.isValidEmail || session.isBusy)

                if sent {
                    NSCard {
                        Text("Check your email — if there's an account for \(email), the reset link is on its way.")
                            .font(.subheadline)
                    }
                }
            }
            .apiErrorBanner(session.errorMessage)
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(NSColor.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
