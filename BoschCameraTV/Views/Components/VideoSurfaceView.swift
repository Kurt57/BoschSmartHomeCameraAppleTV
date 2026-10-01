import AVFoundation
import SwiftUI
import UIKit

/// Reine Videofläche auf Basis von `AVPlayerLayer` – ohne System-Transportleiste,
/// damit möglichst wenig UI über dem Kamerabild liegt.
struct VideoSurfaceView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        view.playerLayer.videoGravity = videoGravity
    }

    static func dismantleUIView(_ view: PlayerLayerView, coordinator: ()) {
        // Layer vom (app-weit geteilten) Player lösen.
        view.playerLayer.player = nil
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        // `layerClass` garantiert den Typ.
        layer as! AVPlayerLayer
    }
}
