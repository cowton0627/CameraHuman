import AVFoundation
import UIKit

extension AVCaptureVideoOrientation {
    init(_ interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .unknown, .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeRight
        case .landscapeRight:
            self = .landscapeLeft
        @unknown default:
            self = .portrait
        }
    }
}
