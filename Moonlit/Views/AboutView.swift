import SwiftUI

struct AboutView: View {
    let onClose: () -> Void

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button {
                onClose()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape)

            Spacer()
            Text("About")
                .font(.headline)
            Spacer()
            Label("Back", systemImage: "chevron.left")
                .labelStyle(.titleAndIcon)
                .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var content: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(LinearGradient(
                    colors: [.pink, .purple],
                    startPoint: .top,
                    endPoint: .bottom
                ))

            VStack(spacing: 4) {
                Text("Tooth Fairy")
                    .font(.title.bold())
                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Schedule Claude desktop runs on your Mac.\nTooth Fairy drives the Claude app via Accessibility — picks the project folder, switches mode, pastes the prompt, sends it.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Link(destination: URL(string: "https://marioquiroz.gumroad.com/l/wacat?wanted=true")!) {
                Label("Buy me a beer", systemImage: "mug.fill")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.orange)

            Divider().padding(.horizontal, 60)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("Made by")
                    Link("mquiroz", destination: URL(string: "https://mquiroz.com")!)
                }
                .font(.caption)
                Text(verbatim: "© \(String(Calendar.current.component(.year, from: Date())))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.bottom, 24)
    }
}
