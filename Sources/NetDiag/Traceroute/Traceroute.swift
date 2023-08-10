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

    public var probesPerHop: Int = 3
    
    public var firstTTL: UInt8 = 1
    public var maxTTL: UInt8 = 30
    
    public var waitTime: TimeInterval = 5
    
    private let ping: Ping?
    private var block: ((TracerouteResult, Bool) -> Void)?
    
    public init(endpoint: EndPoint) {
        self.ping = Ping(endpoint: endpoint)
    }

    public func start(usingBlock block: @escaping (_ result: TracerouteResult, _ stopped: Bool) -> Void) {
        assert(maxTTL > 0, "maxTTL must be > 0")
        assert(maxTTL <= 255, "maxTTL must be <= 255")
        assert(firstTTL > 0, "firstTTL must be > 0")
        assert(firstTTL <= 255, "firstTTL must be <= 255")
        assert(firstTTL < maxTTL, "firstTTL (\(firstTTL)) may not be greater than maxTTL (\(maxTTL)")
        assert(probesPerHop > 0, "probesPerHop must be > 0")

        self.block = block

        sendPing(firstTTL, 0)
    }
    
    func sendPing(_ ttl: UInt8, _ retry: UInt) {
        ping?.setMaxTTL(ttl)
        ping?.sendPing(timeout: waitTime) { pingResult in
            let result = TracerouteResult(seq: ttl, src: pingResult.src, retry: retry, rtt: pingResult.rtt)

            if retry + 1 < self.probesPerHop {
                self.block?(result, false)
                self.sendPing(ttl, retry + 1)
            } else if ttl + 1 < self.maxTTL, pingResult.error != nil {
                self.block?(result, false)
                self.sendPing(ttl + 1, 0)
            } else {
                self.block?(result, true)
            }
        }
    }
    
}
