import Foundation

public struct SolarSnapshot: Equatable, Sendable {
    public let stationName: String
    public let pvPower: Double?
    public let batteryPercent: Double?
    public let batteryPower: Double?
    public let batteryMode: String
    public let housePower: Double?
    public let gridPower: Double?
    public let gridMode: String
    public let todayEnergy: Double?
    public let updatedAt: Date

    public var pvText: String { Self.formatPower(pvPower) }
    public var batteryText: String { Self.formatPower(batteryPower) }
    public var batteryPercentText: String {
        batteryPercent.map { "\(Int($0.rounded()))%" } ?? "--"
    }
    public var houseText: String { Self.formatPower(housePower) }
    public var gridText: String { Self.formatPower(gridPower) }
    public var todayText: String {
        todayEnergy.map { Self.number($0, digits: 1) + " kWh" } ?? "--"
    }

    public init(
        stationName: String,
        pvPower: Double?,
        batteryPercent: Double?,
        batteryPower: Double?,
        batteryMode: String,
        housePower: Double?,
        gridPower: Double?,
        gridMode: String,
        todayEnergy: Double?,
        updatedAt: Date = .now
    ) {
        self.stationName = stationName
        self.pvPower = pvPower
        self.batteryPercent = batteryPercent
        self.batteryPower = batteryPower
        self.batteryMode = batteryMode
        self.housePower = housePower
        self.gridPower = gridPower
        self.gridMode = gridMode
        self.todayEnergy = todayEnergy
        self.updatedAt = updatedAt
    }

    static func formatPower(_ value: Double?) -> String {
        guard let value else { return "--" }
        return number(value, digits: abs(value) >= 10 ? 1 : 2) + " kW"
    }

    static func number(_ value: Double, digits: Int) -> String {
        String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, value)
    }
}
