import SwiftUI

struct JOLSettingsView: View {
    @ObservedObject var connection: JOLController
    @State private var confirmHistory = false
    @State private var confirmDetails = false
    @State private var confirmPhotos = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your explorer. On line.").font(.custom("Caveat", size: 27))
            Text("Read Jerry’s journals and send directions from your browser. Choose a JOL server you trust—or keep everything on this Mac.")
                .font(.system(size: 12)).foregroundStyle(Color(nsColor: NotebookTheme.faded))
            if connection.connected {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(connection.manifest?.name ?? "Jerry On Line").font(.headline)
                        Text(connection.manifest?.origin ?? connection.address).font(.system(size: 12))
                        Text(connection.status).font(.system(size: 12)).accessibilityLabel("JOL status: " + connection.status)
                        if let synced = connection.lastSync { Text("Last synced \(synced, style: .relative) ago").font(.system(size: 11)).foregroundStyle(.secondary) }
                        HStack {
                            Button("Open JOL") { connection.openWebsite() }
                            Button("Disconnect") { connection.disconnect() }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Allow remote missions", isOn: Binding(get: { connection.remoteArmed }, set: { connection.setRemoteArmed($0) }))
                        Text("Remote directions use this Mac and its AI connection. Taking manual control pauses remote missions. Enable them again here when you’re ready, then close Settings.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("Journal sharing") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sharing notes\(connection.sharePhotos || connection.backfillPhotos ? ", photographs" : "")\(connection.shareDetails || connection.backfillDetails ? ", and technical details" : "").")
                        if connection.includeHistory {
                            Text("Older expeditions are included.").foregroundStyle(.secondary)
                        } else {
                            Button("Share Older Expeditions…") { confirmHistory = true }
                        }
                        if !connection.shareDetails && !connection.backfillDetails {
                            Button("Share Technical Details…") { confirmDetails = true }
                                .disabled(connection.working)
                        }
                        if !connection.sharePhotos && !connection.backfillPhotos {
                            Button("Share Journal Photographs…") { confirmPhotos = true }
                                .disabled(connection.working)
                        }
                        if let issue = connection.sharingIssue {
                            Text(issue).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("https://jol.example.com", text: $connection.address).textFieldStyle(.roundedBorder)
                        .disabled(connection.working).onSubmit { connection.checkServer() }.accessibilityLabel("JOL server address")
                        .onChange(of: connection.address) { _, _ in connection.serverAddressChanged() }
                    if connection.manifest == nil {
                        Button("Find Server") { connection.checkServer() }.disabled(connection.working || connection.address.isEmpty)
                    } else {
                        Text(connection.manifest?.name ?? "Jerry On Line").font(.headline)
                        Text(connection.manifest?.origin ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
                        Toggle("Share journal photographs", isOn: $connection.sharePhotos)
                        Toggle("Share technical details", isOn: $connection.shareDetails)
                        Toggle("Also share existing expeditions", isOn: $connection.includeHistory)
                        Text("New expeditions are shared when connected. Photographs and details can contain screen content. Your server’s operator can read shared journals; enabling remote missions also trusts that server to send directions.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack {
                            Button("Connect in Browser") { connection.connect() }.disabled(connection.working)
                            if connection.working { Button("Cancel") { connection.cancelSignIn() } }
                            else { Button("Change Server") { connection.checkServer() } }
                        }
                    }
                    Text(connection.status).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }.padding(14).background(Color(nsColor: NotebookTheme.leather).opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                Text("AI credentials stay on this Mac. Disconnecting JOL never stops local journal saving or removes your AI connection.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 532, alignment: .leading)
        .foregroundStyle(Color(nsColor: NotebookTheme.ink))
        .tint(Color(nsColor: NotebookTheme.ink))
        .font(.system(size: 13))
        .confirmationDialog("Share older expeditions?", isPresented: $confirmHistory) {
            Button("Share Older Expeditions") { connection.shareOlderExpeditions() }
        } message: {
            Text("Upload expeditions saved on this Mac before you connected, using your current sharing choices.")
        }
        .confirmationDialog("Share technical details?", isPresented: $confirmDetails) {
            Button("Share Technical Details") { connection.shareTechnicalDetails() }
        } message: {
            Text("Include technical details from past and future shared expeditions. Details may contain screen content.")
        }
        .confirmationDialog("Share journal photographs?", isPresented: $confirmPhotos) {
            Button("Share Journal Photographs") { connection.shareJournalPhotos() }
        } message: {
            Text("Upload photographs from expeditions you share with this JOL server, including photographs Jerry has already taken. Photographs can contain screen content.")
        }
    }
}
