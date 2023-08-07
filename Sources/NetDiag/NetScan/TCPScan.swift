//
//  TCPScan.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/8/7.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public struct TCPScanResult {
    let address: Address
    let ports: [UInt16]
}

public class TCPScanner {

    private let addresses: [Address]
    private let ports: [UInt16]
    private let timeout: TimeInterval

    private let operationQueue: OperationQueue

    public init(addresses: [Address], ports: [UInt16], timeout: TimeInterval, maxConcurrentOperationCount: Int) {
        self.addresses = addresses
        self.ports = ports
        self.timeout = timeout
        self.operationQueue = OperationQueue()
        self.operationQueue.maxConcurrentOperationCount =  maxConcurrentOperationCount
    }

    public func scan(usingBlock block: @escaping (TCPScanResult) -> Void) {
        for address in addresses {
            operationQueue.addOperation(TCPScanOperation(address: address, ports: ports, timeout: timeout, completion: block))
        }
    }

    public func stop() {
        operationQueue.cancelAllOperations()
    }

}

private class TCPScanOperation: Operation {

    let address: Address
    let ports: [UInt16]
    let timeout: TimeInterval
    let completion: (TCPScanResult) -> Void

    init(address: Address, ports: [UInt16], timeout: TimeInterval, completion: @escaping (TCPScanResult) -> Void) {
        self.address = address
        self.ports = ports
        self.timeout = timeout
        self.completion = completion
        super.init()
    }

    override func main() {
        let ports = ports.filter { reachable($0) }

        guard !isCancelled else { return }

        completion(TCPScanResult(address: address, ports: ports))
    }

    func reachable(_ port: UInt16) -> Bool {
        let socket = socket(Int32(address.sa_family), SOCK_STREAM, IPPROTO_TCP);
        if socket < 0 {
            return false
        }
        defer {
            close(socket)
        }

        if fcntl(socket, F_SETFL, O_NONBLOCK) < 0 {
            return false
        }

        var storage = address.sockaddr_storage

        if address.sa_family == sa_family_t(AF_INET) {
            let sinPtr = withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    $0
                }
            }
            sinPtr.pointee.sin_port = port.bigEndian
        } else if address.sa_family == sa_family_t(AF_INET6) {
            let sin6Ptr = withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    $0
                }
            }
            sin6Ptr.pointee.sin6_port = port.bigEndian
        } else {
            return false
        }

        let addrPtr = withUnsafePointer(to: storage, { storagePtr in
            storagePtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                $0
            }
        })
        if connect(socket, addrPtr, socklen_t(addrPtr.pointee.sa_len)) == 0 {
            return true
        }

        if errno != EINPROGRESS, errno != EWOULDBLOCK {
            return false
        }

        var pollfds = [pollfd(fd: socket, events: Int16(POLLOUT), revents: 0)]
        let ret = Int(poll(&pollfds, nfds_t(pollfds.count), Int32(timeout*1000)))
        if ret <= 0 {
            return false
        }

        var sockerr = 0
        var len = socklen_t(MemoryLayout<socklen_t>.size);
        if getsockopt(socket, SOL_SOCKET, SO_ERROR, &sockerr, &len) == -1 {
            return false
        }
        if sockerr != 0 {
            return false
        }

        return true
    }

}
