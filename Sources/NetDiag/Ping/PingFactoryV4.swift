//
//  PingFactoryV4.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/4/17.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public enum ICMPType: UInt8 {
    case echoReply   = 0
    case echoRequest = 8
    case timeToLiveExceeded = 11
}

struct IPHeader {
    var versionAndHeaderLength: UInt8 = 0
    var differentiatedServices: UInt8 = 0
    var totalLength: UInt16 = 0
    var identification: UInt16 = 0
    var flagsAndFragmentOffset: UInt16 = 0
    var timeToLive: UInt8 = 0
    var `protocol`: UInt8 = 0
    var headerChecksum: UInt16 = 0
    var sourceAddress: in_addr = in_addr()
    var destinationAddress: in_addr = in_addr()
}

struct ICMPHeader {
    var type: UInt8 = 0
    var code: UInt8 = 0
    var checksum: UInt16 = 0
    var identifier: UInt16 = 0
    var sequenceNumber: UInt16 = 0
}

class PingFactoryV4: PingFactory {
    
    func buildPacket(identifier: UInt16, sequenceNumber: UInt16, payload: Data?) -> Data {
        var header = ICMPHeader()
        header.type = ICMPType.echoRequest.rawValue
        header.identifier = identifier
        header.sequenceNumber = CFSwapInt16HostToBig(sequenceNumber)
        
        var packet = withUnsafeBytes(of: header) { Data($0) }
        if let payload = payload {
            packet += payload
        }
        
        let checksum = checksum(packet)
        packet[2] = UInt8(checksum & 0xff)
        packet[3] = UInt8(checksum >> 8 & 0xff)

        return packet
    }
    
    func readPacket(_ dataBuf: Data, cmsgBuf: [UInt8], identifier: inout UInt16?, sequenceNumber: inout UInt16?, timeToLive: inout UInt8?) -> Error? {
        var dataBuf = dataBuf
        var headerLen = 0
        
        guard let IPHeader = readIPHeader(dataBuf, &headerLen) else {
            return PingError.unexpectedPacket
        }
        dataBuf = dataBuf.advanced(by: headerLen)
        
        guard let ICMPHeader = readICMPHeader(dataBuf, &headerLen) else {
            return PingError.unexpectedPacket
        }

        if ICMPHeader.type == ICMPType.echoReply.rawValue {
            identifier = ICMPHeader.identifier
            sequenceNumber = CFSwapInt16BigToHost(ICMPHeader.sequenceNumber)
            timeToLive = IPHeader.timeToLive
        } else if ICMPHeader.type == ICMPType.timeToLiveExceeded.rawValue {
            dataBuf = dataBuf.advanced(by: headerLen)

            guard let IPHeader = readIPHeader(dataBuf, &headerLen) else {
                return PingError.unexpectedPacket
            }
            dataBuf = dataBuf.advanced(by: headerLen)

            guard let ICMPHeader = readICMPHeader(dataBuf, &headerLen) else {
                return PingError.unexpectedPacket
            }

            if ICMPHeader.type == ICMPType.echoRequest.rawValue {
                identifier = ICMPHeader.identifier
                sequenceNumber = CFSwapInt16BigToHost(ICMPHeader.sequenceNumber)
                timeToLive = IPHeader.timeToLive

                return PingError.timeToLiveExceeded
            } else {
                return PingError.unexpectedPacket
            }
        } else {
            return PingError.unexpectedPacket
        }
        
        return nil
    }

    func readIPHeader(_ dataBuf: Data, _ headerLen: inout Int) -> IPHeader? {
        guard dataBuf.count >= MemoryLayout<IPHeader>.size else {
            return nil
        }
        
        let header = dataBuf.withUnsafeBytes {
            $0.load(as: IPHeader.self)
        }
        
        guard header.versionAndHeaderLength & 0xf0 == 0x40, Int32(header.protocol) == IPPROTO_ICMP else {
            return nil
        }
        
        headerLen = Int(header.versionAndHeaderLength & 0x0f)*MemoryLayout<UInt32>.size
        
        return header
    }
    
    func readICMPHeader(_ databuf: Data, _ len: inout Int) -> ICMPHeader? {
        guard databuf.count >= MemoryLayout<ICMPHeader>.size else {
            return nil
        }
        
        let header = databuf.withUnsafeBytes {
            $0.load(as: ICMPHeader.self)
        }
        
        guard header.code == 0 else {
            return nil
        }
        
        len = MemoryLayout<ICMPHeader>.size
        
        return header
    }

    func checksum(_ data: Data) -> UInt16 {
        var data = data
        if data.count%2 == 1 {
            data += Data([0])
        }

        return data.withUnsafeBytes { buf in
            var sum: UInt32 = 0
            var idx = 0
            while idx < (buf.count - 1) {
                sum &+= UInt32(buf.load(fromByteOffset: idx, as: UInt16.self))
                idx += 2
            }

            sum = (sum >> 16) + (sum & 0xffff)
            sum += sum >> 16
            return UInt16(truncatingIfNeeded: ~sum)
        }
    }
    
}
