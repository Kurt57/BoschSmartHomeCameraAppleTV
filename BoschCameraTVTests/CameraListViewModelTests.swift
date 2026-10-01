import Foundation
import Testing
@testable import BoschCameraTV

@MainActor
struct CameraListViewModelTests {
    let isolated = IsolatedDefaults()
    let settings: SettingsStore

    init() {
        settings = SettingsStore(defaults: isolated.defaults)
    }

    private func makeViewModel(_ provider: StubCameraProvider) -> CameraListViewModel {
        CameraListViewModel(cameraService: CameraService(provider: provider, settings: settings), settings: settings)
    }

    @Test func startsInLoadingState() {
        let viewModel = makeViewModel(StubCameraProvider([TestCameras.frontDoor]))

        #expect(viewModel.state == .loading)
        #expect(viewModel.cameras.isEmpty)
    }

    @Test func loadsEnabledCameras() async {
        let viewModel = makeViewModel(StubCameraProvider([TestCameras.frontDoor, TestCameras.garage, TestCameras.garden]))

        await viewModel.load()

        #expect(viewModel.state == .loaded([TestCameras.frontDoor, TestCameras.garden]))
    }

    @Test func showsErrorWhenLoadingFails() async {
        let viewModel = makeViewModel(StubCameraProvider(error: StubError()))

        await viewModel.load()

        #expect(viewModel.state == .failed(message: "Stub-Fehler"))
    }

    @Test func focusesFirstCameraWithoutHistory() async {
        let viewModel = makeViewModel(StubCameraProvider([TestCameras.frontDoor, TestCameras.garden]))

        await viewModel.load()

        #expect(viewModel.preferredCameraID == "front-door")
    }

    @Test func focusesLastUsedCamera() async {
        let viewModel = makeViewModel(StubCameraProvider([TestCameras.frontDoor, TestCameras.garden]))
        await viewModel.load()

        viewModel.select(TestCameras.garden)

        #expect(viewModel.preferredCameraID == "garden")
        #expect(viewModel.lastCameraID == "garden")
    }

    @Test func ignoresUnknownLastCamera() async {
        settings.lastCameraID = "deleted-camera"
        let viewModel = makeViewModel(StubCameraProvider([TestCameras.frontDoor]))

        await viewModel.load()

        #expect(viewModel.preferredCameraID == "front-door")
        #expect(viewModel.cameraForAutoOpen() == nil)
    }

    @Test func autoOpensLastCameraOnLaunch() async {
        settings.lastCameraID = "garden"
        let viewModel = makeViewModel(StubCameraProvider([TestCameras.frontDoor, TestCameras.garden]))

        await viewModel.load()

        #expect(viewModel.cameraForAutoOpen() == TestCameras.garden)
    }

    @Test func respectsDisabledAutoOpen() async {
        settings.lastCameraID = "garden"
        settings.autoOpenLastCamera = false
        let viewModel = makeViewModel(StubCameraProvider([TestCameras.frontDoor, TestCameras.garden]))

        await viewModel.load()

        #expect(viewModel.cameraForAutoOpen() == nil)
    }
}
