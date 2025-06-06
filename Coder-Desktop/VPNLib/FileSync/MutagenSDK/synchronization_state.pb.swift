// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: synchronization_state.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

//
// This file was taken from
// https://github.com/coder/mutagen/tree/v0.18.3/pkg/synchronization/state.proto
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

/// Status encodes the status of a synchronization session.
enum Synchronization_Status: SwiftProtobuf.Enum, Swift.CaseIterable {
  typealias RawValue = Int

  /// Status_Disconnected indicates that the session is unpaused but not
  /// currently connected or connecting to either endpoint.
  case disconnected // = 0

  /// Status_HaltedOnRootEmptied indicates that the session is halted due to
  /// the root emptying safety check.
  case haltedOnRootEmptied // = 1

  /// Status_HaltedOnRootDeletion indicates that the session is halted due to
  /// the root deletion safety check.
  case haltedOnRootDeletion // = 2

  /// Status_HaltedOnRootTypeChange indicates that the session is halted due to
  /// the root type change safety check.
  case haltedOnRootTypeChange // = 3

  /// Status_ConnectingAlpha indicates that the session is attempting to
  /// connect to the alpha endpoint.
  case connectingAlpha // = 4

  /// Status_ConnectingBeta indicates that the session is attempting to connect
  /// to the beta endpoint.
  case connectingBeta // = 5

  /// Status_Watching indicates that the session is watching for filesystem
  /// changes.
  case watching // = 6

  /// Status_Scanning indicates that the session is scanning the filesystem on
  /// each endpoint.
  case scanning // = 7

  /// Status_WaitingForRescan indicates that the session is waiting to retry
  /// scanning after an error during the previous scanning operation.
  case waitingForRescan // = 8

  /// Status_Reconciling indicates that the session is performing
  /// reconciliation.
  case reconciling // = 9

  /// Status_StagingAlpha indicates that the session is staging files on alpha.
  case stagingAlpha // = 10

  /// Status_StagingBeta indicates that the session is staging files on beta.
  case stagingBeta // = 11

  /// Status_Transitioning indicates that the session is performing transition
  /// operations on each endpoint.
  case transitioning // = 12

  /// Status_Saving indicates that the session is recording synchronization
  /// history to disk.
  case saving // = 13
  case UNRECOGNIZED(Int)

  init() {
    self = .disconnected
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .disconnected
    case 1: self = .haltedOnRootEmptied
    case 2: self = .haltedOnRootDeletion
    case 3: self = .haltedOnRootTypeChange
    case 4: self = .connectingAlpha
    case 5: self = .connectingBeta
    case 6: self = .watching
    case 7: self = .scanning
    case 8: self = .waitingForRescan
    case 9: self = .reconciling
    case 10: self = .stagingAlpha
    case 11: self = .stagingBeta
    case 12: self = .transitioning
    case 13: self = .saving
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .disconnected: return 0
    case .haltedOnRootEmptied: return 1
    case .haltedOnRootDeletion: return 2
    case .haltedOnRootTypeChange: return 3
    case .connectingAlpha: return 4
    case .connectingBeta: return 5
    case .watching: return 6
    case .scanning: return 7
    case .waitingForRescan: return 8
    case .reconciling: return 9
    case .stagingAlpha: return 10
    case .stagingBeta: return 11
    case .transitioning: return 12
    case .saving: return 13
    case .UNRECOGNIZED(let i): return i
    }
  }

  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Synchronization_Status] = [
    .disconnected,
    .haltedOnRootEmptied,
    .haltedOnRootDeletion,
    .haltedOnRootTypeChange,
    .connectingAlpha,
    .connectingBeta,
    .watching,
    .scanning,
    .waitingForRescan,
    .reconciling,
    .stagingAlpha,
    .stagingBeta,
    .transitioning,
    .saving,
  ]

}

/// EndpointState encodes the current state of a synchronization endpoint. It is
/// mutable within the context of the daemon, so it should be accessed and
/// modified in a synchronized fashion. Outside of the daemon (e.g. when returned
/// via the API), it should be considered immutable.
struct Synchronization_EndpointState: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Connected indicates whether or not the controller is currently connected
  /// to the endpoint.
  var connected: Bool = false

  /// Scanned indicates whether or not at least one scan has been performed on
  /// the endpoint.
  var scanned: Bool = false

  /// Directories is the number of synchronizable directory entries contained
  /// in the last snapshot from the endpoint.
  var directories: UInt64 = 0

  /// Files is the number of synchronizable file entries contained in the last
  /// snapshot from the endpoint.
  var files: UInt64 = 0

  /// SymbolicLinks is the number of synchronizable symbolic link entries
  /// contained in the last snapshot from the endpoint.
  var symbolicLinks: UInt64 = 0

  /// TotalFileSize is the total size of all synchronizable files referenced by
  /// the last snapshot from the endpoint.
  var totalFileSize: UInt64 = 0

  /// ScanProblems is the list of non-terminal problems encountered during the
  /// last scanning operation on the endpoint. This list may be a truncated
  /// version of the full list if too many problems are encountered to report
  /// via the API, in which case ExcludedScanProblems will be non-zero.
  var scanProblems: [Core_Problem] = []

  /// ExcludedScanProblems is the number of problems that have been excluded
  /// from ScanProblems due to truncation. This value can be non-zero only if
  /// ScanProblems is non-empty.
  var excludedScanProblems: UInt64 = 0

  /// TransitionProblems is the list of non-terminal problems encountered
  /// during the last transition operation on the endpoint. This list may be a
  /// truncated version of the full list if too many problems are encountered
  /// to report via the API, in which case ExcludedTransitionProblems will be
  /// non-zero.
  var transitionProblems: [Core_Problem] = []

  /// ExcludedTransitionProblems is the number of problems that have been
  /// excluded from TransitionProblems due to truncation. This value can be
  /// non-zero only if TransitionProblems is non-empty.
  var excludedTransitionProblems: UInt64 = 0

  /// StagingProgress is the rsync staging progress. It is non-nil if and only
  /// if the endpoint is currently staging files.
  var stagingProgress: Rsync_ReceiverState {
    get {return _stagingProgress ?? Rsync_ReceiverState()}
    set {_stagingProgress = newValue}
  }
  /// Returns true if `stagingProgress` has been explicitly set.
  var hasStagingProgress: Bool {return self._stagingProgress != nil}
  /// Clears the value of `stagingProgress`. Subsequent reads from it will return its default value.
  mutating func clearStagingProgress() {self._stagingProgress = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _stagingProgress: Rsync_ReceiverState? = nil
}

/// State encodes the current state of a synchronization session. It is mutable
/// within the context of the daemon, so it should be accessed and modified in a
/// synchronized fashion. Outside of the daemon (e.g. when returned via the API),
/// it should be considered immutable.
struct Synchronization_State: @unchecked Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Session is the session metadata. If the session is paused, then the
  /// remainder of the fields in this structure should be ignored.
  var session: Synchronization_Session {
    get {return _storage._session ?? Synchronization_Session()}
    set {_uniqueStorage()._session = newValue}
  }
  /// Returns true if `session` has been explicitly set.
  var hasSession: Bool {return _storage._session != nil}
  /// Clears the value of `session`. Subsequent reads from it will return its default value.
  mutating func clearSession() {_uniqueStorage()._session = nil}

  /// Status is the session status.
  var status: Synchronization_Status {
    get {return _storage._status}
    set {_uniqueStorage()._status = newValue}
  }

  /// LastError is the last error to occur during synchronization. It is
  /// cleared after a successful synchronization cycle.
  var lastError: String {
    get {return _storage._lastError}
    set {_uniqueStorage()._lastError = newValue}
  }

  /// SuccessfulCycles is the number of successful synchronization cycles to
  /// occur since successfully connecting to the endpoints.
  var successfulCycles: UInt64 {
    get {return _storage._successfulCycles}
    set {_uniqueStorage()._successfulCycles = newValue}
  }

  /// Conflicts are the content conflicts identified during reconciliation.
  /// This list may be a truncated version of the full list if too many
  /// conflicts are encountered to report via the API, in which case
  /// ExcludedConflicts will be non-zero.
  var conflicts: [Core_Conflict] {
    get {return _storage._conflicts}
    set {_uniqueStorage()._conflicts = newValue}
  }

  /// ExcludedConflicts is the number of conflicts that have been excluded from
  /// Conflicts due to truncation. This value can be non-zero only if conflicts
  /// is non-empty.
  var excludedConflicts: UInt64 {
    get {return _storage._excludedConflicts}
    set {_uniqueStorage()._excludedConflicts = newValue}
  }

  /// AlphaState encodes the state of the alpha endpoint. It is always non-nil.
  var alphaState: Synchronization_EndpointState {
    get {return _storage._alphaState ?? Synchronization_EndpointState()}
    set {_uniqueStorage()._alphaState = newValue}
  }
  /// Returns true if `alphaState` has been explicitly set.
  var hasAlphaState: Bool {return _storage._alphaState != nil}
  /// Clears the value of `alphaState`. Subsequent reads from it will return its default value.
  mutating func clearAlphaState() {_uniqueStorage()._alphaState = nil}

  /// BetaState encodes the state of the beta endpoint. It is always non-nil.
  var betaState: Synchronization_EndpointState {
    get {return _storage._betaState ?? Synchronization_EndpointState()}
    set {_uniqueStorage()._betaState = newValue}
  }
  /// Returns true if `betaState` has been explicitly set.
  var hasBetaState: Bool {return _storage._betaState != nil}
  /// Clears the value of `betaState`. Subsequent reads from it will return its default value.
  mutating func clearBetaState() {_uniqueStorage()._betaState = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "synchronization"

extension Synchronization_Status: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "Disconnected"),
    1: .same(proto: "HaltedOnRootEmptied"),
    2: .same(proto: "HaltedOnRootDeletion"),
    3: .same(proto: "HaltedOnRootTypeChange"),
    4: .same(proto: "ConnectingAlpha"),
    5: .same(proto: "ConnectingBeta"),
    6: .same(proto: "Watching"),
    7: .same(proto: "Scanning"),
    8: .same(proto: "WaitingForRescan"),
    9: .same(proto: "Reconciling"),
    10: .same(proto: "StagingAlpha"),
    11: .same(proto: "StagingBeta"),
    12: .same(proto: "Transitioning"),
    13: .same(proto: "Saving"),
  ]
}

extension Synchronization_EndpointState: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".EndpointState"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "connected"),
    2: .same(proto: "scanned"),
    3: .same(proto: "directories"),
    4: .same(proto: "files"),
    5: .same(proto: "symbolicLinks"),
    6: .same(proto: "totalFileSize"),
    7: .same(proto: "scanProblems"),
    8: .same(proto: "excludedScanProblems"),
    9: .same(proto: "transitionProblems"),
    10: .same(proto: "excludedTransitionProblems"),
    11: .same(proto: "stagingProgress"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self.connected) }()
      case 2: try { try decoder.decodeSingularBoolField(value: &self.scanned) }()
      case 3: try { try decoder.decodeSingularUInt64Field(value: &self.directories) }()
      case 4: try { try decoder.decodeSingularUInt64Field(value: &self.files) }()
      case 5: try { try decoder.decodeSingularUInt64Field(value: &self.symbolicLinks) }()
      case 6: try { try decoder.decodeSingularUInt64Field(value: &self.totalFileSize) }()
      case 7: try { try decoder.decodeRepeatedMessageField(value: &self.scanProblems) }()
      case 8: try { try decoder.decodeSingularUInt64Field(value: &self.excludedScanProblems) }()
      case 9: try { try decoder.decodeRepeatedMessageField(value: &self.transitionProblems) }()
      case 10: try { try decoder.decodeSingularUInt64Field(value: &self.excludedTransitionProblems) }()
      case 11: try { try decoder.decodeSingularMessageField(value: &self._stagingProgress) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if self.connected != false {
      try visitor.visitSingularBoolField(value: self.connected, fieldNumber: 1)
    }
    if self.scanned != false {
      try visitor.visitSingularBoolField(value: self.scanned, fieldNumber: 2)
    }
    if self.directories != 0 {
      try visitor.visitSingularUInt64Field(value: self.directories, fieldNumber: 3)
    }
    if self.files != 0 {
      try visitor.visitSingularUInt64Field(value: self.files, fieldNumber: 4)
    }
    if self.symbolicLinks != 0 {
      try visitor.visitSingularUInt64Field(value: self.symbolicLinks, fieldNumber: 5)
    }
    if self.totalFileSize != 0 {
      try visitor.visitSingularUInt64Field(value: self.totalFileSize, fieldNumber: 6)
    }
    if !self.scanProblems.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.scanProblems, fieldNumber: 7)
    }
    if self.excludedScanProblems != 0 {
      try visitor.visitSingularUInt64Field(value: self.excludedScanProblems, fieldNumber: 8)
    }
    if !self.transitionProblems.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.transitionProblems, fieldNumber: 9)
    }
    if self.excludedTransitionProblems != 0 {
      try visitor.visitSingularUInt64Field(value: self.excludedTransitionProblems, fieldNumber: 10)
    }
    try { if let v = self._stagingProgress {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 11)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Synchronization_EndpointState, rhs: Synchronization_EndpointState) -> Bool {
    if lhs.connected != rhs.connected {return false}
    if lhs.scanned != rhs.scanned {return false}
    if lhs.directories != rhs.directories {return false}
    if lhs.files != rhs.files {return false}
    if lhs.symbolicLinks != rhs.symbolicLinks {return false}
    if lhs.totalFileSize != rhs.totalFileSize {return false}
    if lhs.scanProblems != rhs.scanProblems {return false}
    if lhs.excludedScanProblems != rhs.excludedScanProblems {return false}
    if lhs.transitionProblems != rhs.transitionProblems {return false}
    if lhs.excludedTransitionProblems != rhs.excludedTransitionProblems {return false}
    if lhs._stagingProgress != rhs._stagingProgress {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Synchronization_State: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".State"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "session"),
    2: .same(proto: "status"),
    3: .same(proto: "lastError"),
    4: .same(proto: "successfulCycles"),
    5: .same(proto: "conflicts"),
    6: .same(proto: "excludedConflicts"),
    7: .same(proto: "alphaState"),
    8: .same(proto: "betaState"),
  ]

  fileprivate class _StorageClass {
    var _session: Synchronization_Session? = nil
    var _status: Synchronization_Status = .disconnected
    var _lastError: String = String()
    var _successfulCycles: UInt64 = 0
    var _conflicts: [Core_Conflict] = []
    var _excludedConflicts: UInt64 = 0
    var _alphaState: Synchronization_EndpointState? = nil
    var _betaState: Synchronization_EndpointState? = nil

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
      _session = source._session
      _status = source._status
      _lastError = source._lastError
      _successfulCycles = source._successfulCycles
      _conflicts = source._conflicts
      _excludedConflicts = source._excludedConflicts
      _alphaState = source._alphaState
      _betaState = source._betaState
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
        case 1: try { try decoder.decodeSingularMessageField(value: &_storage._session) }()
        case 2: try { try decoder.decodeSingularEnumField(value: &_storage._status) }()
        case 3: try { try decoder.decodeSingularStringField(value: &_storage._lastError) }()
        case 4: try { try decoder.decodeSingularUInt64Field(value: &_storage._successfulCycles) }()
        case 5: try { try decoder.decodeRepeatedMessageField(value: &_storage._conflicts) }()
        case 6: try { try decoder.decodeSingularUInt64Field(value: &_storage._excludedConflicts) }()
        case 7: try { try decoder.decodeSingularMessageField(value: &_storage._alphaState) }()
        case 8: try { try decoder.decodeSingularMessageField(value: &_storage._betaState) }()
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
      try { if let v = _storage._session {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
      } }()
      if _storage._status != .disconnected {
        try visitor.visitSingularEnumField(value: _storage._status, fieldNumber: 2)
      }
      if !_storage._lastError.isEmpty {
        try visitor.visitSingularStringField(value: _storage._lastError, fieldNumber: 3)
      }
      if _storage._successfulCycles != 0 {
        try visitor.visitSingularUInt64Field(value: _storage._successfulCycles, fieldNumber: 4)
      }
      if !_storage._conflicts.isEmpty {
        try visitor.visitRepeatedMessageField(value: _storage._conflicts, fieldNumber: 5)
      }
      if _storage._excludedConflicts != 0 {
        try visitor.visitSingularUInt64Field(value: _storage._excludedConflicts, fieldNumber: 6)
      }
      try { if let v = _storage._alphaState {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
      } }()
      try { if let v = _storage._betaState {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 8)
      } }()
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Synchronization_State, rhs: Synchronization_State) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._session != rhs_storage._session {return false}
        if _storage._status != rhs_storage._status {return false}
        if _storage._lastError != rhs_storage._lastError {return false}
        if _storage._successfulCycles != rhs_storage._successfulCycles {return false}
        if _storage._conflicts != rhs_storage._conflicts {return false}
        if _storage._excludedConflicts != rhs_storage._excludedConflicts {return false}
        if _storage._alphaState != rhs_storage._alphaState {return false}
        if _storage._betaState != rhs_storage._betaState {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
