import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor enum SystemOpener {
    static func open(_ url: URL) {
        sharedApplication?.open(url)
    }

    static var sharedApplication: UIApplication? {
        UIApplication.perform(#selector(getter: UIApplication.shared))?.takeUnretainedValue() as? UIApplication
    }
}
#endif
