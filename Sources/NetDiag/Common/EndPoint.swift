//
//  Endpoint.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/8/8.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public struct EndPoint {

    let address: Address
    let port: uint16

    public init(address: Address, port: UInt16 = 0) {
        self.address = address
        self.port = port
    }

    public var sockaddr_storage: Darwin.sockaddr_storage {
        var sockaddr_storage = Darwin.sockaddr_storage()
        switch address {
            case .ipv4(let addr):
                withUnsafeMutablePointer(to: &sockaddr_storage, { ptr in
                    ptr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ptr in
                        ptr.pointee.sin_family = sa_family_t(AF_INET)
                        ptr.pointee.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                        ptr.pointee.sin_addr = addr
                        ptr.pointee.sin_port = port.bigEndian
                    }
                })
            case .ipv6(let addr):
                withUnsafeMutablePointer(to: &sockaddr_storage, { ptr in
                    ptr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { ptr in
                        ptr.pointee.sin6_family = sa_family_t(AF_INET6)
                        ptr.pointee.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                        ptr.pointee.sin6_addr = addr
                        ptr.pointee.sin6_port = port.bigEndian
                    }
                })
        }
        return sockaddr_storage
    }

    public var sockaddr: Darwin.sockaddr {
        return withUnsafePointer(to: sockaddr_storage, { storagePtr in
            storagePtr.withMemoryRebound(to: Darwin.sockaddr.self, capacity: 1) {
                $0.pointee
            }
        })
    }

}
