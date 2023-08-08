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
    private let callback: ((TracerouteResult, Bool) -> Void)?
    
    public init?(endpoint: EndPoint, callback: @escaping (_ result: TracerouteResult, _ stopped: Bool) -> Void) {
        self.ping = Ping(endpoint: endpoint)
        self.callback = callback
    }
    
    public func start() {
        assert(maxTTL > 0, "maxTTL must be > 0")
        assert(maxTTL <= 255, "maxTTL must be <= 255")
        assert(firstTTL > 0, "firstTTL must be > 0")
        assert(firstTTL <= 255, "firstTTL must be <= 255")
        assert(firstTTL < maxTTL, "firstTTL (\(firstTTL)) may not be greater than maxTTL (\(maxTTL)")
        assert(probesPerHop > 0, "probesPerHop must be > 0")
        
        sendPing(firstTTL, 0)
    }
    
    func sendPing(_ ttl: UInt8, _ retry: UInt) {
        ping?.setMaxTTL(ttl)
        ping?.sendPing(timeout: waitTime) { [weak self] result in
            self?.didReceive(result, ttl, retry)
        }
    }
    
    func didReceive(_ pingResult: PingResult, _ ttl: UInt8, _ retry: UInt) {
        let result = TracerouteResult(seq: ttl, src: pingResult.src, retry: retry, rtt: pingResult.rtt)
        
        if retry + 1 < probesPerHop {
            callback?(result, false)
            sendPing(ttl, retry + 1)
        } else if ttl + 1 < maxTTL, pingResult.error != nil {
            callback?(result, false)
            sendPing(ttl + 1, 0)
        } else {
            callback?(result, true)
        }
    }
    
}
