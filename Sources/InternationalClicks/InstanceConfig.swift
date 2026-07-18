import Foundation

struct InstanceConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var version: String
    var httpPort: Int
    var tcpPort: Int
    var mysqlPortEnabled: Bool
    var postgresPortEnabled: Bool
    var interserverPortEnabled: Bool

    init(
        id: UUID = UUID(), name: String, version: String, httpPort: Int, tcpPort: Int,
        mysqlPortEnabled: Bool = true, postgresPortEnabled: Bool = true, interserverPortEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.httpPort = httpPort
        self.tcpPort = tcpPort
        self.mysqlPortEnabled = mysqlPortEnabled
        self.postgresPortEnabled = postgresPortEnabled
        self.interserverPortEnabled = interserverPortEnabled
    }

    // Custom decoding so configs saved before these toggles existed default to
    // enabled (matching the previously-hardcoded always-on behavior).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        httpPort = try container.decode(Int.self, forKey: .httpPort)
        tcpPort = try container.decode(Int.self, forKey: .tcpPort)
        mysqlPortEnabled = try container.decodeIfPresent(Bool.self, forKey: .mysqlPortEnabled) ?? true
        postgresPortEnabled = try container.decodeIfPresent(Bool.self, forKey: .postgresPortEnabled) ?? true
        interserverPortEnabled = try container.decodeIfPresent(Bool.self, forKey: .interserverPortEnabled) ?? true
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
