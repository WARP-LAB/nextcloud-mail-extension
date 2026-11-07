import Foundation

/// How a request's network errors and statuses become `NextcloudError`s, the same for every request (T21).
extension NextcloudClient {
    /// Runs a request, turning "offline", which is also what a server blocked by Local Network privacy gives, into
    /// `NextcloudError.offline`, which says where to allow it. "Offline" is retried once after `retryDelay`: macOS
    /// refuses the first request a new build makes to the local network even when it's allowed, then lets the next
    /// one through (docs/MAIL.md, "Network").
    ///
    /// When it stays offline, `hasNetwork` tells a Mac without a network from a server that Local Network privacy
    /// blocks, which macOS reports the same way. Other network errors become the `NextcloudError` that says what
    /// happened (T21).
    static func reaching<T>(
        retryDelay: UInt64 = 1_000_000_000, hasNetwork: () async -> Bool = NetworkStatus.hasNetwork,
        _ request: () async throws -> T
    ) async throws -> T {
        do {
            return try await request()
        } catch let error as URLError where error.code == .notConnectedToInternet {
            try await Task.sleep(nanoseconds: retryDelay)
            do {
                return try await request()
            } catch let error as URLError where error.code == .notConnectedToInternet {
                throw await hasNetwork() ? NextcloudError.offline : NextcloudError.noNetwork
            } catch let error as URLError {
                throw unreachable(error)
            }
        } catch let error as URLError {
            throw unreachable(error)
        }
    }

    /// The `NextcloudError` for a network error that means the server can't be reached, or the error itself.
    static func unreachable(_ error: URLError) -> Error {
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            return NextcloudError.cannotFindServer
        case .cannotConnectToHost, .networkConnectionLost:
            return NextcloudError.cannotConnect
        case .timedOut:
            return NextcloudError.timedOut
        default:
            return error
        }
    }

    /// The response's status, after throwing for the ones every request treats the same. `data` is the response's
    /// body, which tells WebDAV's maintenance mode from other gateway errors (docs/NEXTCLOUD.md).
    static func status(of response: URLResponse, data: Data = Data()) throws -> Int {
        guard let http = response as? HTTPURLResponse else {
            throw NextcloudError.invalidResponse("a request")
        }
        switch http.statusCode {
        case 401:
            throw NextcloudError.unauthorized
        case 429:
            throw NextcloudError.rateLimited
        case 502, 503, 504:
            let maintenance =
                http.value(forHTTPHeaderField: "X-Nextcloud-Maintenance-Mode") == "1"
                || String(bytes: data.prefix(4096), encoding: .utf8)?.contains("ServerMaintenanceMode") == true
            throw maintenance ? NextcloudError.maintenance : NextcloudError.unavailable(status: http.statusCode)
        default:
            return http.statusCode
        }
    }
}
