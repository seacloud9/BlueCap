//
//  MutableCharacteristic.swift
//  BlueCap
//
//  Created by Troy Stribling on 8/9/14.
//  Copyright (c) 2014 Troy Stribling. The MIT License (MIT).
//

import Foundation
import CoreBluetooth

// MARK: - MutableCharacteristic -
public class MutableCharacteristic : NSObject {

    // MARK: Properties
    static let ioQueue = Queue("us.gnos.blueCap.mutable-characteristic.io")

    private let profile: CharacteristicProfile

    private var centrals = SerialIODictionary<NSUUID, CBCentralInjectable>(MutableCharacteristic.ioQueue)

    private var _queuedUpdates = [NSData]()
    private var _isUpdating = false

    internal var _processWriteRequestPromise: StreamPromise<(request: CBATTRequestInjectable, central: CBCentralInjectable)>?
    internal weak var _service: MutableService?
    
    internal let cbMutableChracteristic: CBMutableCharacteristicInjectable
    public var value: NSData?

    private var queuedUpdates: [NSData] {
        get {
            return MutableCharacteristic.ioQueue.sync { return self._queuedUpdates }
        }
        set {
            MutableCharacteristic.ioQueue.sync { self._queuedUpdates = newValue }
        }
    }

    private var processWriteRequestPromise: StreamPromise<(request: CBATTRequestInjectable, central: CBCentralInjectable)>? {
        get {
            return MutableCharacteristic.ioQueue.sync { return self._processWriteRequestPromise }
        }
        set {
            MutableCharacteristic.ioQueue.sync { self._processWriteRequestPromise = newValue }
        }
    }

    public private(set) var isUpdating: Bool {
        get {
            return MutableCharacteristic.ioQueue.sync { return self._isUpdating }
        }
        set {
            MutableCharacteristic.ioQueue.sync { self._isUpdating = newValue }
        }
    }

    public var UUID: CBUUID {
        return self.profile.UUID
    }
    
    public var name: String {
        return self.profile.name
    }
    
    public var stringValues: [String] {
        return self.profile.stringValues
    }
    
    public var permissions: CBAttributePermissions {
        return self.cbMutableChracteristic.permissions
    }
    
    public var properties: CBCharacteristicProperties {
        return self.cbMutableChracteristic.properties
    }

    public var subscribers: [CBCentralInjectable] {
        return Array(self.centrals.values)
    }

    public var pendingUpdates : [NSData] {
        return Array(self.queuedUpdates)
    }

    public var service: MutableService? {
        return self._service
    }

    public var stringValue: [String:String]? {
        if let value = self.value {
            return self.profile.stringValue(value)
        } else {
            return nil
        }
    }

    public var canNotify : Bool {
        return self.propertyEnabled(.Notify)                    ||
               self.propertyEnabled(.Indicate)                  ||
               self.propertyEnabled(.NotifyEncryptionRequired)  ||
               self.propertyEnabled(.IndicateEncryptionRequired)
    }

    // MARK: Initializers
    public convenience init(profile: CharacteristicProfile) {
        let cbMutableChracteristic = CBMutableCharacteristic(type: profile.UUID, properties: profile.properties, value: nil, permissions: profile.permissions)
        self.init(cbMutableCharacteristic: cbMutableChracteristic, profile: profile)
    }

    internal init(cbMutableCharacteristic: CBMutableCharacteristicInjectable, profile: CharacteristicProfile) {
        self.profile = profile
        self.value = profile.initialValue
        self.cbMutableChracteristic = cbMutableCharacteristic
    }

    internal init(cbMutableCharacteristic: CBMutableCharacteristicInjectable) {
        self.profile = CharacteristicProfile(UUID: cbMutableCharacteristic.UUID.UUIDString)
        self.value = profile.initialValue
        self.cbMutableChracteristic = cbMutableCharacteristic
    }

    public init(UUID: String, properties: CBCharacteristicProperties, permissions: CBAttributePermissions, value: NSData?) {
        self.profile = CharacteristicProfile(UUID: UUID)
        self.value = value
        self.cbMutableChracteristic = CBMutableCharacteristic(type:self.profile.UUID, properties:properties, value:nil, permissions:permissions)
    }

    public convenience init(UUID: String) {
        self.init(profile: CharacteristicProfile(UUID: UUID))
    }

    public class func withProfiles(profiles: [CharacteristicProfile]) -> [MutableCharacteristic] {
        return profiles.map{ MutableCharacteristic(profile: $0) }
    }

    public class func withProfiles(profiles: [CharacteristicProfile], cbCharacteristics: [CBMutableCharacteristic]) -> [MutableCharacteristic] {
        return profiles.map{ MutableCharacteristic(profile: $0) }
    }

    // MARK: Properties & Permissions
    public func propertyEnabled(property:CBCharacteristicProperties) -> Bool {
        return (self.properties.rawValue & property.rawValue) > 0
    }
    
    public func permissionEnabled(permission:CBAttributePermissions) -> Bool {
        return (self.permissions.rawValue & permission.rawValue) > 0
    }

    // MARK: Data
    public func dataFromStringValue(stringValue: [String:String]) -> NSData? {
        return self.profile.dataFromStringValue(stringValue)
    }

    // MARK: Manage Writes
    public func startRespondingToWriteRequests(capacity: Int? = nil) -> FutureStream<(request: CBATTRequestInjectable, central: CBCentralInjectable)> {
        self.processWriteRequestPromise = StreamPromise<(request: CBATTRequestInjectable, central: CBCentralInjectable)>(capacity:capacity)
        return self.processWriteRequestPromise!.future
    }
    
    public func stopRespondingToWriteRequests() {
        self.processWriteRequestPromise = nil
    }
    
    public func respondToRequest(request: CBATTRequestInjectable, withResult result: CBATTError) {
        self.service?.peripheralManager?.respondToRequest(request, withResult:result)
    }

    internal func didRespondToWriteRequest(request: CBATTRequestInjectable, central: CBCentralInjectable) -> Bool  {
        guard let processWriteRequestPromise = self.processWriteRequestPromise else {
            return false
        }
        processWriteRequestPromise.success((request, central))
        return true
    }

    // MARK: Manage Notification Updates
    public func updateValueWithString(value: [String:String]) -> Bool {
        guard let data = self.profile.dataFromStringValue(value) else {
            return false
        }
        return self.updateValueWithData(data)
    }

    public func updateValueWithData(value: NSData) -> Bool  {
        return self.updateValuesWithData([value])
    }

    public func updateValue<T: Deserializable>(value: T) -> Bool {
        return self.updateValueWithData(SerDe.serialize(value))
    }

    public func updateValue<T: RawDeserializable>(value: T) -> Bool  {
        return self.updateValueWithData(SerDe.serialize(value))
    }

    public func updateValue<T: RawArrayDeserializable>(value: T) -> Bool  {
        return self.updateValueWithData(SerDe.serialize(value))
    }

    public func updateValue<T: RawPairDeserializable>(value: T) -> Bool  {
        return self.updateValueWithData(SerDe.serialize(value))
    }

    public func updateValue<T: RawArrayPairDeserializable>(value: T) -> Bool  {
        return self.updateValueWithData(SerDe.serialize(value))
    }

    // MARK: CBPeripheralManagerDelegate Shims
    internal func peripheralManagerIsReadyToUpdateSubscribers() {
        self.isUpdating = true
        self.updateValuesWithData(self.queuedUpdates)
        self.queuedUpdates.removeAll()
    }

    internal func didSubscribeToCharacteristic(central: CBCentralInjectable) {
        self.isUpdating = true
        self.centrals[central.identifier] = central
        self.updateValuesWithData(self.queuedUpdates)
        self.queuedUpdates.removeAll()
    }

    internal func didUnsubscribeFromCharacteristic(central: CBCentralInjectable) {
        self.centrals.removeValueForKey(central.identifier)
        if self.centrals.keys.count == 0 {
            self.isUpdating = false
        }
    }

    // MARK: Utils
    private func updateValuesWithData(values: [NSData]) -> Bool  {
        guard let value = values.last else {
            return self.isUpdating
        }
        self.value = value
        if let peripheralManager = self.service?.peripheralManager where self.isUpdating && self.canNotify {
            for value in values {
                self.isUpdating = peripheralManager.updateValue(value, forCharacteristic:self)
                if !self.isUpdating {
                    self.queuedUpdates.append(value)
                }
            }
        } else {
            self.isUpdating = false
            self.queuedUpdates.append(value)
        }
        return self.isUpdating
    }

}