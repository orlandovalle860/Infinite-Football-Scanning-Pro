//
//  UserFacingErrorMessage.swift
//  FootballScanningAI
//
//  Maps arbitrary errors to safe, non-technical copy for UI (no HTTP codes, JSON, or backend strings).
//

import AuthenticationServices
import Foundation

enum UserFacingErrorMessage {
    static let sessionExpiredReconnect = "Session expired. Please reconnect."
    static let connectionIssueRetry = "Connection issue. Try again."
    static let genericRetry = "Something went wrong. Please retry."
    /// Relay join: coach slot already claimed or code points at another room.
    static let relayJoinCodeMismatch = "That code doesn’t match the session on the display. Enter the code shown on the display now, then try again."
    static let notConnected = "Not connected."
    static let notConnectedToDisplay = "Not connected to this display."

    /// Preferred mapping for any `Error` shown in UI.
    static func message(from error: Error) -> String {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain {
            if ns.code == ASAuthorizationError.canceled.rawValue {
                return genericRetry
            }
            return genericRetry
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed,
                 .secureConnectionFailed,
                 .serverCertificateUntrusted,
                 .appTransportSecurityRequiresSecureConnection:
                return connectionIssueRetry
            default:
                return genericRetry
            }
        }
        if error is DecodingError {
            return genericRetry
        }
        if ns.domain == NSPOSIXErrorDomain, ns.code == 60 { // ETIMEDOUT
            return connectionIssueRetry
        }
        return genericRetry
    }
}
