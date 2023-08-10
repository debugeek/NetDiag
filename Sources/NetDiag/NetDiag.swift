//
//  NetDiag.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/4/15.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public struct NetDiag {

    public static func ping(_ destination: String, usingBlock block: @escaping ((PingResult) -> Void)) {
        let resolver = DNSResolver(hostname: destination) { addresses, error in
            guard let address = addresses?.first, error == nil else {
                return
            }

            let endpoint = EndPoint(address: address)
            let ping = Ping(endpoint: endpoint)
            ping?.sendPing(usingBlock: { result in
                block(result)
            })
        }
        resolver.start()
    }

    public static func traceroute(_ destination: String, usingBlock block: @escaping ((TracerouteResult, Bool) -> Void)) {
        let resolver = DNSResolver(hostname: destination) { addresses, error in
            guard let address = addresses?.first, error == nil else {
                return
            }

            let endpoint = EndPoint(address: address)
            let traceroute = Traceroute(endpoint: endpoint)
            traceroute.waitTime = 1
            traceroute.probesPerHop = 1
            traceroute.start(usingBlock: { result, stopped in
                block(result, stopped)
            })
        }
        resolver.start()
    }

    public static func scan(_ destination: String, _ ports: [UInt16], timeout: TimeInterval, maxConcurrentOperationCount: Int, usingBlock block: @escaping ((TCPScanResult) -> Void)) {
        let resolver = DNSResolver(hostname: destination) { addresses, error in
            guard let address = addresses?.first, error == nil else {
                return
            }

            let endpoints = ports.map { EndPoint(address: address, port: $0) }
            let scanner = TCPScanner(endpoints: endpoints, timeout: timeout, maxConcurrentOperationCount: maxConcurrentOperationCount)
            scanner.scan { result in
                block(result)
            }
        }
        resolver.start()
    }

}
