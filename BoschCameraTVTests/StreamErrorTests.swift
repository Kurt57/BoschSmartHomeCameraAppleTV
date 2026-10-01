import Foundation
import Testing
@testable import BoschCameraTV

struct StreamErrorTests {
    @Test(arguments: [
        URLError.Code.cannotConnectToHost,
        .cannotFindHost,
        .timedOut,
        .notConnectedToInternet,
        .networkConnectionLost,
        .dnsLookupFailed,
    ])
    func networkErrorsMeanHomeAssistantIsUnreachable(code: URLError.Code) {
        #expect(StreamError(classifying: URLError(code)) == .homeAssistantUnreachable)
    }

    @Test func findsNetworkErrorWrappedByAVFoundation() {
        let urlError = NSError(domain: NSURLErrorDomain, code: URLError.Code.cannotConnectToHost.rawValue)
        let coreMediaError = NSError(domain: "CoreMediaErrorDomain", code: -12_645, userInfo: [NSUnderlyingErrorKey: urlError])
        let avError = NSError(domain: "AVFoundationErrorDomain", code: -11_800, userInfo: [NSUnderlyingErrorKey: coreMediaError])

        #expect(StreamError(classifying: avError) == .homeAssistantUnreachable)
    }

    @Test func unknownMediaErrorsMeanStreamUnavailable() {
        let error = NSError(domain: "CoreMediaErrorDomain", code: -12_938)

        #expect(StreamError(classifying: error) == .streamUnavailable(statusCode: nil))
    }

    @Test func detectsBlockedInsecureConnections() {
        let error = URLError(.appTransportSecurityRequiresSecureConnection)

        #expect(StreamError(classifying: error) == .insecureConnectionBlocked)
    }

    @Test func detectsUnsupportedURLs() {
        #expect(StreamError(classifying: URLError(.unsupportedURL)) == .invalidStreamURL)
    }

    @Test func keepsStreamErrorsUnchanged() {
        #expect(StreamError(classifying: StreamError.unauthorized) == .unauthorized)
    }

    @Test func classifiesTransientErrors() {
        #expect(StreamError.homeAssistantUnreachable.isTransient)
        #expect(StreamError.streamUnavailable(statusCode: 503).isTransient)
        #expect(StreamError.stalled.isTransient)
        #expect(StreamError.streamEnded.isTransient)

        #expect(!StreamError.unauthorized.isTransient)
        #expect(!StreamError.missingStreamURL.isTransient)
        #expect(!StreamError.invalidStreamURL.isTransient)
        #expect(!StreamError.insecureConnectionBlocked.isTransient)
    }

    @Test func providesUserFacingTexts() {
        #expect(StreamError.homeAssistantUnreachable.title == "Keine Verbindung zu Home Assistant")
        #expect(StreamError.streamUnavailable(statusCode: 404).title == "Stream nicht verfügbar")
        #expect(StreamError.stalled.title == "Stream nicht verfügbar")
        #expect(StreamError.streamUnavailable(statusCode: 404).message.contains("404"))
        #expect(StreamError.unauthorized.errorDescription == StreamError.unauthorized.title)
    }
}
