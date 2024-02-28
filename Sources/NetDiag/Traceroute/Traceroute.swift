//
//  Traceroute.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/5/3.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public struct TracerouteResult {
    public let seq: UInt8
    public let src: String?
    public let retry: UInt
    public let rtt: TimeInterval?
}

public class Traceroute {

    public var probesPerHop: UInt = 3

    public var firstTTL: UInt8 = 1
    public var maxTTL: UInt8 = 30
    
    public var waitTime: TimeInterval = 5
    
    private let ping: Ping
    
    public init?(endpoint: EndPoint) {
        guard let ping = Ping(endpoint: endpoint) else {
            return nil
        }
        self.ping = ping
    }

    public func trace(queue: DispatchQueue = .global(), usingBlock block: @escaping (TracerouteResult, Bool) -> Void) {
        assert(maxTTL > 0, "maxTTL must be > 0")
        assert(maxTTL <= 255, "maxTTL must be <= 255")
        assert(firstTTL > 0, "firstTTL must be > 0")
        assert(firstTTL <= 255, "firstTTL must be <= 255")
        assert(firstTTL < maxTTL, "firstTTL (\(firstTTL)) may not be greater than maxTTL (\(maxTTL)")
        assert(probesPerHop > 0, "probesPerHop must be > 0")

        queue.async {
            var ttl = self.firstTTL
            var retry: UInt = 0

            while true {
                self.ping.setMaxTTL(ttl)

                let result = self.ping.ping(timeout: self.waitTime)

                var stopped = false
                if retry + 1 < self.probesPerHop {
                    retry += 1
                } else if ttl + 1 < self.maxTTL, result.error != nil {
                    retry = 0
                    ttl += 1
                } else {
                    stopped = true
                }
                block(TracerouteResult(seq: ttl,
                                       src: result.src,
                                       retry: retry,
                                       rtt: result.rtt), stopped)
                if stopped {
                    break
                }
            }
        }
    }
    
}
