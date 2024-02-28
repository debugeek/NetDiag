//
//  Ping.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/4/16.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public enum PingError: Error {
    case socketError
    case timedOut
    case unexpectedPacket
    case timeToLiveExceeded
}

public struct PingResult {
    public private(set) var seq: UInt16?
    public private(set) var error: Error?
    public private(set) var ttl: UInt8?
    public private(set) var rtt: TimeInterval?
    public private(set) var src: String?
}

protocol PingFactory {
    func buildPacket(identifier: UInt16, sequenceNumber: UInt16, payload: Data?) -> Data
    func readPacket(_ dataBuf: Data, cmsgBuf: [UInt8], identifier: inout UInt16?, sequenceNumber: inout UInt16?, timeToLive: inout UInt8?) -> Error?
}

public class Ping {
    
    private let fd: Int32
    private let endpoint: EndPoint
    private let factory: PingFactory

    private let identifier: UInt16 = UInt16.random(in: .min ... .max)
    private var nextSequenceNumber: UInt16 = 0

    public init?(endpoint: EndPoint) {
        self.endpoint = endpoint

        switch endpoint.address {
            case .ipv4:
                fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
                self.factory = PingFactoryV4()
            case .ipv6:
                fd = socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)
                self.factory = PingFactoryV6()
        }
        if fd < 0 {
            return nil
        }

        var opt: Int32 = 1
        switch endpoint.address {
            case .ipv4:
                setsockopt(fd, IPPROTO_IP, IP_RECVTTL, &opt, socklen_t(MemoryLayout<Int32>.size))
            case .ipv6:
                setsockopt(fd, IPPROTO_IPV6, IPV6_2292HOPLIMIT, &opt, socklen_t(MemoryLayout<Int32>.size))
        }
    }

    public func ping(payload: Data? = nil, timeout: TimeInterval = 1) -> PingResult {
        let currentSequenceNumber = nextSequenceNumber
        nextSequenceNumber += 1

        let startTime = Date()
        setSndTimeout(timeout)

        let sendBuf = factory.buildPacket(identifier: identifier, sequenceNumber: currentSequenceNumber, payload: payload)
        let bytesSent = sendBuf.withUnsafeBytes { sendBufPtr in
            guard let sendBufPtrAddr = sendBufPtr.baseAddress else { return -1 }
            return withUnsafePointer(to: endpoint.sockaddr_storage) { storagePtr in
                storagePtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                    sendto(fd, sendBufPtrAddr, sendBufPtr.count, 0, addrPtr, socklen_t(addrPtr.pointee.sa_len))
                }
            }
        }
        if bytesSent <= 0 {
            return PingResult(seq: currentSequenceNumber, error: PingError.socketError)
        }

        while true {
            let duration = Date().timeIntervalSince(startTime)
            if duration >= timeout {
                return PingResult(seq: currentSequenceNumber, error: PingError.timedOut)
            }

            setRcvTimeout(timeout - duration)

            let (srcAddr, bytesRcvd, recvBuf, cmsgBuf) = receive()
            guard bytesRcvd > 0 else {
                continue
            }

            let endTime = Date()

            var identifier: UInt16?
            var sequenceNumber: UInt16?
            var timeToLive: UInt8?

            let dataBuf = Data(bytes: recvBuf, count: bytesRcvd)
            let error = factory.readPacket(dataBuf, cmsgBuf: cmsgBuf, identifier: &identifier, sequenceNumber: &sequenceNumber, timeToLive: &timeToLive)

            guard let identifier = identifier, identifier == identifier,
                  let sequenceNumber = sequenceNumber, sequenceNumber == currentSequenceNumber else {
                continue
            }

            return PingResult(seq: sequenceNumber,
                              error: error,
                              ttl: timeToLive,
                              rtt: endTime.timeIntervalSince(startTime),
                              src: srcAddr.address)
        }
    }

    private func receive() -> (src: sockaddr_storage, bytesRcvd: Int, recvBuf: [UInt8], cmsgBuf: [UInt8]) {
        var src = sockaddr_storage()
        var cmsgBuf = [UInt8](repeating: 0, count: (MemoryLayout<cmsghdr>.size) + MemoryLayout<UInt32>.size)
        var recvBuf = [UInt8](repeating: 0, count: Int(IP_MAXPACKET))
        var iov = iovec(iov_base: recvBuf.withUnsafeMutableBytes { $0.baseAddress }, iov_len: recvBuf.count)
        var msghdr = msghdr(msg_name: withUnsafeMutablePointer(to: &src) { $0 }, msg_namelen: socklen_t(MemoryLayout.size(ofValue: src)),
                            msg_iov: withUnsafeMutablePointer(to: &iov) { $0 }, msg_iovlen: 1,
                            msg_control: cmsgBuf.withUnsafeMutableBytes { $0.baseAddress }, msg_controllen: socklen_t(cmsgBuf.count),
                            msg_flags: 0)
        let bytesRcvd = withUnsafeMutablePointer(to: &msghdr) { msghdrPtr in
            recvmsg(fd, msghdrPtr, 0)
        }
        return (src, bytesRcvd, recvBuf, cmsgBuf)
    }

    public func setMaxTTL(_ ttl: UInt8) {
        var ttl = Int32(ttl)
        switch endpoint.address {
            case .ipv4:
                setsockopt(fd, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
            case .ipv6:
                setsockopt(fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl, socklen_t(MemoryLayout<Int32>.size))
        }
    }

    private func setSndTimeout(_ timeout: TimeInterval) {
        var time = timeout.toTimeval()
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    }

    private func setRcvTimeout(_ timeout: TimeInterval) {
        var time = timeout.toTimeval()
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    }

}
