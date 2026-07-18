import SwiftUI

struct QueryWindowView: View {
    @ObservedObject var instance: InstanceManager

    @State private var sql = "SHOW TABLES"
    @State private var result: QueryResult?
    @State private var errorMessage: String?
    @State private var isRunning = false
    @State private var elapsed: Duration?

    private var isServerRunning: Bool {
        if case .running = instance.state { return true }
        return false
    }

    private var trimmedSQL: String {
        sql.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canRun: Bool {
        isServerRunning && !isRunning && !trimmedSQL.isEmpty
    }

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                editor
                controlBar
            }
            .frame(maxWidth: .infinity, minHeight: 130)

            results
                .frame(maxWidth: .infinity, minHeight: 120)
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    // MARK: - Editor

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $sql)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)

            if sql.isEmpty {
                Text("Enter a SQL query…")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            if !isServerRunning {
                Label("Server not running", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else if isRunning {
                ProgressView().controlSize(.small)
                Text("Running…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            Button("Clear") {
                result = nil
                errorMessage = nil
                elapsed = nil
            }
            .disabled(result == nil && errorMessage == nil)

            Button {
                Task { await runQuery() }
            } label: {
                Text("Run")
                    .frame(minWidth: 44)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canRun)
            .help("Run query (⌘↵)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        VStack(spacing: 0) {
            resultStatusBar

            if let errorMessage {
                ScrollView {
                    Text(errorMessage)
                        .textSelection(.enabled)
                        .foregroundStyle(.red)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            } else if let result {
                ResultsTable(result: result)
            } else {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "tablecells",
                    description: Text(isServerRunning
                        ? "Run a query to see results here."
                        : "Start the server to run queries.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var resultStatusBar: some View {
        if let result, errorMessage == nil {
            HStack(spacing: 12) {
                Text("^[\(result.rows.count) row](inflect: true)")
                    .monospacedDigit()
                if let elapsed {
                    Divider().frame(height: 12)
                    Text(elapsed.formattedSeconds)
                        .monospacedDigit()
                }
                Spacer()
                Button {
                    copyResults(result)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy results as TSV")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()
        }
    }

    // MARK: - Actions

    private func runQuery() async {
        errorMessage = nil
        isRunning = true
        let start = ContinuousClock.now
        defer { isRunning = false }
        do {
            result = try await QueryClient.run(sql: sql, port: instance.httpPort)
            elapsed = ContinuousClock.now - start
        } catch {
            result = nil
            elapsed = nil
            errorMessage = error.localizedDescription
        }
    }

    private func copyResults(_ result: QueryResult) {
        var lines = [result.columns.joined(separator: "\t")]
        lines.append(contentsOf: result.rows.map { $0.joined(separator: "\t") })
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

private extension Duration {
    var formattedSeconds: String {
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        }
        return String(format: "%.2f s", seconds)
    }
}

struct ResultsTable: View {
    let result: QueryResult

    var body: some View {
        if result.columns.isEmpty {
            ContentUnavailableView(
                "Query Returned No Columns",
                systemImage: "checkmark.circle"
            )
        } else {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            ForEach(Array(result.columns.enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .font(.system(.callout, design: .monospaced).bold())
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.primary.opacity(0.08))
                            }
                        }

                        ForEach(Array(result.rows.enumerated()), id: \.offset) { rowIndex, row in
                            GridRow {
                                ForEach(Array(result.columns.indices), id: \.self) { index in
                                    Text(index < row.count ? row[index] : "")
                                        .font(.system(.callout, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.05))
                                }
                            }
                        }
                    }
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
                }
            }
        }
    }
}
