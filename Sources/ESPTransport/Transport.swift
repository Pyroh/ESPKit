// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Canal d'octets vers une puce. ESPKit fournit `SerialPort` ; on peut implémenter
/// ce protocole pour un autre lien (réseau, tests).
public protocol Transport: Sendable {
    func open() async throws
    func close() async
    func write(_ data: Data) async throws
    /// Rend au plus `maxCount` octets dès qu'il y en a, ou des données vides à l'expiration du délai.
    func read(maxCount: Int, timeout: Duration) async throws -> Data
    func discardInput() async throws
    func setBaudRate(_ rate: Int) async throws
    /// Change DTR et/ou RTS **en un seul appel système** quand les deux sont donnés.
    func setControlLines(dtr: Bool?, rts: Bool?) async throws
    /// Identité USB du port, si elle est connue (choix du reset automatique).
    var usbIdentity: USBIdentity? { get }
}

/// Identité USB d'un port série.
public struct USBIdentity: Hashable, Sendable {
    public var vendorID: UInt16
    public var productID: UInt16
    public var serialNumber: String?
    public var manufacturer: String?
    public var product: String?

    public init(vendorID: UInt16, productID: UInt16, serialNumber: String? = nil,
                manufacturer: String? = nil, product: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.manufacturer = manufacturer
        self.product = product
    }

    /// Identifiant USB d'Espressif.
    public static let espressifVendorID: UInt16 = 0x303A
    /// Produit du périphérique USB-Serial-JTAG intégré.
    public static let usbSerialJTAGProductID: UInt16 = 0x1001

    /// Vrai pour le périphérique USB-Serial-JTAG intégré d'Espressif (303A:1001).
    public var isEspressifUSBSerialJTAG: Bool {
        vendorID == Self.espressifVendorID && productID == Self.usbSerialJTAGProductID
    }
}

/// Erreurs du transport série.
public enum TransportError: ESPKitError, Equatable {
    case openFailed(path: String, errno: Int32)
    case portBusy(path: String)
    case ioFailed(errno: Int32)
    case unsupportedBaudRate(Int)
    /// Le port a disparu : câble retiré, ou ré-énumération USB-Serial-JTAG après un reset.
    case deviceRemoved
    case closed

    public var description: String {
        switch self {
        case .openFailed(let path, let code): "Impossible d'ouvrir \(path) : \(String(cString: strerror(code)))"
        case .portBusy(let path): "Le port \(path) est déjà utilisé par un autre programme"
        case .ioFailed(let code): "Erreur d'entrée-sortie sur le port série : \(String(cString: strerror(code)))"
        case .unsupportedBaudRate(let rate): "Débit non pris en charge par le port : \(rate) bauds"
        case .deviceRemoved: "Le port série a disparu (câble retiré ou périphérique USB ré-énuméré)"
        case .closed: "Le port série est fermé"
        }
    }
}
