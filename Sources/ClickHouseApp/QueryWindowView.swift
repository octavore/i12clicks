import SwiftUI

struct QueryWindowView: View {
    @EnvironmentObject var server: ServerManager

    @State private var sql = "SHOW TABLES"
    @State private var result: QueryResult?
    @State private var errorMessage: String?
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $sql)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 160)
                .padding(8)

            HStack {
                if isRunning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Run") { Task { await runQuery() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isRunning || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            Divider()

            if let errorMessage {
                ScrollView {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            } else if let result {
                ResultsTable(result: result)
            } else {
                Spacer()
                Text("Run a query to see results")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private func runQuery() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }
        do {
            result = try await QueryClient.run(sql: sql, port: server.httpPort)
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct ResultsTable: View {
    let result: QueryResult

    var body: some View {
        if result.columns.isEmpty {
            Text("Query returned no columns")
                .foregroundStyle(.secondary)
                .padding(8)
        } else {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        ForEach(Array(result.columns.enumerated()), id: \.offset) { _, name in
                            Text(name)
                                .font(.system(.body, design: .monospaced).bold())
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(result.columns.indices), id: \.self) { index in
                                Text(index < row.count ? row[index] : "")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }
}
