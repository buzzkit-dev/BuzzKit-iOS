import Foundation

extension BuzzKit {
    /// Everything the SDK needs to run, created once and passed to ``BuzzKit/configure(with:)``.
    public struct Configuration: Sendable {
        /// The client key from the dashboard (`bk_pk_…`). Safe to ship in the app binary.
        public var apiKey: String

        /// The API origin. The default talks to BuzzKit Cloud; point it at your own
        /// deployment when self-hosting.
        public var apiURL: URL

        /// How much the SDK writes to the system log. Defaults to ``BuzzKitLogLevel/warn``.
        public var logLevel: BuzzKitLogLevel

        /// How notifications that arrive while the app is in the foreground are shown.
        /// Defaults to ``BuzzKit/ForegroundPresentation/banner``; override per
        /// notification through ``BuzzKitDelegate/buzzKit(_:willPresent:)``.
        public var foregroundPresentation: ForegroundPresentation

        /// Registers automatic session events (`$app.opened`, `$app.backgrounded`,
        /// `$session.ended`). Defaults to `true`.
        public var automaticSessionTracking: Bool

        /// The app group shared with the notification service extension. Required for
        /// delivered-receipts spillover and rich media caching from the extension;
        /// without it the extension still works, best effort.
        public var appGroup: String?

        /// Forces the APNs environment instead of detecting it from the embedded
        /// provisioning profile.
        public var pushEnvironment: BuzzKit.PushEnvironment?

        /// iOS hands three push callbacks to the app, not to BuzzKit: the device token,
        /// registration failures, and silent pushes. With this on (the default), BuzzKit
        /// receives them automatically and the app writes no forwarding code. Turn it
        /// off to keep full control and forward the three callbacks yourself through
        /// ``BuzzKit/didRegisterForRemoteNotifications(deviceToken:)``,
        /// ``BuzzKit/didFailToRegisterForRemoteNotifications(error:)``, and
        /// ``BuzzKit/didReceiveRemoteNotification(userInfo:)``.
        public var automaticPushHandling: Bool

        public init(
            apiKey: String,
            apiURL: URL = URL(string: "https://api.buzzkit.dev")!,
            logLevel: BuzzKitLogLevel = .warn,
            foregroundPresentation: ForegroundPresentation = .banner,
            automaticSessionTracking: Bool = true,
            appGroup: String? = nil,
            pushEnvironment: BuzzKit.PushEnvironment? = nil,
            automaticPushHandling: Bool = true
        ) {
            self.apiKey = apiKey
            self.apiURL = apiURL
            self.logLevel = logLevel
            self.foregroundPresentation = foregroundPresentation
            self.automaticSessionTracking = automaticSessionTracking
            self.appGroup = appGroup
            self.pushEnvironment = pushEnvironment
            self.automaticPushHandling = automaticPushHandling
        }
    }

    /// How a push arriving while the app is open is presented.
    public enum ForegroundPresentation: Sendable {
        /// The system banner with sound, as if the app were closed.
        case banner
        /// Nothing; the app reads the payload through the delegate and renders its own
        /// surface, or stays quiet.
        case hidden
    }

    /// Which APNs environment a device token belongs to.
    public enum PushEnvironment: String, Sendable {
        case production
        case sandbox
    }
}
