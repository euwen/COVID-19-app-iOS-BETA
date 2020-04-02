//
//  BTLEListener.swift
//  CoLocate
//
//  Created by NHSX.
//  Copyright © 2020 NHSX. All rights reserved.
//

import Foundation
import CoreBluetooth

protocol BTLEPeripheral {
    var identifier: UUID { get }
}

extension CBPeripheral: BTLEPeripheral {
}

protocol BTLEListenerDelegate {
    func btleListener(_ listener: BTLEListener, didConnect peripheral: BTLEPeripheral)
    func btleListener(_ listener: BTLEListener, didDisconnect peripheral: BTLEPeripheral, error: Error?)
    func btleListener(_ listener: BTLEListener, didFindSonarId sonarId: UUID, forPeripheral peripheral: BTLEPeripheral)
    func btleListener(_ listener: BTLEListener, didReadRSSI RSSI: Int, forPeripheral peripheral: BTLEPeripheral)
    func btleListener(_ listener: BTLEListener, shouldReadRSSIFor peripheral: BTLEPeripheral) -> Bool
}

protocol BTLEListenerStateDelegate {
    func btleListener(_ listener: BTLEListener, didUpdateState state: CBManagerState)
}

protocol BTLEListener {
    func start(stateDelegate: BTLEListenerStateDelegate?, delegate: BTLEListenerDelegate?)
}

class ConcreteBTLEListener: NSObject, BTLEListener, CBCentralManagerDelegate, CBPeripheralDelegate {

    let rssiSamplingInterval: TimeInterval = 20.0
    let restoreIdentifier: String = "CoLocateCentralRestoreIdentifier"
    
    var stateDelegate: BTLEListenerStateDelegate?
    var delegate: BTLEListenerDelegate?
    var contactEventRecorder: ContactEventRecorder
    
    var centralManager: CBCentralManager?

    var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    init(contactEventRecorder: ContactEventRecorder = PlistContactEventRecorder.shared) {
        self.contactEventRecorder = contactEventRecorder
    }

    func start(stateDelegate: BTLEListenerStateDelegate?, delegate: BTLEListenerDelegate?) {
        self.stateDelegate = stateDelegate
        self.delegate = delegate

        guard centralManager == nil else { return }
        
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier])
    }
    
    // MARK: CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateDelegate?.btleListener(self, didUpdateState: central.state)
        
        switch (central.state) {
                
        case .unknown:
            print("\(#file).\(#function) .unknown")
            
        case .resetting:
            print("\(#file).\(#function) .resetting")
            
        case .unsupported:
            print("\(#file).\(#function) .unsupported")
            
        case .unauthorized:
            print("\(#file).\(#function) .unauthorized")
            
        case .poweredOff:
            print("\(#file).\(#function) .poweredOff")
            
        case .poweredOn:
            print("\(#file).\(#function) .poweredOn")
            
//            Comment this back in for testing if necessary, but be aware AllowDuplicates is
//            ignored while running in the background, so we can't count on this behaviour
//            central.scanForPeripherals(withServices: [BTLEBroadcaster.primaryServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            central.scanForPeripherals(withServices: [ConcreteBTLEBroadcaster.sonarServiceUUID])
        @unknown default:
            fatalError()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("\(#file).\(#function) discovered peripheral: \(advertisementData)")
        
        // TODO: We do not ever delete from this list. Is that a problem?
        if discoveredPeripherals[peripheral.identifier] == nil {
            discoveredPeripherals[peripheral.identifier] = peripheral
        }
        centralManager?.connect(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("\(#file).\(#function) discovered peripheral: \(String(describing: peripheral.name))")
        
        delegate?.btleListener(self, didConnect: peripheral)
        
        peripheral.delegate = self
        peripheral.readRSSI()
        peripheral.discoverServices([ConcreteBTLEBroadcaster.sonarServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("\(#file).\(#function) disconnected peripheral: \(String(describing: peripheral.name))")
        
        delegate?.btleListener(self, didDisconnect: peripheral, error: error)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else {
            print("\(#file).\(#function) error reading RSSI: \(error!)")
            return
        }
        print("\(#file).\(#function) didReadRSSI for peripheral: \(peripheral.identifier): \(RSSI)")

        delegate?.btleListener(self, didReadRSSI: RSSI.intValue, forPeripheral: peripheral)
        
        if delegate?.btleListener(self, shouldReadRSSIFor: peripheral) ?? false {
            Timer.scheduledTimer(withTimeInterval: rssiSamplingInterval, repeats: false) { timer in
                peripheral.readRSSI()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        print("\(#file).\(#function) got centralManager: \(central)")
        
        self.centralManager = central
    }
    
    // MARK: CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("\(#file).\(#function) peripheral \(peripheral) invalidating services:\n")
        for service in invalidatedServices {
            print("\(#file).\(#function)     \(service):\n")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            print("Error discovering services: \(error!)")
            return
        }
        
        guard let services = peripheral.services, services.count > 0 else {
            print("No services discovered for peripheral \(peripheral)")
            return
        }
        
        guard let sonarService = services.first(where: {$0.uuid == ConcreteBTLEBroadcaster.sonarServiceUUID}) else {
            print("Sonar service not discovered for peripheral \(peripheral)")
            return
        }

        print("\(#file).\(#function) found sonarService: \(sonarService)")
        peripheral.discoverCharacteristics([ConcreteBTLEBroadcaster.sonarIdCharacteristicUUID], for: sonarService)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            print("Error discovering characteristics: \(error!)")
            return
        }
        
        guard let characteristics = service.characteristics, characteristics.count > 0 else {
            print("No characteristics discovered for service \(service)")
            return
        }
        
        guard let sonarIdCharacteristic = characteristics.first(where: {$0.uuid == ConcreteBTLEBroadcaster.sonarIdCharacteristicUUID}) else {
            print("Sonar Id characteristic not discovered for peripheral \(peripheral)")
            return
        }

        print("\(#file).\(#function) found sonarIdCharacteristic: \(sonarIdCharacteristic)")
        peripheral.readValue(for: sonarIdCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Error updatingValueFor characteristic \(characteristic) : \(error!)")
            return
        }

        print("\(#file).\(#function) didUpdateValueFor characteristic: \(characteristic)")

        guard let data = characteristic.value else {
            print("\(#file).\(#function) No data found in characteristic.")
            return
        }

        guard characteristic.uuid == ConcreteBTLEBroadcaster.sonarIdCharacteristicUUID else {
            return
        }

        let sonarId = UUID(uuidString: CBUUID(data: data).uuidString)!
        delegate?.btleListener(self, didFindSonarId: sonarId, forPeripheral: peripheral)
    }

}
