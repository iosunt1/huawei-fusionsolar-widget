import XCTest
@testable import FusionSolarKit

final class FusionSolarClientTests: XCTestCase {
    func testRegionalHostsNormalizeToTheirBaseHost() {
        XCTAssertEqual(
            FusionSolarClient.normalizeHost("https://uni003eu5.fusionsolar.huawei.com/portal"),
            "eu5.fusionsolar.huawei.com"
        )
        XCTAssertEqual(
            FusionSolarClient.normalizeHost("region01eu5.fusionsolar.huawei.com"),
            "eu5.fusionsolar.huawei.com"
        )
        XCTAssertEqual(
            FusionSolarClient.normalizeHost(""),
            "eu5.fusionsolar.huawei.com"
        )
    }

    func testSnapshotParsesFlowValuesAndFormatsMetrics() {
        let response: [String: Any] = [
            "data": [
                "flow": [
                    "nodes": [
                        ["name": "neteco.pvms.devTypeLangKey.string", "description": ["value": "3.25"]],
                        ["name": "neteco.pvms.KPI.kpiView.electricalLoad", "description": ["value": "1.10 kW"]],
                        [
                            "name": "neteco.pvms.devTypeLangKey.energy_store",
                            "description": ["value": "0.80"],
                            "deviceTips": ["SOC": "72%", "BATTERY_POWER": "500"]
                        ]
                    ],
                    "links": [
                        ["description": ["label": "neteco.pvms.energy.flow.buy.power", "value": "1.35"]]
                    ]
                ]
            ]
        ]

        let snapshot = FusionSolarClient.snapshot(flow: response, today: 12.5, stationName: "South roof")
        XCTAssertEqual(snapshot.stationName, "South roof")
        XCTAssertEqual(snapshot.pvText, "3.25 kW")
        XCTAssertEqual(snapshot.batteryPercentText, "72%")
        XCTAssertEqual(snapshot.batteryText, "0.80 kW")
        XCTAssertEqual(snapshot.batteryMode, "charge")
        XCTAssertEqual(snapshot.houseText, "1.10 kW")
        XCTAssertEqual(snapshot.gridText, "1.35 kW")
        XCTAssertEqual(snapshot.gridMode, "export")
        XCTAssertEqual(snapshot.todayText, "12.5 kWh")
    }
}
