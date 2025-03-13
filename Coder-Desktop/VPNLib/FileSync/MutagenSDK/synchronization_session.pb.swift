// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: synchronization_session.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

//
// This file was taken from
// https://github.com/mutagen-io/mutagen/tree/v0.18.1/pkg/synchronization/session.proto
//
// MIT License
// 
// Copyright (c) 2016-present Docker, Inc.
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

/// Session represents a synchronization session configuration and persistent
/// state. It is mutable within the context of the daemon, so it should be
/// accessed and modified in a synchronized fashion. Outside of the daemon (e.g.
/// when returned via the API), it should be considered immutable.
struct Synchronization_Session: @unchecked Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Identifier is the (unique) session identifier. It is static. It cannot be
  /// empty.
  var identifier: String {
    get {return _storage._identifier}
    set {_uniqueStorage()._identifier = newValue}
  }

  /// Version is the session version. It is static.
  var version: Synchronization_Version {
    get {return _storage._version}
    set {_uniqueStorage()._version = newValue}
  }

  /// CreationTime is the creation time of the session. It is static. It cannot
  /// be nil.
  var creationTime: SwiftProtobuf.Google_Protobuf_Timestamp {
    get {return _storage._creationTime ?? SwiftProtobuf.Google_Protobuf_Timestamp()}
    set {_uniqueStorage()._creationTime = newValue}
  }
  /// Returns true if `creationTime` has been explicitly set.
  var hasCreationTime: Bool {return _storage._creationTime != nil}
  /// Clears the value of `creationTime`. Subsequent reads from it will return its default value.
  mutating func clearCreationTime() {_uniqueStorage()._creationTime = nil}

  /// CreatingVersionMajor is the major version component of the version of
  /// Mutagen which created the session. It is static.
  var creatingVersionMajor: UInt32 {
    get {return _storage._creatingVersionMajor}
    set {_uniqueStorage()._creatingVersionMajor = newValue}
  }

  /// CreatingVersionMinor is the minor version component of the version of
  /// Mutagen which created the session. It is static.
  var creatingVersionMinor: UInt32 {
    get {return _storage._creatingVersionMinor}
    set {_uniqueStorage()._creatingVersionMinor = newValue}
  }

  /// CreatingVersionPatch is the patch version component of the version of
  /// Mutagen which created the session. It is static.
  var creatingVersionPatch: UInt32 {
    get {return _storage._creatingVersionPatch}
    set {_uniqueStorage()._creatingVersionPatch = newValue}
  }

  /// Alpha is the alpha endpoint URL. It is static. It cannot be nil.
  var alpha: Url_URL {
    get {return _storage._alpha ?? Url_URL()}
    set {_uniqueStorage()._alpha = newValue}
  }
  /// Returns true if `alpha` has been explicitly set.
  var hasAlpha: Bool {return _storage._alpha != nil}
  /// Clears the value of `alpha`. Subsequent reads from it will return its default value.
  mutating func clearAlpha() {_uniqueStorage()._alpha = nil}

  /// Beta is the beta endpoint URL. It is static. It cannot be nil.
  var beta: Url_URL {
    get {return _storage._beta ?? Url_URL()}
    set {_uniqueStorage()._beta = newValue}
  }
  /// Returns true if `beta` has been explicitly set.
  var hasBeta: Bool {return _storage._beta != nil}
  /// Clears the value of `beta`. Subsequent reads from it will return its default value.
  mutating func clearBeta() {_uniqueStorage()._beta = nil}

  /// Configuration is the flattened session configuration. It is static. It
  /// cannot be nil.
  var configuration: Synchronization_Configuration {
    get {return _storage._configuration ?? Synchronization_Configuration()}
    set {_uniqueStorage()._configuration = newValue}
  }
  /// Returns true if `configuration` has been explicitly set.
  var hasConfiguration: Bool {return _storage._configuration != nil}
  /// Clears the value of `configuration`. Subsequent reads from it will return its default value.
  mutating func clearConfiguration() {_uniqueStorage()._configuration = nil}

  /// ConfigurationAlpha are the alpha-specific session configuration
  /// overrides. It is static. It may be nil for existing sessions loaded from
  /// disk, but it is not considered valid unless non-nil, so it should be
  /// replaced with an empty default value in-memory if a nil on-disk value is
  /// detected.
  var configurationAlpha: Synchronization_Configuration {
    get {return _storage._configurationAlpha ?? Synchronization_Configuration()}
    set {_uniqueStorage()._configurationAlpha = newValue}
  }
  /// Returns true if `configurationAlpha` has been explicitly set.
  var hasConfigurationAlpha: Bool {return _storage._configurationAlpha != nil}
  /// Clears the value of `configurationAlpha`. Subsequent reads from it will return its default value.
  mutating func clearConfigurationAlpha() {_uniqueStorage()._configurationAlpha = nil}

  /// ConfigurationBeta are the beta-specific session configuration overrides.
  /// It is static. It may be nil for existing sessions loaded from disk, but
  /// it is not considered valid unless non-nil, so it should be replaced with
  /// an empty default value in-memory if a nil on-disk value is detected.
  var configurationBeta: Synchronization_Configuration {
    get {return _storage._configurationBeta ?? Synchronization_Configuration()}
    set {_uniqueStorage()._configurationBeta = newValue}
  }
  /// Returns true if `configurationBeta` has been explicitly set.
  var hasConfigurationBeta: Bool {return _storage._configurationBeta != nil}
  /// Clears the value of `configurationBeta`. Subsequent reads from it will return its default value.
  mutating func clearConfigurationBeta() {_uniqueStorage()._configurationBeta = nil}

  /// Name is a user-friendly name for the session. It may be empty and is not
  /// guaranteed to be unique across all sessions. It is only used as a simpler
  /// handle for specifying sessions. It is static.
  var name: String {
    get {return _storage._name}
    set {_uniqueStorage()._name = newValue}
  }

  /// Labels are the session labels. They are static.
  var labels: Dictionary<String,String> {
    get {return _storage._labels}
    set {_uniqueStorage()._labels = newValue}
  }

  /// Paused indicates whether or not the session is marked as paused.
  var paused: Bool {
    get {return _storage._paused}
    set {_uniqueStorage()._paused = newValue}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "synchronization"

extension Synchronization_Session: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Session"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "identifier"),
    2: .same(proto: "version"),
    3: .same(proto: "creationTime"),
    4: .same(proto: "creatingVersionMajor"),
    5: .same(proto: "creatingVersionMinor"),
    6: .same(proto: "creatingVersionPatch"),
    7: .same(proto: "alpha"),
    8: .same(proto: "beta"),
    9: .same(proto: "configuration"),
    11: .same(proto: "configurationAlpha"),
    12: .same(proto: "configurationBeta"),
    14: .same(proto: "name"),
    13: .same(proto: "labels"),
    10: .same(proto: "paused"),
  ]

  fileprivate class _StorageClass {
    var _identifier: String = String()
    var _version: Synchronization_Version = .invalid
    var _creationTime: SwiftProtobuf.Google_Protobuf_Timestamp? = nil
    var _creatingVersionMajor: UInt32 = 0
    var _creatingVersionMinor: UInt32 = 0
    var _creatingVersionPatch: UInt32 = 0
    var _alpha: Url_URL? = nil
    var _beta: Url_URL? = nil
    var _configuration: Synchronization_Configuration? = nil
    var _configurationAlpha: Synchronization_Configuration? = nil
    var _configurationBeta: Synchronization_Configuration? = nil
    var _name: String = String()
    var _labels: Dictionary<String,String> = [:]
    var _paused: Bool = false

    #if swift(>=5.10)
      // This property is used as the initial default value for new instances of the type.
      // The type itself is protecting the reference to its storage via CoW semantics.
      // This will force a copy to be made of this reference when the first mutation occurs;
      // hence, it is safe to mark this as `nonisolated(unsafe)`.
      static nonisolated(unsafe) let defaultInstance = _StorageClass()
    #else
      static let defaultInstance = _StorageClass()
    #endif

    private init() {}

    init(copying source: _StorageClass) {
      _identifier = source._identifier
      _version = source._version
      _creationTime = source._creationTime
      _creatingVersionMajor = source._creatingVersionMajor
      _creatingVersionMinor = source._creatingVersionMinor
      _creatingVersionPatch = source._creatingVersionPatch
      _alpha = source._alpha
      _beta = source._beta
      _configuration = source._configuration
      _configurationAlpha = source._configurationAlpha
      _configurationBeta = source._configurationBeta
      _name = source._name
      _labels = source._labels
      _paused = source._paused
    }
  }

  fileprivate mutating func _uniqueStorage() -> _StorageClass {
    if !isKnownUniquelyReferenced(&_storage) {
      _storage = _StorageClass(copying: _storage)
    }
    return _storage
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    _ = _uniqueStorage()
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      while let fieldNumber = try decoder.nextFieldNumber() {
        // The use of inline closures is to circumvent an issue where the compiler
        // allocates stack space for every case branch when no optimizations are
        // enabled. https://github.com/apple/swift-protobuf/issues/1034
        switch fieldNumber {
        case 1: try { try decoder.decodeSingularStringField(value: &_storage._identifier) }()
        case 2: try { try decoder.decodeSingularEnumField(value: &_storage._version) }()
        case 3: try { try decoder.decodeSingularMessageField(value: &_storage._creationTime) }()
        case 4: try { try decoder.decodeSingularUInt32Field(value: &_storage._creatingVersionMajor) }()
        case 5: try { try decoder.decodeSingularUInt32Field(value: &_storage._creatingVersionMinor) }()
        case 6: try { try decoder.decodeSingularUInt32Field(value: &_storage._creatingVersionPatch) }()
        case 7: try { try decoder.decodeSingularMessageField(value: &_storage._alpha) }()
        case 8: try { try decoder.decodeSingularMessageField(value: &_storage._beta) }()
        case 9: try { try decoder.decodeSingularMessageField(value: &_storage._configuration) }()
        case 10: try { try decoder.decodeSingularBoolField(value: &_storage._paused) }()
        case 11: try { try decoder.decodeSingularMessageField(value: &_storage._configurationAlpha) }()
        case 12: try { try decoder.decodeSingularMessageField(value: &_storage._configurationBeta) }()
        case 13: try { try decoder.decodeMapField(fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString,SwiftProtobuf.ProtobufString>.self, value: &_storage._labels) }()
        case 14: try { try decoder.decodeSingularStringField(value: &_storage._name) }()
        default: break
        }
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every if/case branch local when no optimizations
      // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
      // https://github.com/apple/swift-protobuf/issues/1182
      if !_storage._identifier.isEmpty {
        try visitor.visitSingularStringField(value: _storage._identifier, fieldNumber: 1)
      }
      if _storage._version != .invalid {
        try visitor.visitSingularEnumField(value: _storage._version, fieldNumber: 2)
      }
      try { if let v = _storage._creationTime {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
      } }()
      if _storage._creatingVersionMajor != 0 {
        try visitor.visitSingularUInt32Field(value: _storage._creatingVersionMajor, fieldNumber: 4)
      }
      if _storage._creatingVersionMinor != 0 {
        try visitor.visitSingularUInt32Field(value: _storage._creatingVersionMinor, fieldNumber: 5)
      }
      if _storage._creatingVersionPatch != 0 {
        try visitor.visitSingularUInt32Field(value: _storage._creatingVersionPatch, fieldNumber: 6)
      }
      try { if let v = _storage._alpha {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
      } }()
      try { if let v = _storage._beta {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 8)
      } }()
      try { if let v = _storage._configuration {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 9)
      } }()
      if _storage._paused != false {
        try visitor.visitSingularBoolField(value: _storage._paused, fieldNumber: 10)
      }
      try { if let v = _storage._configurationAlpha {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 11)
      } }()
      try { if let v = _storage._configurationBeta {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 12)
      } }()
      if !_storage._labels.isEmpty {
        try visitor.visitMapField(fieldType: SwiftProtobuf._ProtobufMap<SwiftProtobuf.ProtobufString,SwiftProtobuf.ProtobufString>.self, value: _storage._labels, fieldNumber: 13)
      }
      if !_storage._name.isEmpty {
        try visitor.visitSingularStringField(value: _storage._name, fieldNumber: 14)
      }
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Synchronization_Session, rhs: Synchronization_Session) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._identifier != rhs_storage._identifier {return false}
        if _storage._version != rhs_storage._version {return false}
        if _storage._creationTime != rhs_storage._creationTime {return false}
        if _storage._creatingVersionMajor != rhs_storage._creatingVersionMajor {return false}
        if _storage._creatingVersionMinor != rhs_storage._creatingVersionMinor {return false}
        if _storage._creatingVersionPatch != rhs_storage._creatingVersionPatch {return false}
        if _storage._alpha != rhs_storage._alpha {return false}
        if _storage._beta != rhs_storage._beta {return false}
        if _storage._configuration != rhs_storage._configuration {return false}
        if _storage._configurationAlpha != rhs_storage._configurationAlpha {return false}
        if _storage._configurationBeta != rhs_storage._configurationBeta {return false}
        if _storage._name != rhs_storage._name {return false}
        if _storage._labels != rhs_storage._labels {return false}
        if _storage._paused != rhs_storage._paused {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
