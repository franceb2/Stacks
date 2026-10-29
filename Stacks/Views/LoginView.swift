import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AppSession

    @AppStorage("lastServerInput") private var server = ""
    @AppStorage("lastUsername") private var username = ""
    @State private var password = ""
    @State private var authKey = ""
    @State private var useAuthKey = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.20:5000", text: $server)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Kavita server")
                } footer: {
                    Text("Your PC's address and Kavita's port (5000 by default). Away from home, use your PC's Tailscale address, like http://100.x.y.z:5000.")
                }

                if useAuthKey {
                    Section {
                        SecureField("Auth Key", text: $authKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Create one in Kavita under User Settings → Manage Auth Keys.")
                    }
                } else {
                    Section("Account") {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }

                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text("Connect")
                            Spacer()
                            if busy { ProgressView() }
                        }
                    }
                    .disabled(busy || server.isEmpty || (useAuthKey ? authKey.isEmpty : (username.isEmpty || password.isEmpty)))

                    Button(useAuthKey ? "Use username and password instead" : "Use an Auth Key instead") {
                        useAuthKey.toggle()
                    }
                    .font(.footnote)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Stacks")
        }
    }

    private func signIn() async {
        busy = true
        error = nil
        defer { busy = false }
        guard let url = KavitaClient.normalize(server) else {
            error = KavitaError.badURL.localizedDescription
            return
        }
        do {
            let key = useAuthKey
                ? authKey.trimmingCharacters(in: .whitespacesAndNewlines)
                : try await KavitaClient.login(server: url, username: username, password: password)
            try await session.signIn(server: url, apiKey: key)
            password = ""
        } catch let urlError as URLError {
            error = "Couldn't reach the server (\(urlError.localizedDescription)). Check that Kavita is running, the address is right, and your phone is on the same network or Tailscale."
        } catch {
            self.error = error.localizedDescription
        }
    }
}
