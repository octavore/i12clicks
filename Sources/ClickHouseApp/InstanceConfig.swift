import Foundation

struct InstanceConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var version: String
    var httpPort: Int
    var tcpPort: Int

    init(id: UUID = UUID(), name: String, version: String, httpPort: Int, tcpPort: Int) {
        self.id = id
        self.name = name
        self.version = version
        self.httpPort = httpPort
        self.tcpPort = tcpPort
    }

    /// "major.minor" derived from the full release tag (e.g. "v25.8.28.1-lts" -> "25.8"),
    /// falling back to the raw version string when it isn't in that shape (e.g. "legacy").
    var majorMinorVersion: String {
        let digitsAndDots = version.drop { $0 == "v" }.prefix { $0.isNumber || $0 == "." }
        let components = digitsAndDots.split(separator: ".")
        guard components.count >= 2 else { return version }
        return "\(components[0]).\(components[1])"
    }
}
