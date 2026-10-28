import Foundation

/// Why a license key could not be activated.
public enum LicenseActivationError: Error, Equatable, Sendable {
    case emptyKey
    case keyNotFound
    case keyInactive
    case activationLimitReached
    case wrongProduct
    case network(String)

    public var userMessage: String {
        switch self {
        case .emptyKey:
            return "Enter the license key from your purchase email."
        case .keyNotFound:
            return "That license key wasn't found. Check it against your purchase email."
        case .keyInactive:
            return "That license key has been disabled. Contact support if you think this is a mistake."
        case .activationLimitReached:
            return "That license key is already active on the maximum number of Macs."
        case .wrongProduct:
            return "That license key is for a different product."
        case .network(let detail):
            return "Couldn't reach the license server. Check your connection and try again. (\(detail))"
        }
    }
}

/// Checks license keys with a payment provider.
public protocol LicenseKeyVerifying: Sendable {
    /// Activates `key` on this Mac and returns the activation instance ID.
    func activate(key: String, deviceName: String) async throws(LicenseActivationError) -> String
    /// Whether `key` and its activation instance are still valid. Throws `.network` when the server can't be reached.
    func validate(key: String, instanceID: String) async throws(LicenseActivationError) -> Bool
}

/// Dodo Payments license keys. The activate/validate endpoints are public and meant for client apps,
/// so no API key ships in the app.
public struct DodoLicenseClient: LicenseKeyVerifying {
    public enum Environment: String, Sendable {
        case live = "https://live.dodopayments.com"
        case test = "https://test.dodopayments.com"
    }

    /// Must match the checkout the website links to: keys bought in test mode only validate against `.test`.
    public static let environment: Environment = .live
    /// The live Declutter Mac product; keys issued for other products on the same Dodo account are rejected.
    public static let expectedProductID: String? = "pdt_0NqhWbYx5j9eAeiJOrA7V"

    private let baseURL: URL
    private let expectedProductID: String?
    private let session: URLSession

    public init(
        environment: Environment = DodoLicenseClient.environment,
        expectedProductID: String? = DodoLicenseClient.expectedProductID,
        session: URLSession = .shared
    ) {
        self.baseURL = URL(string: environment.rawValue)!
        self.expectedProductID = expectedProductID
        self.session = session
    }

    private struct ActivateResponse: Decodable {
        struct Product: Decodable { let product_id: String }
        let id: String
        let product: Product
    }

    private struct ValidateResponse: Decodable {
        let valid: Bool
    }

    public func activate(key: String, deviceName: String) async throws(LicenseActivationError) -> String {
        let (data, status) = try await post("licenses/activate", body: ["license_key": key, "name": deviceName])
        switch status {
        case 200..<300:
            guard let response = try? JSONDecoder().decode(ActivateResponse.self, from: data) else {
                throw .network("unexpected response")
            }
            if let expectedProductID, response.product.product_id != expectedProductID {
                throw .wrongProduct
            }
            return response.id
        case 403: throw .keyInactive
        case 404: throw .keyNotFound
        case 422: throw .activationLimitReached
        default: throw .network("HTTP \(status)")
        }
    }

    public func validate(key: String, instanceID: String) async throws(LicenseActivationError) -> Bool {
        let (data, status) = try await post("licenses/validate", body: ["license_key": key, "license_key_instance_id": instanceID])
        switch status {
        case 200..<300:
            guard let response = try? JSONDecoder().decode(ValidateResponse.self, from: data) else {
                throw .network("unexpected response")
            }
            return response.valid
        case 403, 404, 422:
            return false
        default:
            throw .network("HTTP \(status)")
        }
    }

    private func post(_ path: String, body: [String: String]) async throws(LicenseActivationError) -> (Data, Int) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try? JSONEncoder().encode(body)
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw .network(error.localizedDescription)
        }
    }
}
