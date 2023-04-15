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

    private let hostname: CFString
    private var completion: (([Data]?, Error?) -> Void)

    private var host: CFHost?

    deinit {
        stop()
    }

    public init(hostname: CFString, completion: @escaping (([Data]?, Error?) -> Void)) {
        self.hostname = hostname
        self.completion = completion
    }

    public func start() {
        assert(host == nil)

        let host = CFHostCreateWithName(kCFAllocatorDefault, hostname).takeRetainedValue()
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

        completion(addresses, nil)
    }

    func didFailWithHostStreamError(_ error: CFStreamError) {
        didFailWithError(DNSResolverError.streamError)
    }

    func didFailWithError(_ error: Error) {
        stop()

        completion(nil, error)
    }

}
