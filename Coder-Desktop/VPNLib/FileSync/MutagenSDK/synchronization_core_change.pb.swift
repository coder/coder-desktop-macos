// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: synchronization_core_change.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

//
// This file was taken from
// https://github.com/mutagen-io/mutagen/tree/v0.18.1/pkg/synchronization/core/change.proto
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

/// Change encodes a change to an entry hierarchy. Change objects should be
/// considered immutable and must not be modified.
struct Core_Change: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Path is the path of the root of the change (relative to the
  /// synchronization root).
  var path: String = String()

  /// Old represents the old filesystem hierarchy at the change path. It may be
  /// nil if no content previously existed.
  var old: Core_Entry {
    get {return _old ?? Core_Entry()}
    set {_old = newValue}
  }
  /// Returns true if `old` has been explicitly set.
  var hasOld: Bool {return self._old != nil}
  /// Clears the value of `old`. Subsequent reads from it will return its default value.
  mutating func clearOld() {self._old = nil}

  /// New represents the new filesystem hierarchy at the change path. It may be
  /// nil if content has been deleted.
  var new: Core_Entry {
    get {return _new ?? Core_Entry()}
    set {_new = newValue}
  }
  /// Returns true if `new` has been explicitly set.
  var hasNew: Bool {return self._new != nil}
  /// Clears the value of `new`. Subsequent reads from it will return its default value.
  mutating func clearNew() {self._new = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _old: Core_Entry? = nil
  fileprivate var _new: Core_Entry? = nil
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "core"

extension Core_Change: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Change"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "path"),
    2: .same(proto: "old"),
    3: .same(proto: "new"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.path) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._old) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._new) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if !self.path.isEmpty {
      try visitor.visitSingularStringField(value: self.path, fieldNumber: 1)
    }
    try { if let v = self._old {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._new {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Core_Change, rhs: Core_Change) -> Bool {
    if lhs.path != rhs.path {return false}
    if lhs._old != rhs._old {return false}
    if lhs._new != rhs._new {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
