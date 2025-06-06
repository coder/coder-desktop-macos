// DO NOT EDIT.
// swift-format-ignore-file
// swiftlint:disable all
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: filesystem_behavior_probe_mode.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

//
// This file was taken from
// https://github.com/coder/mutagen/tree/v0.18.3/pkg/filesystem/behavior/probe_mode.proto
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

/// ProbeMode specifies the mode for filesystem probing.
enum Behavior_ProbeMode: SwiftProtobuf.Enum, Swift.CaseIterable {
  typealias RawValue = Int

  /// ProbeMode_ProbeModeDefault represents an unspecified probe mode. It
  /// should be converted to one of the following values based on the desired
  /// default behavior.
  case `default` // = 0

  /// ProbeMode_ProbeModeProbe specifies that filesystem behavior should be
  /// determined using temporary files or, if possible, a "fast-path" mechanism
  /// (such as filesystem format detection) that provides quick but certain
  /// determination of filesystem behavior.
  case probe // = 1

  /// ProbeMode_ProbeModeAssume specifies that filesystem behavior should be
  /// assumed based on the underlying platform. This is not as accurate as
  /// ProbeMode_ProbeModeProbe.
  case assume // = 2
  case UNRECOGNIZED(Int)

  init() {
    self = .default
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .default
    case 1: self = .probe
    case 2: self = .assume
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .default: return 0
    case .probe: return 1
    case .assume: return 2
    case .UNRECOGNIZED(let i): return i
    }
  }

  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static let allCases: [Behavior_ProbeMode] = [
    .default,
    .probe,
    .assume,
  ]

}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension Behavior_ProbeMode: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "ProbeModeDefault"),
    1: .same(proto: "ProbeModeProbe"),
    2: .same(proto: "ProbeModeAssume"),
  ]
}
