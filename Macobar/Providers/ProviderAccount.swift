/// The provider the user chose, with the non-secret details needed to reach it.
struct ProviderAccount: Codable, Equatable, Sendable {
    /// Which provider.
    var kind: ProviderKind
    /// Model ID requests use; for Azure, the deployment name.
    var model: String
    /// Azure resource name or AWS region, when the provider needs one.
    var setting: String?
}
