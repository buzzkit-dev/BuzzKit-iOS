#if canImport(UIKit) && !os(watchOS)
import Foundation
import ObjectiveC
import UIKit

@MainActor enum AppDelegateSwizzler {
    private static var installed = false

    static func installIfNeeded(swizzles: Bool) {
        guard swizzles, !installed, let delegate = SystemOpener.sharedApplication?.delegate else { return }
        installed = true
        let delegateClass: AnyClass = type(of: delegate)
        installTokenHook(on: delegateClass)
        installFailureHook(on: delegateClass)
        installRemoteNotificationHook(on: delegateClass)
    }

    private static func installTokenHook(on delegateClass: AnyClass) {
        let selector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        typealias Original = @convention(c) (AnyObject, Selector, UIApplication, Data) -> Void
        let original = existingIMP(delegateClass, selector, type: Original.self)
        let block: @convention(block) (AnyObject, UIApplication, Data) -> Void = { receiver, application, token in
            BuzzKit.didRegisterForRemoteNotifications(deviceToken: token)
            original?(receiver, selector, application, token)
        }
        replace(delegateClass, selector, types: "v@:@@", block: block)
    }

    private static func installFailureHook(on delegateClass: AnyClass) {
        let selector = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        typealias Original = @convention(c) (AnyObject, Selector, UIApplication, NSError) -> Void
        let original = existingIMP(delegateClass, selector, type: Original.self)
        let block: @convention(block) (AnyObject, UIApplication, NSError) -> Void = { receiver, application, error in
            BuzzKit.didFailToRegisterForRemoteNotifications(error: error)
            original?(receiver, selector, application, error)
        }
        replace(delegateClass, selector, types: "v@:@@", block: block)
    }

    private static func installRemoteNotificationHook(on delegateClass: AnyClass) {
        let selector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
        typealias Completion = @convention(block) (UIBackgroundFetchResult) -> Void
        typealias Original = @convention(c) (AnyObject, Selector, UIApplication, NSDictionary, @escaping Completion) -> Void
        let original = existingIMP(delegateClass, selector, type: Original.self)
        let block: @convention(block) (AnyObject, UIApplication, NSDictionary, @escaping Completion) -> Void = { receiver, application, userInfo, completion in
            let payload = PushPayload(userInfo: userInfo as? [AnyHashable: Any] ?? [:])
            if let original {
                let merger = FetchResultMerger(parts: 2, completion: completion)
                Task {
                    let result = await BuzzKit.handleRemotePayload(payload)
                    merger.complete(result.fetchResult)
                }
                original(receiver, selector, application, userInfo) { result in
                    merger.complete(result)
                }
            } else {
                let finish = UncheckedSendableBox(completion)
                Task {
                    let result = await BuzzKit.handleRemotePayload(payload)
                    await MainActor.run { finish.value(result.fetchResult) }
                }
            }
        }
        replace(delegateClass, selector, types: "v@:@@@?", block: block)
    }

    private static func existingIMP<T>(_ delegateClass: AnyClass, _ selector: Selector, type: T.Type) -> T? {
        guard let method = class_getInstanceMethod(delegateClass, selector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: T.self)
    }

    private static func replace(_ delegateClass: AnyClass, _ selector: Selector, types: String, block: Any) {
        let implementation = imp_implementationWithBlock(block)
        if let method = class_getInstanceMethod(delegateClass, selector) {
            method_setImplementation(method, implementation)
        } else {
            class_addMethod(delegateClass, selector, implementation, types)
        }
    }
}
#endif

#if canImport(UIKit) && !os(watchOS)
final class FetchResultMerger: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var best: UIBackgroundFetchResult = .noData
    private var completion: ((UIBackgroundFetchResult) -> Void)?

    init(parts: Int, completion: @escaping (UIBackgroundFetchResult) -> Void) {
        self.remaining = parts
        self.completion = completion
    }

    func complete(_ result: UIBackgroundFetchResult) {
        let finish: ((UIBackgroundFetchResult) -> Void)?
        let merged: UIBackgroundFetchResult
        lock.lock()
        best = Self.merge(best, result)
        remaining -= 1
        if remaining == 0 {
            finish = completion
            completion = nil
        } else {
            finish = nil
        }
        merged = best
        lock.unlock()
        guard let finish else { return }
        DispatchQueue.main.async {
            finish(merged)
        }
    }

    private static func merge(_ lhs: UIBackgroundFetchResult, _ rhs: UIBackgroundFetchResult) -> UIBackgroundFetchResult {
        if lhs == .newData || rhs == .newData { return .newData }
        if lhs == .failed || rhs == .failed { return .failed }
        return .noData
    }
}
#endif
