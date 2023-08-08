//  
//  Address.swift
//  NetDiag
//
//  Created by Xiao Jin on 2023/4/17.
//  Copyright © 2023 debugeek. All rights reserved.
//

import Foundation

public enum Address {
    case ipv4(_: in_addr)
    case ipv6(_: in6_addr)
}

extension Address {
    
    public var sa_family: Darwin.sa_family_t {
        switch self {
            case .ipv4:
                return Darwin.sa_family_t(AF_INET)
            case .ipv6:
                return Darwin.sa_family_t(AF_INET6)
        }
    }

}
