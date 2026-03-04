//
//  NetworkMonitor.swift
//  EtherBar
//

import Foundation
import Network
import Observation

@Observable
class NetworkMonitor {
    var isEthernetConnected: Bool = false

    private let monitor = NWPathMonitor(requiredInterfaceType: .wiredEthernet)
    private let queue = DispatchQueue(label: "EtherBarNetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isEthernetConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
