import AppKit
import CommonCrypto
import CoreFoundation
import Foundation
import SQLite3

struct UsageMeter: Codable {
    var title: String
    var percent: Double
    var resetsAt: String?
}

struct ProfileUsageSnapshot: Codable {
    var profileID: String
    var fetchedAt: Date
    var message: String?
    var fiveHour: UsageMeter?
    var weekly: UsageMeter?
    var scopedWeekly: [UsageMeter]
}

struct UsageCacheFile: Codable {
    var profiles: [String: ProfileUsageSnapshot] = [:]

    static func load() -> UsageCacheFile {
        let url = URL(fileURLWithPath: rootPath()).appendingPathComponent("usage-cache.json")
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(UsageCacheFile.self, from: data) else { return UsageCacheFile() }
        return value
    }

    func save() {
        let url = URL(fileURLWithPath: rootPath()).appendingPathComponent("usage-cache.json")
        guard let data = try? JSONEncoder().encode(self) else { return }
        do {
            try makeDirectory(rootPath())
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Usage is optional. Keep the last in-memory values if the local cache cannot be written.
        }
    }
}

private enum UsageReadError: Error {
    case noSession
    case keychain
    case cookie
    case network
    case expired
    case empty
}

private struct ProfileCookies {
    var sessionKey: String
    var organizationID: String
    var clearance: String?
}

/// Reads only the Claude web session cookies needed for the usage request.
/// Cookie values and the Keychain secret are never written to disk or logged.
private final class ClaudeUsageClient: NSObject, URLSessionTaskDelegate {
    static let shared = ClaudeUsageClient()
    private var derivedKey: Data?

    private override init() { super.init() }

    func fetch(_ profile: Profile) -> ProfileUsageSnapshot {
        let stamp = Date()
        do {
            let cookies = try readCookies(profile)
            let (data, response) = try requestUsage(cookies)
            guard let http = response as? HTTPURLResponse else { throw UsageReadError.network }
            guard http.statusCode == 200 else {
                if http.statusCode == 401 || http.statusCode == 403 { throw UsageReadError.expired }
                throw UsageReadError.network
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fiveHour = meter(in: object, key: "five_hour", title: "Current session"),
                  let weekly = meter(in: object, key: "seven_day", title: "This week") else { throw UsageReadError.empty }
            let scopes = scopedMeters(object)
            return ProfileUsageSnapshot(profileID: profile.id, fetchedAt: stamp, message: nil,
                                         fiveHour: fiveHour, weekly: weekly, scopedWeekly: scopes)
        } catch UsageReadError.noSession {
            return unavailable(profile, stamp, "Sign in to this Claude profile to see usage.")
        } catch UsageReadError.keychain {
            return unavailable(profile, stamp, "Allow access to Claude Safe Storage in Keychain to load usage.")
        } catch UsageReadError.cookie {
            return unavailable(profile, stamp, "Reopen Claude for this profile, then refresh usage.")
        } catch UsageReadError.expired {
            return unavailable(profile, stamp, "Session expired. Sign in to this profile to refresh usage.")
        } catch UsageReadError.empty {
            return unavailable(profile, stamp, "Claude has not returned usage data for this profile yet.")
        } catch {
            return unavailable(profile, stamp, "Claude usage is temporarily unavailable. It will retry automatically.")
        }
    }

    private func unavailable(_ profile: Profile, _ date: Date, _ message: String) -> ProfileUsageSnapshot {
        ProfileUsageSnapshot(profileID: profile.id, fetchedAt: date, message: message,
                             fiveHour: nil, weekly: nil, scopedWeekly: [])
    }

    private func readCookies(_ profile: Profile) throws -> ProfileCookies {
        var encrypted: [String: Data] = [:]
        var plain: [String: String] = [:]
        let paths = [profile.dataPath + "/Cookies", profile.dataPath + "/Network/Cookies"]
        for path in paths where fm.fileExists(atPath: path) {
            readCookieRows(path, encrypted: &encrypted, plain: &plain)
            if (encrypted["sessionKey"] != nil || plain["sessionKey"] != nil) &&
               (encrypted["lastActiveOrg"] != nil || plain["lastActiveOrg"] != nil) { break }
        }
        guard !encrypted.isEmpty || !plain.isEmpty else { throw UsageReadError.noSession }
        let needsKey = encrypted.values.contains { $0.starts(with: Data("v10".utf8)) }
        if needsKey, derivedKey == nil { derivedKey = try loadDerivedKey() }

        func value(_ name: String) throws -> String? {
            if let text = plain[name], !text.isEmpty { return text }
            guard let bytes = encrypted[name] else { return nil }
            guard let decoded = decryptCookie(bytes), !decoded.isEmpty else { throw UsageReadError.cookie }
            return decoded
        }
        guard let session = try value("sessionKey"), let org = try value("lastActiveOrg") else { throw UsageReadError.noSession }
        guard safeCookie(session), safeOrganization(org) else { throw UsageReadError.cookie }
        let clearance = try? value("cf_clearance")
        return ProfileCookies(sessionKey: session, organizationID: org, clearance: clearance.flatMap { $0 })
    }

    private func readCookieRows(_ path: String, encrypted: inout [String: Data], plain: inout [String: String]) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else { return }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2500)
        let sql = "SELECT name, value, encrypted_value FROM cookies WHERE host_key IN ('.claude.ai','claude.ai') AND name IN ('sessionKey','lastActiveOrg','cf_clearance')"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePointer = sqlite3_column_text(statement, 0) else { continue }
            let name = String(cString: namePointer)
            let textPointer = sqlite3_column_text(statement, 1)
            let text = textPointer.map { String(cString: $0) } ?? ""
            let count = Int(sqlite3_column_bytes(statement, 2))
            if count > 0, let blob = sqlite3_column_blob(statement, 2) {
                encrypted[name] = Data(bytes: blob, count: count)
            } else if !text.isEmpty {
                plain[name] = text
            }
        }
    }

    private func loadDerivedKey() throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Safe Storage", "-w"]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UsageReadError.keychain }
        var secret = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        while secret.last == 10 || secret.last == 13 { secret.removeLast() }
        guard process.terminationStatus == 0, !secret.isEmpty else { throw UsageReadError.keychain }
        var key = Data(count: kCCKeySizeAES128)
        let result = key.withUnsafeMutableBytes { keyBytes in
            secret.withUnsafeBytes { passwordBytes in
                "saltysalt".withCString { salt in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), passwordBytes.count,
                                         UnsafeRawPointer(salt).assumingMemoryBound(to: UInt8.self), 9,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                         keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), keyBytes.count)
                }
            }
        }
        guard result == kCCSuccess else { throw UsageReadError.keychain }
        return key
    }

    private func decryptCookie(_ encrypted: Data) -> String? {
        guard encrypted.starts(with: Data("v10".utf8)), let key = derivedKey else { return nil }
        let ciphertext = encrypted.dropFirst(3)
        guard ciphertext.count > 0 else { return nil }
        var plaintext = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var moved = 0
        let status = plaintext.withUnsafeMutableBytes { output in
            ciphertext.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    Data(repeating: 0x20, count: kCCBlockSizeAES128).withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, keyBytes.count, ivBytes.baseAddress,
                                input.baseAddress, input.count, output.baseAddress, output.count, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess, moved > 32 else { return nil }
        let value = plaintext.subdata(in: 32..<moved)
        return String(data: value, encoding: .utf8)
    }

    private func requestUsage(_ cookies: ProfileCookies) throws -> (Data, URLResponse) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(cookies.organizationID)/usage") else { throw UsageReadError.cookie }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        var cookie = "sessionKey=\(cookies.sessionKey); lastActiveOrg=\(cookies.organizationID)"
        if let clearance = cookies.clearance, safeCookie(clearance) { cookie += "; cf_clearance=\(clearance)" }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        let delegate = ClaudeUsageClient()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, URLResponse), Error>?
        session.dataTask(with: request) { data, response, error in
            if let error { result = .failure(error) }
            else if let data, let response, data.count <= 1_048_576 { result = .success((data, response)) }
            else { result = .failure(UsageReadError.network) }
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 15) == .success, let result else { throw UsageReadError.network }
        return try result.get()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.host == "claude.ai", url.port == nil else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }

    private func meter(in object: [String: Any], key: String, title: String) -> UsageMeter? {
        let nested = (object["standard"] as? [String: Any])?["rate_limit"] as? [String: Any]
        let value = (object[key] as? [String: Any]) ?? (nested?[key] as? [String: Any])
        guard let value, let number = number(value["utilization"]) else { return nil }
        return UsageMeter(title: title, percent: min(100, max(0, number)), resetsAt: value["resets_at"] as? String)
    }

    private func scopedMeters(_ object: [String: Any]) -> [UsageMeter] {
        guard let limits = object["limits"] as? [[String: Any]] else { return [] }
        return limits.compactMap { limit in
            guard limit["kind"] as? String == "weekly_scoped", let percent = number(limit["percent"]) else { return nil }
            let scope = limit["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            let title = (model?["display_name"] as? String) ?? (model?["name"] as? String) ?? "Model"
            return UsageMeter(title: title + " this week", percent: min(100, max(0, percent)), resetsAt: limit["resets_at"] as? String)
        }
    }

    private func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let number = value.doubleValue
        return number.isFinite ? number : nil
    }
}

/// Serial background polling keeps both the status menu and manager responsive.
final class UsageRefresher {
    static let shared = UsageRefresher()
    private let queue = DispatchQueue(label: "local.multi-claude-app.usage-refresh", qos: .utility)
    private let interval: TimeInterval = 300

    func refresh(_ profiles: [Profile], force: Bool = false) {
        queue.async {
            var cache = UsageCacheFile.load()
            let activeIDs = Set(profiles.map(\.id))
            let oldCount = cache.profiles.count
            cache.profiles = cache.profiles.filter { activeIDs.contains($0.key) }
            let pruned = cache.profiles.count != oldCount
            if pruned { cache.save(); self.notifyUpdated() }
            for profile in profiles {
                if !force, let current = cache.profiles[profile.id], Date().timeIntervalSince(current.fetchedAt) < self.interval { continue }
                let previous = cache.profiles[profile.id]
                cache.profiles[profile.id] = ProfileUsageSnapshot(profileID: profile.id, fetchedAt: Date(),
                                                                    message: "Checking Claude usage…", fiveHour: nil,
                                                                    weekly: nil, scopedWeekly: [])
                cache.save()
                let snapshot = ClaudeUsageClient.shared.fetch(profile)
                if snapshot.fiveHour == nil, var previous, previous.weekly != nil {
                    previous.message = snapshot.message
                    previous.fetchedAt = snapshot.fetchedAt
                    cache.profiles[profile.id] = previous
                } else {
                    cache.profiles[profile.id] = snapshot
                }
                cache.save(); self.notifyUpdated()
            }
        }
    }

    private func notifyUpdated() {
        DispatchQueue.main.async {
            DistributedNotificationCenter.default().post(name: usageDidRefreshNotification, object: nil)
        }
    }
}

private func safeCookie(_ value: String) -> Bool {
    !value.isEmpty && value.unicodeScalars.allSatisfy { $0.value >= 0x21 && $0.value <= 0x7e && $0 != ";" && $0 != "," }
}

private func safeOrganization(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 128 && value.unicodeScalars.allSatisfy {
        CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
    }
}

import CoreFoundation
