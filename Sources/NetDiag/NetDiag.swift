//
//  NetDiag.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/4/15.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public struct NetDiag {

    public static func ping(_ destination: String, 
                            queue: DispatchQueue = .global(),
                            usingBlock block: @escaping ((PingResult) -> Void)) {
        queue.async {
            let resolver = DNSResolver()
            guard let address = resolver.resolve(destination)?.first else {
                return
            }

            let endpoint = EndPoint(address: address)
            guard let ping = Ping(endpoint: endpoint) else {
                return
            }

            let result = ping.ping()
            block(result)
        }
    }

    public static func traceroute(_ destination: String, 
                                  queue: DispatchQueue = .global(),
                                  usingBlock block: @escaping ((TracerouteResult, Bool) -> Void)) {
        queue.async {
            let resolver = DNSResolver()
            guard let address = resolver.resolve(destination)?.first else {
                return
            }

            let endpoint = EndPoint(address: address)
            guard let traceroute = Traceroute(endpoint: endpoint) else {
                return
            }
            traceroute.waitTime = 1
            traceroute.probesPerHop = 1
            traceroute.trace { result, stopped in
                block(result, stopped)
            }
        }
    }

    public static func scan(_ destination: String, 
                            _ ports: [UInt16],
                            timeout: TimeInterval,
                            maxConcurrentOperationCount: Int,
                            queue: DispatchQueue = .global(),
                            usingBlock block: @escaping ((TCPScanResult) -> Void)) {
        queue.async {
            let resolver = DNSResolver()
            guard let address = resolver.resolve(destination)?.first else {
                return
            }

            let endpoints = ports.map { EndPoint(address: address, port: $0) }
            let scanner = TCPScanner(endpoints: endpoints, timeout: timeout, maxConcurrentOperationCount: maxConcurrentOperationCount)
            scanner.scan { result in
                block(result)
            }
        }
    }

}
