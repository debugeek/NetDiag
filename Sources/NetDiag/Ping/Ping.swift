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

private class PingAction {
    let sendTime: UInt64
    
    init(sendTime: UInt64) {
        self.sendTime = sendTime
    }
    
    var block: ((PingResult) -> Void)?
    
    var timer: Timer?
    
    func complete(with result: PingResult) {
        guard let block = block else {
            return
        }
        
        if let timer = timer {
            timer.invalidate()
            self.timer = nil
        }
        
        block(result)
        self.block = nil
    }
}

public class Ping {
    
    fileprivate var socket: CFSocket?
    fileprivate let endpoint: EndPoint
    fileprivate let factory: PingFactory
    
    fileprivate let identifier: UInt16 = UInt16.random(in: .min ... .max)
    fileprivate var nextSequenceNumber: UInt16 = 0
    
    fileprivate var actions = [UInt16: PingAction]()
    
    public init?(endpoint: EndPoint) {
        self.endpoint = endpoint
        
        let fd: Int32
        switch endpoint.address {
            case .ipv4:
                fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
                self.factory = PingFactoryV4()
            case .ipv6:
                fd = Darwin.socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)
                self.factory = PingFactoryV6()
        }
        if fd < 0 {
            return nil
        }
        
        var context = CFSocketContext()
        context.info = Unmanaged.passRetained(self).toOpaque()
        self.socket = CFSocketCreateWithNative(kCFAllocatorDefault, fd, CFSocketCallBackType.readCallBack.rawValue, readCallback, &context)
        
        var opt: Int32 = 1
        switch endpoint.address {
            case .ipv4:
                setsockopt(fd, IPPROTO_IP, IP_RECVTTL, &opt, socklen_t(MemoryLayout<Int32>.size))
                
            case .ipv6:
                setsockopt(fd, IPPROTO_IPV6, IPV6_2292HOPLIMIT, &opt, socklen_t(MemoryLayout<Int32>.size))
        }
        
        let source = CFSocketCreateRunLoopSource(nil, socket, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
    }
    
    public func sendPing(payload: Data? = nil, timeout: TimeInterval = 1, usingBlock block: @escaping ((PingResult) -> Void)) {
        let sequenceNumber = nextSequenceNumber
        nextSequenceNumber += 1

        let sendBuf = factory.buildPacket(identifier: identifier, sequenceNumber: sequenceNumber, payload: payload)
        let bytesSent = sendBuf.withUnsafeBytes { sendBufPtr in
            guard let sendBufPtrAddr = sendBufPtr.baseAddress else { return -1 }
            return withUnsafePointer(to: endpoint.sockaddr_storage) { storagePtr in
                storagePtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                    sendto(CFSocketGetNative(socket), sendBufPtrAddr, sendBufPtr.count, 0, addrPtr, socklen_t(addrPtr.pointee.sa_len))
                }
            }
        }
        if bytesSent > 0 {
            let action = PingAction(sendTime: mach_absolute_time())
            action.block = block
            action.timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] timer in
                guard let self = self, let action = self.actions[sequenceNumber] else {
                    return
                }
                self.actions[sequenceNumber] = nil
                
                let result = PingResult(seq: sequenceNumber, error: PingError.timedOut)
                action.complete(with: result)
            }
            actions[sequenceNumber] = action
        } else {
            let result = PingResult(seq: sequenceNumber, error: PingError.socketError)
            block(result)
        }
    }
    
    public func setMaxTTL(_ ttl: UInt8) {
        var ttl = Int32(ttl)
        switch endpoint.address {
            case .ipv4:
                setsockopt(CFSocketGetNative(socket), IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
            case .ipv6:
                setsockopt(CFSocketGetNative(socket), IPPROTO_IPV6, IPV6_UNICAST_HOPS, &ttl, socklen_t(MemoryLayout<Int32>.size))
        }
    }
    
}

private func readCallback(socket: CFSocket?, type: CFSocketCallBackType, address: CFData?, data: UnsafeRawPointer?, info: UnsafeMutableRawPointer?) -> Void {
    guard let info = info, let socket = socket else {
        return
    }
    
    let ping = Unmanaged<Ping>.fromOpaque(info).takeUnretainedValue()
    assert(ping.socket == socket)
    
    let recvTime = mach_absolute_time()
    
    var srcAddr = sockaddr_storage()
    var cmsgBuf = [UInt8](repeating: 0, count: (MemoryLayout<cmsghdr>.size) + MemoryLayout<UInt32>.size)
    var recvBuf = [UInt8](repeating: 0, count: Int(IP_MAXPACKET))
    var iov = iovec(iov_base: recvBuf.withUnsafeMutableBytes { $0.baseAddress }, iov_len: recvBuf.count)
    var msghdr = msghdr(msg_name: withUnsafeMutablePointer(to: &srcAddr) { $0 }, msg_namelen: socklen_t(MemoryLayout.size(ofValue: srcAddr)),
                        msg_iov: withUnsafeMutablePointer(to: &iov) { $0 }, msg_iovlen: 1,
                        msg_control: cmsgBuf.withUnsafeMutableBytes { $0.baseAddress }, msg_controllen: socklen_t(cmsgBuf.count),
                        msg_flags: 0)
    let bytesRcvd = withUnsafeMutablePointer(to: &msghdr) { msghdrPtr in
        recvmsg(CFSocketGetNative(socket), msghdrPtr, 0)
    }
    guard bytesRcvd > 0 else {
        return
    }
    
    var identifier: UInt16?
    var sequenceNumber: UInt16?
    var timeToLive: UInt8?
    
    let dataBuf = Data(bytes: recvBuf, count: bytesRcvd)
    let error = ping.factory.readPacket(dataBuf, cmsgBuf: cmsgBuf, identifier: &identifier, sequenceNumber: &sequenceNumber, timeToLive: &timeToLive)
    
    guard let identifier = identifier, identifier == ping.identifier else {
        return
    }
    
    guard let sequenceNumber = sequenceNumber, let action = ping.actions[sequenceNumber] else {
        return
    }
    
    ping.actions[sequenceNumber] = nil
    
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let rtt = (recvTime - action.sendTime)*UInt64(timebase.numer)/UInt64(timebase.denom);
    
    let src: String?
    switch Int32(srcAddr.ss_family) {
        case AF_INET:
            src = withUnsafeBytes(of: &srcAddr) { srcAddrPtr in
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var addr = srcAddrPtr.load(as: sockaddr_in.self).sin_addr
                inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                return String(cString: buf)
            }
            
        case AF_INET6:
            src = withUnsafeBytes(of: &srcAddr) { srcAddrPtr in
                var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                var addr = srcAddrPtr.load(as: sockaddr_in6.self).sin6_addr
                inet_ntop(AF_INET6, &addr, &buf, socklen_t(INET6_ADDRSTRLEN))
                return String(cString: buf)
            }
            
        default: src = nil
    }
    
    let result = PingResult(seq: sequenceNumber,
                            error: error,
                            ttl: timeToLive,
                            rtt: Double(rtt)/1.0e6,
                            src: src)
    action.complete(with: result)
}
