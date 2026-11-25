import SwiftUI

// MARK: - Sign in / create account
struct SignInView: View {
    @Environment(AppSession.self) private var session

    @State private var creating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var message: String?

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 6 && (!creating || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox.fill").font(.system(size: 48)).foregroundStyle(.tint)
                        Text("Bins").font(.largeTitle.bold())
                        Text("Know what's in every box, and where it is.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("", selection: $creating) {
                        Text("Sign in").tag(false)
                        Text("Create account").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if creating {
                        TextField("Your first name", text: $name)
                            .textContentType(.givenName)
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password (6+ characters)", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                } footer: {
                    if creating {
                        Text("Your name shows to others in your household, e.g. in a bin's access history.")
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text(creating ? "Create account" : "Sign in").bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit || working)

                    if !creating {
                        Button("Forgot password?") { reset() }
                            .disabled(email.isEmpty || working)
                            .frame(maxWidth: .infinity)
                    }
                }

                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func submit() {
        working = true
        message = nil
        Task {
            defer { working = false }
            do {
                if creating {
                    try await session.createAccount(name: name.trimmingCharacters(in: .whitespaces),
                                                    email: email.trimmingCharacters(in: .whitespaces),
                                                    password: password)
                } else {
                    try await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func reset() {
        Task {
            do {
                try await session.resetPassword(email: email.trimmingCharacters(in: .whitespaces))
                message = "Check your email for a link to reset your password."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

// MARK: - Create or join a household
struct HouseholdSetupView: View {
    @Environment(AppSession.self) private var session

    @State private var householdName = ""
    @State private var code = ""
    @State private var working = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A household is the shared set of bins that everyone in your home can see and update.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("e.g. Our house", text: $householdName)
                    Button("Create household") {
                        run { try await session.createHousehold(name: householdName.trimmingCharacters(in: .whitespaces)) }
                    }
                    .disabled(householdName.trimmingCharacters(in: .whitespaces).isEmpty || working)
                } header: {
                    Text("Start a new household")
                }
                Section {
                    TextField("6-character code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced))
                    Button("Join household") {
                        run { try await session.joinHousehold(code: code) }
                    }
                    .disabled(code.filter { $0.isLetter || $0.isNumber }.count != 6 || working)
                } header: {
                    Text("Join with an invite code")
                } footer: {
                    Text("Ask someone already in the household for the code. It's in their Household tab.")
                }
                if working { ProgressView().frame(maxWidth: .infinity) }
                if let message { Text(message).foregroundStyle(.red).font(.footnote) }
                Section {
                    Button("Sign out", role: .destructive) { session.signOut() }
                }
            }
            .navigationTitle("Your household")
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        working = true
        message = nil
        Task {
            defer { working = false }
            do { try await action() } catch { message = error.localizedDescription }
        }
    }
}

// MARK: - Household (opened from the Bins tab)
struct HouseholdView: View {
    @Environment(AppSession.self) private var session
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var showsDone = false
    @State private var confirmingLeave = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invite code").font(.caption).foregroundStyle(.secondary)
                        Text(store.inviteCode)
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    ShareLink(item: "Join our household in the Bins app with invite code \(store.inviteCode)") {
                        Label("Send invite", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text(store.householdName)
                } footer: {
                    Text("Anyone with this code can join and see and edit all bins. Each person installs the app, creates their own account, then enters the code.")
                }

                Section("Members") {
                    ForEach(store.memberNames, id: \.self) { Label($0, systemImage: "person") }
                }

                Section {
                    LabeledContent("Signed in as", value: session.userName)
                    Button("Sign out") { session.signOut() }
                    Button("Leave household", role: .destructive) { confirmingLeave = true }
                }
            }
            .navigationTitle("Household")
            .toolbar {
                if showsDone { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Leave \(store.householdName)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave household", role: .destructive) {
                    Task { try? await session.leaveHousehold() }
                }
            } message: {
                Text("The bins stay with the household. You can rejoin with the invite code.")
            }
        }
    }
}
