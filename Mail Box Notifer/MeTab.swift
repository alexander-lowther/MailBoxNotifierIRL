
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// "Me" / Account screen (production-safe, iOS 15+).
/// - Always returns the user to Sign In by clearing `@AppStorage("userUID")`.
/// - Deletion is performed server-side via callable `deleteAccountHard` to guarantee:
///   - Firestore subtree under /users/{uid}/** is deleted
///   - Auth user is deleted
/// - On any deletion failure, we sign out (per requirement).
struct MeView: View {
    let userUID: String
    private let db = Firestore.firestore() // kept (no extra changes), though not used for deletion anymore
    private let functions = Functions.functions()

    @AppStorage("userUID") private var storedUID: String = ""

    @State private var email: String = ""
    @State private var providerSummary: String = ""

    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false

    @State private var isWorking = false
    @State private var statusText: String? = nil   // minimal surface area for errors

    var body: some View {
        AppNavigationContainer {
            List {
                Section(header: Text("Account")) {
                    infoRow(title: "Email", value: email.isEmpty ? "Not available" : email)
                    infoRow(title: "Provider", value: providerSummary.isEmpty ? "Unknown" : providerSummary)
                }

                if let statusText {
                    Section {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(isWorking)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(isWorking ? "Working…" : "Delete Account", systemImage: "trash")
                    }
                    .disabled(isWorking)
                }
            }
            .navigationTitle("Me")
            .navigationBarTitleDisplayMode(.large)
            .onAppear(perform: hydrateFromAuth)
            .confirmationDialog(
                "Sign out of this device?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    goToSignIn()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You’ll need to sign in again to use this app on this device.")
            }
            .confirmationDialog(
                "Delete this account?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    statusText = nil
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is permanent. If deletion can’t be completed right now, we’ll sign you out.")
            }
        }
    }

    // MARK: - UI helpers

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    // MARK: - Data hydration

    private func hydrateFromAuth() {
        guard let user = Auth.auth().currentUser else {
            email = ""
            providerSummary = ""
            return
        }

        email = user.email ?? ""
        let providers = user.providerData.map { $0.providerID }
        providerSummary = providers.isEmpty ? "Unknown" : providers.joined(separator: ", ")
    }

    // MARK: - Deletion (server-side, guaranteed)

    private func deleteAccount() {
        guard Auth.auth().currentUser != nil else {
            goToSignIn()
            return
        }

        isWorking = true
        statusText = "Deleting account…"

        Task {
            do {
                try await callDeleteAccountHard()
                // At this point: Firestore subtree + Auth user are deleted server-side.
                // Local sign-out is just UI cleanup.
                do { try Auth.auth().signOut() } catch { /* ignore */ }
                await MainActor.run {
                    isWorking = false
                    statusText = nil
                    storedUID = ""
                }
            } catch {
                // Per requirement: if we cannot complete deletion right now, sign out.
                await MainActor.run {
                    isWorking = false
                    statusText = "Couldn’t delete account right now. Signed you out."
                    goToSignIn()
                }
            }
        }
    }

    private func callDeleteAccountHard() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            functions.httpsCallable("deleteAccountHard").call([:]) { _, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }


    // MARK: - Sign out / return to Sign In

    private func goToSignIn() {
        // Always return to sign-in by clearing local auth + AppStorage state.
        do { try Auth.auth().signOut() } catch { /* ignore */ }
        storedUID = ""
    }
}
