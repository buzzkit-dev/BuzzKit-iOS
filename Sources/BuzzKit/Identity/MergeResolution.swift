import Foundation

/// What to do with the anonymous id an identify call carried, once that call has come back.
enum MergeResolution: Equatable {
    /// The merge will never succeed, so stop sending the anonymous id.
    case settle
    /// The merge may still succeed, so keep the anonymous id for the next identify.
    case retain
}

/// Decides whether the pending merge is finished. Anything the API can recover from,
/// a network failure or a retryable rejection, keeps the anonymous id on the device.
func resolveMerge(after error: Error?) -> MergeResolution {
    guard let error else { return .settle }
    guard case let BuzzKitError.api(code, _) = error else { return .retain }
    return code == "merge_source_identified" || code == "merge_source_verified" ? .settle : .retain
}
