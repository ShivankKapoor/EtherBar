//
//  TrafficMonitor.swift
//  EtherBar
//

import Foundation
import SystemConfiguration

struct InterfaceBytes {
    let ibytes: UInt64
    let obytes: UInt64

    var total: UInt64 { ibytes + obytes }
}

class TrafficMonitor {
    private var lastSample: [String: InterfaceBytes] = [:]
    private var lastSampleTime: Date = Date()

    /// Returns bytes/sec for each interface since last call
    func sample() -> [String: Double] {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleTime)
        guard elapsed >= 0.1 else { return [:] }

        let current = readAllInterfaces()
        var rates: [String: Double] = [:]

        for (iface, bytes) in current {
            if let prev = lastSample[iface] {
                // Guard against counter wrap or reset
                if bytes.total >= prev.total {
                    let delta = Double(bytes.total - prev.total)
                    rates[iface] = delta / elapsed
                } else {
                    rates[iface] = 0
                }
            } else {
                rates[iface] = 0
            }
        }

        lastSample = current
        lastSampleTime = now
        return rates
    }

    private func readAllInterfaces() -> [String: InterfaceBytes] {
        var result: [String: InterfaceBytes] = [:]

        // Use getifaddrs which is faster and more accurate than shelling out to netstat
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let ifa = ptr.pointee
            let family = ifa.ifa_addr.pointee.sa_family

            if family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                let ibytes = UInt64(networkData.ifi_ibytes)
                let obytes = UInt64(networkData.ifi_obytes)

                if let existing = result[name] {
                    if ibytes + obytes > existing.total {
                        result[name] = InterfaceBytes(ibytes: ibytes, obytes: obytes)
                    }
                } else {
                    result[name] = InterfaceBytes(ibytes: ibytes, obytes: obytes)
                }
            }

            if let next = ifa.ifa_next {
                ptr = next
            } else {
                break
            }
        }

        return result
    }
}
