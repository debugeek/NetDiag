//
//  PingFactoryV6.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/4/17.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public enum ICMP6Type: UInt8 {
    case echoRequest = 128
    case echoReply   = 129
}

class PingFactoryV6: PingFactory {
    
    func buildPacket(identifier: UInt16, sequenceNumber: UInt16, payload: Data?) -> Data {
        var header = ICMPHeader()
        header.type = ICMP6Type.echoRequest.rawValue
        header.identifier = identifier
        header.sequenceNumber = CFSwapInt16HostToBig(sequenceNumber)
        
        var packet = withUnsafeBytes(of: header) { Data($0) }
        if let payload = payload {
            packet += payload
        }
        
        return packet
    }
    
    func readPacket(_ dataBuf: Data, cmsgBuf: [UInt8], identifier: inout UInt16?, sequenceNumber: inout UInt16?, timeToLive: inout UInt8?) -> Error? {
        var dataBuf = dataBuf
        var headerLen = 0
        
        guard let ICMPHeader = readICMPHeader(dataBuf, &headerLen) else {
            return PingError.unexpectedPacket
        }
        dataBuf = dataBuf.advanced(by: headerLen)
        
        guard ICMPHeader.type == ICMP6Type.echoReply.rawValue else {
            return PingError.unexpectedPacket
        }
        
        identifier = ICMPHeader.identifier
        sequenceNumber = CFSwapInt16BigToHost(ICMPHeader.sequenceNumber)

        var cmsgBuf = cmsgBuf
        timeToLive = cmsgBuf.withUnsafeMutableBytes { cmsgBufPtr in
            let cmsghdrPtr = cmsgBufPtr.bindMemory(to: cmsghdr.self)
            if cmsghdrPtr[0].cmsg_level == IPPROTO_IPV6, cmsghdrPtr[0].cmsg_type == IPV6_2292HOPLIMIT {
                return cmsgBufPtr.load(fromByteOffset: MemoryLayout<cmsghdr>.size, as: UInt8.self)
            } else {
                return nil
            }
        }
        
        return nil
    }
    
    func readICMPHeader(_ dataBuf: Data, _ headerLen: inout Int) -> ICMPHeader? {
        guard dataBuf.count >= MemoryLayout<ICMPHeader>.size else {
            return nil
        }
        
        let header = dataBuf.withUnsafeBytes {
            $0.load(as: ICMPHeader.self)
        }
        
        guard header.code == 0 else {
            return nil
        }
        
        headerLen = MemoryLayout<ICMPHeader>.size
        
        return header
    }
    
}
