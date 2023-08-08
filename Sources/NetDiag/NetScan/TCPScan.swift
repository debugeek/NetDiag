//
//  TCPScan.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/8/7.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public struct TCPScanResult {
    let endpoint: EndPoint
    let reachable: Bool
}

public class TCPScanner {

    private let endpoints: [EndPoint]
    private let timeout: TimeInterval

    private let operationQueue: OperationQueue

    public init(endpoints: [EndPoint], timeout: TimeInterval, maxConcurrentOperationCount: Int) {
        self.endpoints = endpoints
        self.timeout = timeout
        self.operationQueue = OperationQueue()
        self.operationQueue.maxConcurrentOperationCount =  maxConcurrentOperationCount
    }

    public func scan(usingBlock block: @escaping (TCPScanResult) -> Void) {
        for endpoint in endpoints {
            operationQueue.addOperation(TCPScanOperation(endpoint: endpoint, timeout: timeout, completion: block))
        }
    }

    public func stop() {
        operationQueue.cancelAllOperations()
    }

}

private class TCPScanOperation: Operation {

    let endpoint: EndPoint
    let timeout: TimeInterval
    let completion: (TCPScanResult) -> Void

    init(endpoint: EndPoint, timeout: TimeInterval, completion: @escaping (TCPScanResult) -> Void) {
        self.endpoint = endpoint
        self.timeout = timeout
        self.completion = completion
        super.init()
    }

    override func main() {
        let reachable = reachable()

        guard !isCancelled else { return }

        completion(TCPScanResult(endpoint: endpoint, reachable: reachable))
    }

    func reachable() -> Bool {
        let socket = socket(Int32(endpoint.address.sa_family), SOCK_STREAM, IPPROTO_TCP);
        if socket < 0 {
            return false
        }
        defer {
            close(socket)
        }

        if fcntl(socket, F_SETFL, O_NONBLOCK) < 0 {
            return false
        }

        var sockaddr = endpoint.sockaddr
        if connect(socket, &sockaddr, socklen_t(sockaddr.sa_len)) == 0 {
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
