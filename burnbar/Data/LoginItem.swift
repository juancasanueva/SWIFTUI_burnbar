//
//  LoginItem.swift
//  burnbar
//
//  The app's login item, behind a protocol so tests and inert runs never touch the real one.
//

import ServiceManagement

/// Whether the app opens at login.
nonisolated enum LoginItemStatus: Hashable, Sendable {
    case enabled
    case disabled
    /// Registered, but the user still has to allow it in System Settings.
    case requiresApproval
}

protocol LoginItemControlling: AnyObject {
    var status: LoginItemStatus { get }
    /// Registers (true) or unregisters (false) the login item.
    func setEnabled(_ isEnabled: Bool) throws
}

/// The real login item: `SMAppService.mainApp`.
final class SystemLoginItem: LoginItemControlling {
    private let service = SMAppService.mainApp

    var status: LoginItemStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}

/// A login item that only remembers its state, for inert runs (tests, UI tests).
final class InMemoryLoginItem: LoginItemControlling {
    private(set) var status: LoginItemStatus

    init(isEnabled: Bool) { status = isEnabled ? .enabled : .disabled }

    func setEnabled(_ isEnabled: Bool) throws { status = isEnabled ? .enabled : .disabled }
}
