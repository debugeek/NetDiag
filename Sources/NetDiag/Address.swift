//  
//  Address.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/4/17.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public enum Address {
    case ipv4(_: in_addr)
    case ipv6(_: in6_addr)
}

extension Address {
    
    public var sa_family: Darwin.sa_family_t {
        switch self {
            case .ipv4:
                return Darwin.sa_family_t(AF_INET)
            case .ipv6:
                return Darwin.sa_family_t(AF_INET6)
        }
    }
    
    public var sockaddr_storage: Darwin.sockaddr_storage {
        var sockaddr_storage = Darwin.sockaddr_storage()
        switch self {
            case .ipv4(let addr):
                withUnsafeMutablePointer(to: &sockaddr_storage, { ptr in
                    ptr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ptr in
                        ptr.pointee.sin_family = sa_family_t(AF_INET)
                        ptr.pointee.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                        ptr.pointee.sin_addr = addr
                    }
                })
            case .ipv6(let addr):
                withUnsafeMutablePointer(to: &sockaddr_storage, { ptr in
                    ptr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { ptr in
                        ptr.pointee.sin6_family = sa_family_t(AF_INET6)
                        ptr.pointee.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                        ptr.pointee.sin6_addr = addr
                    }
                })
        }
        return sockaddr_storage
    }

}
