//
//  DNSResolver.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/4/15.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public class DNSResolver {

    public init() {}
    
    public func resolve(_ hostname: String) -> [Address]? {
        let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()

        CFHostStartInfoResolution(host, .addresses, nil)

        var resolved: DarwinBoolean = false
        guard let addresses = CFHostGetAddressing(host, &resolved)?.takeUnretainedValue() as? [Data], resolved.boolValue else {
            return nil
        }

        return addresses.compactMap { address in
            let addr = address.withUnsafeBytes { $0.load(as: sockaddr.self) }
            if addr.sa_family == AF_INET {
                return .ipv4(address.withUnsafeBytes { $0.load(as: sockaddr_in.self) }.sin_addr)
            } else if addr.sa_family == AF_INET6 {
                return .ipv6(address.withUnsafeBytes { $0.load(as: sockaddr_in6.self) }.sin6_addr)
            } else {
                return nil
            }
        }
    }

}
