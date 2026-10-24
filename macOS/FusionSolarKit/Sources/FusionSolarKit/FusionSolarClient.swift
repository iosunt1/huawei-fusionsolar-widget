import Foundation
import Security

public struct FusionSolarCredentials: Equatable, Sendable {
    public var host: String
    public var username: String
    public var password: String
    public var stationDN: String

    public init(host: String, username: String, password: String, stationDN: String = "") {
        self.host = host
        self.username = username
        self.password = password
        self.stationDN = stationDN
    }

    public var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }
}

public enum FusionSolarError: LocalizedError, Sendable {
    case notConfigured
    case storageUnavailable
    case network(String)
    case authentication(String)
    case sessionExpired
    case captcha
    case noPlant
    case invalidResponse(String)
    case encryption(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Open FusionSolar Widget to enter your account details."
        case .storageUnavailable:
            return "The shared widget settings are unavailable. Check the app's App Group signing capability."
        case .network(let message):
            return "Could not reach FusionSolar. \(message)"
        case .authentication(let message):
            return message
        case .sessionExpired:
            return "FusionSolar session expired. Please try again."
        case .captcha:
            return "FusionSolar requires a captcha. Sign in to the FusionSolar website in a browser, then try again."
        case .noPlant:
            return "No matching plant was found for this account."
        case .invalidResponse(let message):
            return message
        case .encryption(let message):
            return message
        }
    }
}

public final class FusionSolarClient {
    private let credentials: FusionSolarCredentials
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage?
    private var dataHost = ""
    private var stationDN = ""
    private var stationName = ""
    private var csrf = ""

    public init(credentials: FusionSolarCredentials) {
        self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        cookieStorage = configuration.httpCookieStorage
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 25
        session = URLSession(configuration: configuration)
    }

    public func fetchSnapshot() async throws -> SolarSnapshot {
        try await fetchSnapshot(retried: false)
    }

    private func fetchSnapshot(retried: Bool) async throws -> SolarSnapshot {
        guard credentials.isConfigured else { throw FusionSolarError.notConfigured }
        do {
            let loginHost = Self.normalizeHost(credentials.host)
            if loginHost.contains("la5.") || loginHost.contains("intl.") {
                try await loginPlain(host: loginHost)
            } else {
                try await loginRSA(host: loginHost)
            }

            try await refreshCSRF()
            try await selectPlant()
            try await refreshCSRF()
            let flow = try await fetchFlow()
            let today = try? await fetchToday()
            return Self.snapshot(flow: flow, today: today ?? nil, stationName: stationName)
        } catch FusionSolarError.sessionExpired where !retried {
            return try await FusionSolarClient(credentials: credentials).fetchSnapshot(retried: true)
        }
    }

    public static func normalizeHost(_ value: String) -> String {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        host = host.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
        host = String(host.split(separator: "/", maxSplits: 1).first ?? "")
        host = String(host.split(separator: ":", maxSplits: 1).first ?? "")
        let suffix = ".fusionsolar.huawei.com"
        if host.hasSuffix(suffix) {
            host.removeLast(suffix.count)
        }
        host = host.replacingOccurrences(
            of: #"^(?:region|uni)\d+(?=[a-z]+\d+$)"#,
            with: "",
            options: .regularExpression
        )
        if host.isEmpty { host = "eu5" }
        return host + suffix
    }

    static func numeric(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        let token = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard token != "--", token.lowercased() != "null" else { return nil }
        guard let range = token.range(of: #"^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)"#, options: .regularExpression) else {
            return nil
        }
        return Double(token[range].replacingOccurrences(of: ",", with: "."))
    }

    static func snapshot(flow: [String: Any], today: Double?, stationName: String) -> SolarSnapshot {
        let body = flow["data"] as? [String: Any] ?? flow
        let graph = body["flow"] as? [String: Any] ?? body
        let nodes = graph["nodes"] as? [[String: Any]] ?? []
        var pv: Double?
        var house: Double?
        var soc: Double?
        var charge = 0.0
        var discharge = 0.0
        var hasBattery = false

        for node in nodes {
            let description = node["description"] as? [String: Any] ?? [:]
            let value = numeric(description["value"])
            switch node["name"] as? String {
            case "neteco.pvms.devTypeLangKey.string":
                pv = value
            case "neteco.pvms.KPI.kpiView.electricalLoad":
                house = value
            case "neteco.pvms.devTypeLangKey.energy_store":
                hasBattery = true
                let tips = node["deviceTips"] as? [String: Any] ?? [:]
                soc = numeric(tips["SOC"])
                if let direction = numeric(tips["BATTERY_POWER"]), direction > 0 {
                    charge = value ?? 0
                } else {
                    discharge = value ?? 0
                }
            default:
                break
            }
        }

        var gridKnown = false
        var gridImport = 0.0
        var gridExport = 0.0
        for link in graph["links"] as? [[String: Any]] ?? [] {
            let description = link["description"] as? [String: Any] ?? [:]
            guard description["label"] as? String == "neteco.pvms.energy.flow.buy.power" else { continue }
            let value = numeric(description["value"]) ?? 0
            gridKnown = true
            if (pv ?? 0) + discharge - charge - (house ?? 0) > 0 {
                gridExport = value
            } else {
                gridImport = value
            }
        }

        let batteryMode = !hasBattery ? "" : charge > 0 ? "charge" : discharge > 0 ? "discharge" : "idle"
        let batteryPower = !hasBattery ? nil : charge > 0 ? charge : discharge > 0 ? discharge : 0
        let gridMode = !gridKnown ? "" : gridExport > 0 ? "export" : gridImport > 0 ? "import" : "idle"
        let gridPower = !gridKnown ? nil : gridExport > 0 ? gridExport : gridImport
        return SolarSnapshot(
            stationName: stationName,
            pvPower: pv,
            batteryPercent: soc,
            batteryPower: batteryPower,
            batteryMode: batteryMode,
            housePower: house,
            gridPower: gridPower,
            gridMode: gridMode,
            todayEnergy: today
        )
    }

    private func loginRSA(host: String) async throws {
        let origin = "https://\(host)"
        let service = "/unisess/v1/auth?service=%2Fnetecowebext%2Fhome%2Findex.html"
        let loginPage = "\(origin)/unisso/login.action?service=\(Self.urlEncode(service))"
        _ = try? await request(url: loginPage, accept: "text/html")
        let keyResponse = try await request(url: "\(origin)/unisso/pubkey", accept: "application/json", referer: loginPage)
        guard let keyData = keyResponse.json, let pem = keyData["pubKey"] as? String,
              let timeStamp = keyData["timeStamp"] else {
            throw FusionSolarError.invalidResponse("FusionSolar did not return a valid encryption key.")
        }
        let encrypted = try Self.encrypt(credentials.password, pem: pem) + String(describing: keyData["version"] ?? "")
        let payload: [String: Any] = [
            "organizationName": "",
            "username": credentials.username,
            "password": encrypted,
            "multiRegionName": ""
        ]
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let baseURL = "\(origin)/unisso/v3/validateUser.action?timeStamp=\(Self.urlEncode(String(describing: timeStamp)))&nonce=\(nonce)"
        let first = try await postLogin(url: baseURL + "&service=\(Self.urlEncode(service))", payload: payload, referer: loginPage + "?service=\(Self.urlEncode(service))", host: host)
        var result = first.json
        var redirect = Self.loginRedirect(result)
        var referer = origin + "/pvmswebsite/loginCustomize.html"
        if redirect.isEmpty {
            if let response = result, String(describing: response["errorCode"] ?? "") == "411" || response["verifyCodeCreate"] as? Bool == true {
                throw FusionSolarError.captcha
            }
            let second = try await postLogin(url: baseURL, payload: payload, referer: origin + "/unisso/login.action", host: host)
            result = second.json
            redirect = Self.loginRedirect(result)
            referer = origin + "/unisso/login.action"
        }
        guard !redirect.isEmpty else {
            let code = String(describing: result?["errorCode"] ?? "")
            if code == "411" { throw FusionSolarError.captcha }
            if code == "406" { throw FusionSolarError.authentication("FusionSolar rejected the username or password.") }
            let message = result?["errorMsg"] as? String ?? "FusionSolar login did not return a redirect."
            throw FusionSolarError.authentication(message)
        }
        let final = try await request(url: Self.resolve(redirect, base: origin + "/"), accept: "text/html", referer: referer)
        guard hasSessionCookie(final) else {
            throw FusionSolarError.authentication("FusionSolar login did not return a session cookie.")
        }
        dataHost = Self.responseHost(final) ?? Self.responseHost(final, fallback: Self.resolve(redirect, base: origin + "/")) ?? host
    }

    private func postLogin(url: String, payload: [String: Any], referer: String, host: String) async throws -> HTTPResult {
        var request = try makeRequest(url: url, accept: "application/json", referer: referer, host: host)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await send(request)
    }

    private func loginPlain(host: String) async throws {
        let origin = "https://\(host)"
        let home = try await request(url: origin + "/", accept: "text/html")
        var login = try makeRequest(url: origin + "/rest/dp/uidm/unisso/v1/validate-user?service=%2Frest%2Fdp%2Fuidm%2Fauth%2Fv1%2Fon-sso-credential-ready", accept: "application/json, text/plain, */*", referer: origin + "/", host: host)
        login.httpMethod = "POST"
        login.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        login.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        login.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": credentials.username,
            "password": credentials.password,
            "organizationName": ""
        ])
        let loginResult = try await send(login)
        guard let redirect = loginResult.response.value(forHTTPHeaderField: "redirect_url") else {
            if String(describing: loginResult.json?["errorCode"] ?? "") == "411" { throw FusionSolarError.captcha }
            throw FusionSolarError.authentication("FusionSolar login did not return a redirect.")
        }
        let followed = try await request(url: Self.resolve(redirect, base: origin + "/"), accept: "text/html", referer: origin)
        let completed = try await request(url: origin + "/rest/pvms/web/login/v1/redirecturl?isFirst=false", accept: "application/json, text/plain, */*")
        guard hasSessionCookie(followed) || hasSessionCookie(completed) else {
            throw FusionSolarError.authentication("FusionSolar login did not return a session cookie.")
        }
        _ = home
        dataHost = host
    }

    private func refreshCSRF() async throws {
        let result = try await request(url: "https://\(dataHost)/rest/dpcloud/auth/v1/keep-alive", accept: "application/json, text/plain, */*")
        guard let value = result.json?["payload"] as? String, !value.isEmpty else {
            throw FusionSolarError.sessionExpired
        }
        csrf = value
    }

    private func selectPlant() async throws {
        let payload: [String: Any] = [
            "curPage": 1, "pageSize": 10, "gridConnectedTime": "",
            "queryTime": 1_666_044_000_000 as Int64, "timeZone": 2,
            "sortId": "createTime", "sortDir": "DESC", "locale": "en_US"
        ]
        var request = try dataRequest(url: "https://\(dataHost)/rest/pvms/web/station/v1/station/station-list")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let result = try await send(request)
        try ensureSuccess(result, label: "Plant list")
        let stations = result.json?["data"] as? [String: Any]
        let list = stations?["list"] as? [[String: Any]] ?? []
        guard !list.isEmpty else { throw FusionSolarError.noPlant }
        let wanted = Self.decodeStationDN(credentials.stationDN)
        let selected = wanted.isEmpty ? list[0] : list.first(where: { $0["dn"] as? String == wanted })
        guard let selected else { throw FusionSolarError.noPlant }
        stationDN = selected["dn"] as? String ?? ""
        stationName = selected["name"] as? String ?? stationDN
    }

    private func fetchFlow() async throws -> [String: Any] {
        let url = "https://\(dataHost)/rest/pvms/web/station/v2/overview/energy-flow?stationDn=\(Self.urlEncode(stationDN))"
        let result = try await send(try dataRequest(url: url))
        try ensureSuccess(result, label: "Energy flow")
        guard let flow = result.json?["data"] as? [String: Any], flow["flow"] != nil else {
            throw FusionSolarError.invalidResponse("FusionSolar returned invalid energy-flow data.")
        }
        return result.json ?? [:]
    }

    private func fetchToday() async throws -> Double? {
        let now = Date()
        var calendar = Calendar.current
        calendar.timeZone = .current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timezoneName = TimeZone.current.identifier
        let timezone = Double(-TimeZone.current.secondsFromGMT(for: start)) / 3600
        let query = [
            "stationDn=\(Self.urlEncode(stationDN))",
            "timeDim=4",
            "queryTime=\(Int(start.timeIntervalSince1970 * 1000))",
            "timeZone=\(timezone)",
            "timeZoneStr=\(Self.urlEncode(timezoneName))",
            "dateStr=\(Self.urlEncode(formatter.string(from: start)))",
            "_=\(Int(Date().timeIntervalSince1970 * 1000))"
        ].joined(separator: "&")
        let result = try await send(try dataRequest(url: "https://\(dataHost)/rest/pvms/web/station/v2/overview/energy-balance?\(query)"))
        try ensureSuccess(result, label: "Energy balance")
        let values = (result.json?["data"] as? [String: Any])?["productPower"] as? [Any] ?? []
        let dayIndex = Calendar.current.component(.day, from: now) - 1
        guard values.indices.contains(dayIndex) else { return nil }
        return Self.numeric(values[dayIndex])
    }

    private func dataRequest(url: String) throws -> URLRequest {
        var request = try makeRequest(url: url, accept: "application/json, text/plain, */*", referer: "https://\(dataHost)/uniportal/pvmswebsite/assets/build/cloud.html", host: dataHost)
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if !csrf.isEmpty { request.setValue(csrf, forHTTPHeaderField: "Roarand") }
        return request
    }

    private func makeRequest(url: String, accept: String, referer: String? = nil, host: String) throws -> URLRequest {
        guard let parsedURL = URL(string: url), ["https", "http"].contains(parsedURL.scheme?.lowercased() ?? ""), parsedURL.host != nil else {
            throw FusionSolarError.network("FusionSolar URL is invalid.")
        }
        var request = URLRequest(url: parsedURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        if url.hasPrefix("https://\(host)") { request.setValue("https://\(host)", forHTTPHeaderField: "Origin") }
        return request
    }

    private func request(url: String, accept: String, referer: String? = nil) async throws -> HTTPResult {
        try await send(makeRequest(url: url, accept: accept, referer: referer, host: dataHost.isEmpty ? Self.normalizeHost(credentials.host) : dataHost))
    }

    private func send(_ request: URLRequest) async throws -> HTTPResult {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FusionSolarError.network("The server returned an invalid response.")
            }
            let decoded = try? JSONSerialization.jsonObject(with: data)
            return HTTPResult(response: http, body: data, json: decoded as? [String: Any])
        } catch let error as FusionSolarError {
            throw error
        } catch {
            throw FusionSolarError.network(error.localizedDescription)
        }
    }

    private func ensureSuccess(_ result: HTTPResult, label: String) throws {
        guard (200..<300).contains(result.response.statusCode) else {
            if result.response.statusCode == 401 || result.response.statusCode == 403 {
                throw FusionSolarError.sessionExpired
            }
            throw FusionSolarError.network("\(label) failed (HTTP \(result.response.statusCode)).")
        }
        if result.json?["success"] as? Bool == false {
            throw FusionSolarError.sessionExpired
        }
    }

    private func hasSessionCookie(_ result: HTTPResult) -> Bool {
        cookieStorage?.cookies?.contains(where: { $0.name == "dp-session" }) == true
            || result.response.allHeaderFields.contains(where: {
                String(describing: $0.key).lowercased() == "set-cookie"
                    && String(describing: $0.value).contains("dp-session=")
            })
    }

    private static func responseHost(_ result: HTTPResult, fallback: String? = nil) -> String? {
        if let host = result.response.url?.host { return host }
        return fallback.flatMap { URL(string: $0)?.host }
    }

    private static func loginRedirect(_ json: [String: Any]?) -> String {
        if let regions = json?["respMultiRegionName"] as? [Any], regions.count > 1, let value = regions[1] as? String {
            return value
        }
        return json?["redirectURL"] as? String ?? json?["redirectUrl"] as? String ?? ""
    }

    private static func resolve(_ path: String, base: String) -> String {
        URL(string: path, relativeTo: URL(string: base))?.absoluteURL.absoluteString ?? path
    }

    private static func decodeStationDN(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? value
    }

    private static func encrypt(_ password: String, pem: String) throws -> String {
        let encoded = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let der = Data(base64Encoded: encoded), let keyData = rsaKeyData(from: der) else {
            throw FusionSolarError.encryption("FusionSolar returned an invalid RSA public key.")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        var unmanagedError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &unmanagedError) else {
            throw FusionSolarError.encryption("Could not read FusionSolar's RSA public key.")
        }
        let algorithm = SecKeyAlgorithm.rsaEncryptionOAEPSHA384
        guard SecKeyIsAlgorithmSupported(key, .encrypt, algorithm),
              let encrypted = SecKeyCreateEncryptedData(key, algorithm, Data(password.utf8) as CFData, &unmanagedError) as Data? else {
            throw FusionSolarError.encryption("Could not encrypt your password for FusionSolar.")
        }
        return encrypted.base64EncodedString()
    }

    private static func rsaKeyData(from der: Data) -> Data? {
        let bytes = [UInt8](der)
        guard bytes.count > 2, bytes[0] == 0x30 else { return nil }
        var index = 1
        _ = derLength(bytes, index: &index)
        while index < bytes.count {
            let tag = bytes[index]
            index += 1
            guard let length = derLength(bytes, index: &index), index + length <= bytes.count else { return nil }
            if tag == 0x03, length > 1, bytes[index] == 0 {
                return Data(bytes[(index + 1)..<(index + length)])
            }
            index += length
        }
        return der
    }

    private static func derLength(_ bytes: [UInt8], index: inout Int) -> Int? {
        guard index < bytes.count else { return nil }
        let first = Int(bytes[index])
        index += 1
        if first < 0x80 { return first }
        let count = first & 0x7f
        guard count > 0, count <= 4, index + count <= bytes.count else { return nil }
        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }
}

private struct HTTPResult {
    let response: HTTPURLResponse
    let body: Data
    let json: [String: Any]?
}
