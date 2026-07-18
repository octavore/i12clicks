import Foundation

struct QueryResult {
    let columns: [String]
    let rows: [[String]]
}

enum QueryError: LocalizedError {
    case serverError(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .serverError(let message): return message
        case .badResponse: return "Unexpected response from server"
        }
    }
}

enum QueryClient {
    static func run(sql: String, port: Int) async throws -> QueryResult {
        var components = URLComponents(string: "http://127.0.0.1:\(port)/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: sql + " FORMAT TabSeparatedWithNames")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QueryError.badResponse }

        let text = String(data: data, encoding: .utf8) ?? ""
        guard http.statusCode == 200 else {
            throw QueryError.serverError(text.isEmpty ? "HTTP \(http.statusCode)" : text)
        }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        guard let headerLine = lines.first else {
            return QueryResult(columns: [], rows: [])
        }

        let columns = headerLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let rows = lines.dropFirst().map { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }

        return QueryResult(columns: columns, rows: rows)
    }
}
