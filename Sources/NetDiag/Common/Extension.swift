//
//  Extension.swift
//  NetDiag
//
//  Created by Xiao Jin on 1/3/24.
//  Copyright © 2024 debugeek. All rights reserved.
//

import Foundation

extension sockaddr_storage {

    public var address: String? {
        switch Int32(self.ss_family) {
        case AF_INET:
            var addr = withUnsafePointer(to: self) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &(addr.sin_addr), &buffer, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buffer)
        case AF_INET6:
            var addr = withUnsafePointer(to: self) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            inet_ntop(AF_INET6, &addr.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
            return String(cString: buffer)
        default:
            return nil
        }
    }

    public var port: UInt16? {
        switch Int32(self.ss_family) {
        case AF_INET:
            return withUnsafePointer(to: self) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            }.sin_port.bigEndian
        case AF_INET6:
            return withUnsafePointer(to: self) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            }.sin6_port.bigEndian
        default:
            return nil
        }
    }

}

extension TimeInterval {

    func toTimeval() -> timeval {
        let usec = Int(self*1_000_000)
        return timeval(tv_sec: usec/1_000_000, tv_usec: Int32(usec%1_000_000))
    }

}
