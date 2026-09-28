import Foundation

enum ScreenCaptureError: LocalizedError {
    case permissionNotGranted
    case noDisplays
    case displayNotFound
    case noWindows
    case emptyResult
    case selectionTooSmall
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionNotGranted:
            return "Screen Recording access has not been granted to Snapper."
        case .noDisplays:
            return "No attached displays were found."
        case .displayNotFound:
            return "The requested display is no longer available."
        case .noWindows:
            return "No capturable windows were found on screen."
        case .emptyResult:
            return "ScreenCaptureKit returned an empty image."
        case .selectionTooSmall:
            return "The selected region was too small to capture."
        case .imageEncodingFailed:
            return "The captured image could not be encoded as PNG."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionNotGranted:
            return "Open System Settings › Privacy & Security › Screen Recording and enable Snapper, then try again."
        default:
            return nil
        }
    }
}
