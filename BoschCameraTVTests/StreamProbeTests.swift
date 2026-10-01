import Foundation
import Testing
@testable import BoschCameraTV

struct StreamProbeTests {
    @Test(arguments: [200, 204, 302])
    func successfulResponsesMeanReachable(statusCode: Int) throws {
        #expect(try HTTPStreamProbe.evaluate(statusCode: statusCode) == .reachable)
    }

    @Test(arguments: [401, 403])
    func authErrorsMeanUnauthorized(statusCode: Int) {
        #expect(throws: StreamError.unauthorized) {
            _ = try HTTPStreamProbe.evaluate(statusCode: statusCode)
        }
    }

    @Test(arguments: [404, 500, 502, 503])
    func otherErrorsMeanStreamUnavailable(statusCode: Int) {
        #expect(throws: StreamError.streamUnavailable(statusCode: statusCode)) {
            _ = try HTTPStreamProbe.evaluate(statusCode: statusCode)
        }
    }
}
