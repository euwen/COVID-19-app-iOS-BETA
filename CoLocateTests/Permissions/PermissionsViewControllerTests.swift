//
//  PermissionsViewControllerTests.swift
//  CoLocateTests
//
//  Created by NHSX.
//  Copyright © 2020 NHSX. All rights reserved.
//

import CoreBluetooth
import XCTest
@testable import CoLocate

class PermissionsViewControllerTests: TestCase {

    func testPermissionsFlow() {
        let authManagerDouble = AuthorizationManagerDouble()
        let pushNotificationManagerDouble = PushNotificationManagerDouble()
        let persistence = PersistenceDouble()
        let vc = PermissionsViewController.instantiate()
        vc.authManager = authManagerDouble
        vc.pushNotificationManager = pushNotificationManagerDouble
        vc.persistence = persistence
        vc.uiQueue = QueueDouble()

        let permissionsUnwinder = PermissionsUnwinder()
        rootViewController.viewControllers = [permissionsUnwinder]
        permissionsUnwinder.present(vc, animated: false)

        vc.didTapContinue(UIButton())
        
        #if targetEnvironment(simulator)
        // We skip Bluetooth on the simulator and jump straight
        // to requesting notification authorization.
        #else
        authManagerDouble._bluetooth = .allowed
        vc.peripheralManagerDidUpdateState(CBPeripheralManager())
        #endif

        XCTAssertNotNil(pushNotificationManagerDouble.requestAuthorizationCompletion)
        pushNotificationManagerDouble.requestAuthorizationCompletion?(.success(true))

        XCTAssert(permissionsUnwinder.didUnwindFromPermissions)
    }

}

private class BTLEBroadcasterDouble: BTLEBroadcaster {
    var delegate: BTLEBroadcasterStateDelegate?
    
    func start(stateDelegate: BTLEBroadcasterStateDelegate?) {
        delegate = stateDelegate
    }
    
    func setSonarUUID(_ uuid: UUID) {
    }
}

private class BTLEListenerDouble: BTLEListener {
    var stateDelegate: BTLEListenerStateDelegate?
    var delegate: BTLEListenerDelegate?
    
    func start(stateDelegate: BTLEListenerStateDelegate?, delegate: BTLEListenerDelegate?) {
        self.stateDelegate = stateDelegate
    }
}

class PermissionsUnwinder: UIViewController {
    var didUnwindFromPermissions = false
    @IBAction func unwindFromPermissions(unwindSegue: UIStoryboardSegue) {
        didUnwindFromPermissions = true
    }
}
