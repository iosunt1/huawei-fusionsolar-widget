import FusionSolarKit
import SwiftUI
import WidgetKit

@main
struct FusionSolarWidgetApp: App {
    var body: some Scene {
        WindowGroup("FusionSolar Widget") {
            ConfigurationView()
                .frame(minWidth: 420, minHeight: 440)
        }
        .windowResizability(.contentSize)
    }
}

private struct ConfigurationView: View {
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var stationDN = ""
    @State private var status = ""
    @State private var isRefreshing = false

    var body: some View {
        Form {
            Section {
                TextField("FusionSolar host", text: $host, prompt: Text("eu5.fusionsolar.huawei.com"))
                    .textContentType(.URL)
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                TextField("Plant DN (optional)", text: $stationDN)
            } header: {
                Text("Account")
            } footer: {
                Text("Use the same account as the FusionSolar website. Leave Plant DN empty to use the first plant on your account.")
            }

            HStack {
                Button("Save and refresh") {
                    saveAndRefresh()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRefreshing || host.isEmpty || username.isEmpty || password.isEmpty)
                if isRefreshing { ProgressView().controlSize(.small) }
            }

            if !status.isEmpty {
                Text(status)
                    .font(.callout)
                    .foregroundColor(status.hasPrefix("Connected") ? Color.green : Color.secondary)
                    .textSelection(.enabled)
            }

            Text("After saving, add **Huawei FusionSolar** from macOS Notification Center's widget gallery. macOS controls how often widgets refresh.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .onAppear(perform: load)
    }

    private func load() {
        do {
            let credentials = try SharedConfiguration.load()
            host = credentials.host
            username = credentials.username
            password = credentials.password
            stationDN = credentials.stationDN
        } catch {
            status = error.localizedDescription
        }
    }

    private func saveAndRefresh() {
        let credentials = FusionSolarCredentials(host: host, username: username, password: password, stationDN: stationDN)
        do {
            try SharedConfiguration.save(credentials)
        } catch {
            status = error.localizedDescription
            return
        }
        isRefreshing = true
        status = "Connecting to FusionSolar…"
        Task {
            defer { isRefreshing = false }
            do {
                let snapshot = try await FusionSolarClient(credentials: credentials).fetchSnapshot()
                status = "Connected to \(snapshot.stationName). Widget data refreshed."
            } catch {
                status = error.localizedDescription
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
