import Foundation
import Testing
@testable import BoschCameraTV

@MainActor
struct StreamPlayerPoolTests {
    private func makePool(linger: Duration = .milliseconds(20)) -> (StreamPlayerPool, () -> [FakeStreamPlayer]) {
        var created: [FakeStreamPlayer] = []
        let pool = StreamPlayerPool(linger: linger) {
            let player = FakeStreamPlayer()
            created.append(player)
            return player
        }
        return (pool, { created })
    }

    @Test func createsOneMutedPlayerPerCamera() {
        let (pool, created) = makePool()

        let first = pool.player(for: TestCameras.frontDoor)
        let again = pool.player(for: TestCameras.frontDoor)
        _ = pool.player(for: TestCameras.garden)

        #expect(first === again)
        #expect(created().count == 2)
        #expect(first.player.isMuted)
    }

    @Test func startsOnFirstAcquireOnly() {
        let (pool, created) = makePool()

        pool.acquire(TestCameras.frontDoor)
        pool.acquire(TestCameras.frontDoor)

        #expect(created().first?.calls == [.start("front-door")])
    }

    @Test func keepsStreamRunningWhileHandedOver() async {
        let (pool, created) = makePool()
        pool.acquire(TestCameras.frontDoor)     // Kachel

        pool.acquire(TestCameras.frontDoor)     // Vollbild
        pool.release(TestCameras.frontDoor)     // Kachel verschwindet
        try? await Task.sleep(for: .milliseconds(60))

        #expect(created().first?.calls == [.start("front-door")])
    }

    @Test func stopsAfterLingerWhenUnused() async {
        let (pool, created) = makePool()
        pool.acquire(TestCameras.frontDoor)

        pool.release(TestCameras.frontDoor)

        #expect(await waitUntil { created().first?.calls.last == .stop })
    }

    @Test func reacquireWithinLingerCancelsStop() async {
        let (pool, created) = makePool(linger: .milliseconds(80))
        pool.acquire(TestCameras.frontDoor)
        pool.release(TestCameras.frontDoor)

        pool.acquire(TestCameras.frontDoor)
        try? await Task.sleep(for: .milliseconds(150))

        #expect(created().first?.calls == [.start("front-door")])
    }

    @Test func restartsFailedStreamOnAcquire() {
        let (pool, created) = makePool()
        pool.acquire(TestCameras.frontDoor)
        created().first?.state = .failed(.stalled)

        pool.acquire(TestCameras.frontDoor)

        #expect(created().first?.calls == [.start("front-door"), .start("front-door")])
    }

    @Test func suspendsAndResumesInUseStreams() {
        let (pool, created) = makePool()
        pool.acquire(TestCameras.frontDoor)
        pool.acquire(TestCameras.garden)
        pool.release(TestCameras.garden)

        pool.suspendAll()
        pool.resumeAll()

        #expect(created()[0].calls == [.start("front-door"), .stop, .start("front-door")])
        #expect(created()[1].calls == [.start("garden"), .stop])
    }
}
