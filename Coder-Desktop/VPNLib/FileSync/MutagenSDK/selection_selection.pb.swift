// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: selection_selection.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

//
// This file was taken from
// https://github.com/mutagen-io/mutagen/tree/v0.18.1/pkg/selection/selection.proto
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

/// Selection encodes a selection mechanism that can be used to select a
/// collection of sessions. It should have exactly one member set.
struct Selection_Selection: Sendable {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// All, if true, indicates that all sessions should be selected.
  var all: Bool = false

  /// Specifications is a list of session specifications. Each element may be
  /// either a session identifier or name (or a prefix thereof). If non-empty,
  /// it indicates that these specifications should be used to select sessions.
  var specifications: [String] = []

  /// LabelSelector is a label selector specification. If present (non-empty),
  /// it indicates that this selector should be used to select sessions.
  var labelSelector: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "selection"

extension Selection_Selection: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Selection"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "all"),
    2: .same(proto: "specifications"),
    3: .same(proto: "labelSelector"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBoolField(value: &self.all) }()
      case 2: try { try decoder.decodeRepeatedStringField(value: &self.specifications) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.labelSelector) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.all != false {
      try visitor.visitSingularBoolField(value: self.all, fieldNumber: 1)
    }
    if !self.specifications.isEmpty {
      try visitor.visitRepeatedStringField(value: self.specifications, fieldNumber: 2)
    }
    if !self.labelSelector.isEmpty {
      try visitor.visitSingularStringField(value: self.labelSelector, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Selection_Selection, rhs: Selection_Selection) -> Bool {
    if lhs.all != rhs.all {return false}
    if lhs.specifications != rhs.specifications {return false}
    if lhs.labelSelector != rhs.labelSelector {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
