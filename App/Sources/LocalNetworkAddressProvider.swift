import Darwin
import Foundation

enum LocalNetworkAddressProvider {
    static func ipv4Addresses() -> [String] {
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let firstInterface = interfaceList else {
            return []
        }
        defer { freeifaddrs(interfaceList) }

        var addresses = Set<String>()
        var interface: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let current = interface {
            defer { interface = current.pointee.ifa_next }

            guard let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  current.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  current.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                addresses.insert(String(decoding: bytes, as: UTF8.self))
            }
        }

        return addresses.sorted()
    }
}
