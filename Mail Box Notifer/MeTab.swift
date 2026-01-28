
import SwiftUI
import FirebaseAuth

struct MeView: View {
    let userUID: String

    @State private var email: String = ""
    @State private var displayName: String = ""
    @State private var providerSummary: String = ""
    @State private var showSignOutConfirm: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    headerCard

                    accountCard

                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)

                    Spacer(minLength: 8)
                }
                .padding()
            }
            .navigationTitle("Me")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                hydrateFromAuth()
            }
            .confirmationDialog(
                "Sign out of this device?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to sign in again to use this app on this device.")
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.surface)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                        .frame(width: 52, height: 52)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName.isEmpty ? "Account" : displayName)
                        .font(.title3.bold())
                    Text(email.isEmpty ? "Signed in" : email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }

            if !userUID.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("User ID")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(userUID)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .padding(.top, 6)
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account Details")
                .font(.headline)

            row("Email", value: email.isEmpty ? "Not available" : email)
            row("Provider", value: providerSummary.isEmpty ? "Unknown" : providerSummary)
        }
        .padding(14)
        .background(AppTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private func hydrateFromAuth() {
        guard let user = Auth.auth().currentUser else {
            email = ""
            displayName = ""
            providerSummary = ""
            return
        }

        // Email:
        // - With Sign in with Apple via Firebase, `user.email` is often present
        //   but it is NOT guaranteed on every sign-in (Apple may not provide after first consent).
        email = user.email ?? ""

        // Display name (Apple often does not provide on later sign-ins)
        displayName = user.displayName ?? ""

        // Provider info
        let providers = user.providerData.map { $0.providerID }
        providerSummary = providers.isEmpty ? "Unknown" : providers.joined(separator: ", ")
    }

    private func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            // If you have a global error surface, wire it here. Keeping it silent to avoid UI churn.
        }
        UserDefaults.standard.removeObject(forKey: "userUID")
    }
}
