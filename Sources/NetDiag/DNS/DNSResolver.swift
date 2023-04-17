//
//  DNSResolver.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/4/15.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public enum DNSResolverError: Error {
    case streamError
    case unknownHost
}

public class DNSResolver {

    private let hostname: String
    private var completion: (([Address]?, Error?) -> Void)

    private var host: CFHost?

    deinit {
        stop()
    }

    public init(hostname: String, completion: @escaping (([Address]?, Error?) -> Void)) {
        self.hostname = hostname
        self.completion = completion
    }

    public func start() {
        assert(host == nil)

        let host = CFHostCreateWithName(kCFAllocatorDefault, hostname as CFString).takeRetainedValue()
        self.host = host

        var context = CFHostClientContext()
        context.info = Unmanaged.passRetained(self).toOpaque()

        CFHostSetClient(host, {(host: CFHost, typeInfo: CFHostInfoType, error: UnsafePointer<CFStreamError>?, info: UnsafeMutableRawPointer?) -> () in
            guard let info = info else {
                return
            }

            let resolver = Unmanaged<DNSResolver>.fromOpaque(info).takeUnretainedValue()

            if let error = error?.pointee, error.domain != 0 {
                resolver.didFailWithHostStreamError(error)
            } else {
                var resolved: DarwinBoolean = false
                if let addresses = CFHostGetAddressing(host, &resolved)?.takeUnretainedValue() as? [Data], resolved.boolValue {
                    resolver.didSuccessWithAddresses(addresses)
                } else {
                    resolver.didFailWithError(DNSResolverError.unknownHost)
                }
            }
        }, &context)

        CFHostScheduleWithRunLoop(host, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        var streamError = CFStreamError()
        if !CFHostStartInfoResolution(host, .addresses, &streamError) {
            didFailWithHostStreamError(streamError)
        }
    }

    func stop() {
        guard let host = host else {
            return
        }

        CFHostSetClient(host, nil, nil)
        CFHostUnscheduleFromRunLoop(host, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        self.host = nil
    }

    func didSuccessWithAddresses(_ addresses: [Data]) {
        stop()

        completion(addresses.compactMap { address in
            let addr = address.withUnsafeBytes { $0.load(as: sockaddr.self) }
            if addr.sa_family == AF_INET {
                return .ipv4(address.withUnsafeBytes { $0.load(as: sockaddr_in.self) }.sin_addr)
            } else if addr.sa_family == AF_INET6 {
                return .ipv6(address.withUnsafeBytes { $0.load(as: sockaddr_in6.self) }.sin6_addr)
            } else {
                return nil
            }
        }, nil)
    }

    func didFailWithHostStreamError(_ error: CFStreamError) {
        didFailWithError(DNSResolverError.streamError)
    }

    func didFailWithError(_ error: Error) {
        stop()

        completion(nil, error)
    }

}
