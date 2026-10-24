import Foundation

public enum SharedConfiguration {
    public static let appGroup = "group.com.goitonthefloor.fusionsolarwidget"

    public static func load() throws -> FusionSolarCredentials {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            throw FusionSolarError.storageUnavailable
        }
        return FusionSolarCredentials(
            host: defaults.string(forKey: "host") ?? "",
            username: defaults.string(forKey: "username") ?? "",
            password: defaults.string(forKey: "password") ?? "",
            stationDN: defaults.string(forKey: "stationDN") ?? ""
        )
    }

    public static func save(_ credentials: FusionSolarCredentials) throws {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            throw FusionSolarError.storageUnavailable
        }
        defaults.set(credentials.host, forKey: "host")
        defaults.set(credentials.username, forKey: "username")
        defaults.set(credentials.password, forKey: "password")
        defaults.set(credentials.stationDN, forKey: "stationDN")
    }
}
