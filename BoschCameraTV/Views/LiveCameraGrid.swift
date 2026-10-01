import SwiftUI

/// Startseite als Sicherheits-Monitor: alle Kameras live, randlos, vier pro Bildschirm
/// (2 × 2). Weitere Kameras liegen darunter und sind per Fokus scrollbar.
struct LiveCameraGrid: View {
    let cameras: [Camera]
    let streams: any StreamProviding
    let preferredCameraID: Camera.ID?
    let onSelect: (Camera) -> Void
    let onOpenSettings: () -> Void

    private enum FocusTarget: Hashable {
        case camera(Camera.ID)
        case settings
    }

    @FocusState private var focusedTarget: FocusTarget?

    var body: some View {
        GeometryReader { geometry in
            let columnCount = cameras.count == 1 ? 1 : 2
            let tileSize = CGSize(
                width: geometry.size.width / CGFloat(columnCount),
                height: geometry.size.height / CGFloat(columnCount)
            )
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(tileSize.width), spacing: 0), count: columnCount),
                    spacing: 0
                ) {
                    ForEach(cameras) { camera in
                        LiveCameraTile(camera: camera, streams: streams) {
                            onSelect(camera)
                        }
                        .frame(width: tileSize.width, height: tileSize.height)
                        .focused($focusedTarget, equals: .camera(camera.id))
                    }
                }
                .scrollTargetLayout()
                // Bei nur einer Reihe vertikal zentrieren.
                .frame(minHeight: geometry.size.height)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .background(Color.black)
        .overlay(alignment: .top) { settingsRow }
        .defaultFocus($focusedTarget, preferredCameraID.map(FocusTarget.camera))
    }

    /// Dezenter Zugang zu den Einstellungen: oben rechts, per „nach oben wischen“.
    private var settingsRow: some View {
        HStack {
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .accessibilityLabel("Einstellungen")
            }
            .focused($focusedTarget, equals: .settings)
            .opacity(focusedTarget == .settings ? 1 : 0.35)
        }
        .focusSection()
    }
}
