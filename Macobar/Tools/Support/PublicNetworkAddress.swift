import Darwin
import Foundation

/// Tells addresses on the public internet from this Mac and the local network, so a fetched page can't be aimed at local servers or the router.
enum PublicNetworkAddress {
    /// Whether `host` resolves, and every address it resolves to is public; false when it doesn't resolve.
    static func isPublicHost(_ host: String) async -> Bool {
        let bareHost = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        let addresses = await resolvedAddresses(of: bareHost)
        return !addresses.isEmpty && addresses.allSatisfy(isPublic)
    }

    /// Whether the numeric IPv4 or IPv6 `address` is public: not loopback, private, link-local, shared, multicast or reserved.
    static func isPublic(_ address: String) -> Bool {
        let numeric = String(address.prefix { $0 != "%" })
        var ipv4 = in_addr()
        if inet_pton(AF_INET, numeric, &ipv4) == 1 {
            return withUnsafeBytes(of: ipv4) { isPublicIPv4(Array($0)) }
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, numeric, &ipv6) == 1 {
            return withUnsafeBytes(of: ipv6) { isPublicIPv6(Array($0)) }
        }
        return false
    }

    /// Whether the four bytes of an IPv4 address are outside every special-purpose range.
    private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        let (first, second, third) = (bytes[0], bytes[1], bytes[2])
        let isSpecial = first == 0 || first == 10 || first == 127 || first >= 224
            || (first == 100 && second & 0xC0 == 64)
            || (first == 169 && second == 254)
            || (first == 172 && second & 0xF0 == 16)
            || (first == 192 && second == 168)
            || (first == 192 && second == 0 && third == 0)
            || (first == 198 && second & 0xFE == 18)
        return !isSpecial
    }

    /// Whether the sixteen bytes of an IPv6 address are public, checking any IPv4 address embedded in it too.
    private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        let embeddedIPv4 = Array(bytes[12...])
        if bytes[0..<10].allSatisfy({ $0 == 0 }) {
            // Unspecified, loopback, IPv4-compatible (::a.b.c.d) and IPv4-mapped (::ffff:a.b.c.d).
            if bytes[10] == 0, bytes[11] == 0 { return bytes[12..<15].contains { $0 != 0 } && isPublicIPv4(embeddedIPv4) }
            if bytes[10] == 0xFF, bytes[11] == 0xFF { return isPublicIPv4(embeddedIPv4) }
        }
        if bytes[0..<12] == [0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0] { return isPublicIPv4(embeddedIPv4) }
        if bytes[0] == 0x20, bytes[1] == 0x02 { return isPublicIPv4(Array(bytes[2..<6])) }
        let isUniqueLocal = bytes[0] & 0xFE == 0xFC
        let isLinkOrSiteLocal = bytes[0] == 0xFE && bytes[1] & 0x80 == 0x80
        let isMulticast = bytes[0] == 0xFF
        return !isUniqueLocal && !isLinkOrSiteLocal && !isMulticast
    }

    /// The numeric addresses `host` resolves to, looked up off the cooperative threads since the lookup blocks.
    private static func resolvedAddresses(of host: String) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: lookUp(host))
            }
        }
    }

    /// The numeric addresses `host` resolves to through the system resolver, the same one the download uses.
    private static func lookUp(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return [] }
        defer { freeaddrinfo(first) }
        return sequence(first: first, next: { $0.pointee.ai_next }).compactMap { entry in
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else {
                return nil
            }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }
}
