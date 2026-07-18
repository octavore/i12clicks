import SwiftUI

struct LogsView: View {
    @ObservedObject var instance: InstanceManager

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(instance.logTail.isEmpty ? "No log output yet." : instance.logTail)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                        .id("bottom")
                }
                .onChange(of: instance.logTail) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            Divider()

            HStack {
                Text(instance.logPath.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([instance.logPath])
                }
            }
            .padding(8)
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}
