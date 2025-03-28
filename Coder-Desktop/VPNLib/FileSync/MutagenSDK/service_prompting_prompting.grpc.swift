//
// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the protocol buffer compiler.
// Source: service_prompting_prompting.proto
//
import GRPC
import NIO
import NIOConcurrencyHelpers
import SwiftProtobuf


/// Prompting allows clients to host and request prompting.
///
/// Usage: instantiate `Prompting_PromptingClient`, then call methods of this protocol to make API calls.
internal protocol Prompting_PromptingClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Prompting_PromptingClientInterceptorFactoryProtocol? { get }

  func host(
    callOptions: CallOptions?,
    handler: @escaping (Prompting_HostResponse) -> Void
  ) -> BidirectionalStreamingCall<Prompting_HostRequest, Prompting_HostResponse>

  func prompt(
    _ request: Prompting_PromptRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Prompting_PromptRequest, Prompting_PromptResponse>
}

extension Prompting_PromptingClientProtocol {
  internal var serviceName: String {
    return "prompting.Prompting"
  }

  /// Host allows clients to perform prompt hosting.
  ///
  /// Callers should use the `send` method on the returned object to send messages
  /// to the server. The caller should send an `.end` after the final message has been sent.
  ///
  /// - Parameters:
  ///   - callOptions: Call options.
  ///   - handler: A closure called when each response is received from the server.
  /// - Returns: A `ClientStreamingCall` with futures for the metadata and status.
  internal func host(
    callOptions: CallOptions? = nil,
    handler: @escaping (Prompting_HostResponse) -> Void
  ) -> BidirectionalStreamingCall<Prompting_HostRequest, Prompting_HostResponse> {
    return self.makeBidirectionalStreamingCall(
      path: Prompting_PromptingClientMetadata.Methods.host.path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeHostInterceptors() ?? [],
      handler: handler
    )
  }

  /// Prompt performs prompting using a specific prompter.
  ///
  /// - Parameters:
  ///   - request: Request to send to Prompt.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  internal func prompt(
    _ request: Prompting_PromptRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Prompting_PromptRequest, Prompting_PromptResponse> {
    return self.makeUnaryCall(
      path: Prompting_PromptingClientMetadata.Methods.prompt.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makePromptInterceptors() ?? []
    )
  }
}

@available(*, deprecated)
extension Prompting_PromptingClient: @unchecked Sendable {}

@available(*, deprecated, renamed: "Prompting_PromptingNIOClient")
internal final class Prompting_PromptingClient: Prompting_PromptingClientProtocol {
  private let lock = Lock()
  private var _defaultCallOptions: CallOptions
  private var _interceptors: Prompting_PromptingClientInterceptorFactoryProtocol?
  internal let channel: GRPCChannel
  internal var defaultCallOptions: CallOptions {
    get { self.lock.withLock { return self._defaultCallOptions } }
    set { self.lock.withLockVoid { self._defaultCallOptions = newValue } }
  }
  internal var interceptors: Prompting_PromptingClientInterceptorFactoryProtocol? {
    get { self.lock.withLock { return self._interceptors } }
    set { self.lock.withLockVoid { self._interceptors = newValue } }
  }

  /// Creates a client for the prompting.Prompting service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  internal init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Prompting_PromptingClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self._defaultCallOptions = defaultCallOptions
    self._interceptors = interceptors
  }
}

internal struct Prompting_PromptingNIOClient: Prompting_PromptingClientProtocol {
  internal var channel: GRPCChannel
  internal var defaultCallOptions: CallOptions
  internal var interceptors: Prompting_PromptingClientInterceptorFactoryProtocol?

  /// Creates a client for the prompting.Prompting service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  internal init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Prompting_PromptingClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

/// Prompting allows clients to host and request prompting.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal protocol Prompting_PromptingAsyncClientProtocol: GRPCClient {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Prompting_PromptingClientInterceptorFactoryProtocol? { get }

  func makeHostCall(
    callOptions: CallOptions?
  ) -> GRPCAsyncBidirectionalStreamingCall<Prompting_HostRequest, Prompting_HostResponse>

  func makePromptCall(
    _ request: Prompting_PromptRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Prompting_PromptRequest, Prompting_PromptResponse>
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Prompting_PromptingAsyncClientProtocol {
  internal static var serviceDescriptor: GRPCServiceDescriptor {
    return Prompting_PromptingClientMetadata.serviceDescriptor
  }

  internal var interceptors: Prompting_PromptingClientInterceptorFactoryProtocol? {
    return nil
  }

  internal func makeHostCall(
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncBidirectionalStreamingCall<Prompting_HostRequest, Prompting_HostResponse> {
    return self.makeAsyncBidirectionalStreamingCall(
      path: Prompting_PromptingClientMetadata.Methods.host.path,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeHostInterceptors() ?? []
    )
  }

  internal func makePromptCall(
    _ request: Prompting_PromptRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Prompting_PromptRequest, Prompting_PromptResponse> {
    return self.makeAsyncUnaryCall(
      path: Prompting_PromptingClientMetadata.Methods.prompt.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makePromptInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Prompting_PromptingAsyncClientProtocol {
  internal func host<RequestStream>(
    _ requests: RequestStream,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncResponseStream<Prompting_HostResponse> where RequestStream: Sequence, RequestStream.Element == Prompting_HostRequest {
    return self.performAsyncBidirectionalStreamingCall(
      path: Prompting_PromptingClientMetadata.Methods.host.path,
      requests: requests,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeHostInterceptors() ?? []
    )
  }

  internal func host<RequestStream>(
    _ requests: RequestStream,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncResponseStream<Prompting_HostResponse> where RequestStream: AsyncSequence & Sendable, RequestStream.Element == Prompting_HostRequest {
    return self.performAsyncBidirectionalStreamingCall(
      path: Prompting_PromptingClientMetadata.Methods.host.path,
      requests: requests,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeHostInterceptors() ?? []
    )
  }

  internal func prompt(
    _ request: Prompting_PromptRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Prompting_PromptResponse {
    return try await self.performAsyncUnaryCall(
      path: Prompting_PromptingClientMetadata.Methods.prompt.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makePromptInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal struct Prompting_PromptingAsyncClient: Prompting_PromptingAsyncClientProtocol {
  internal var channel: GRPCChannel
  internal var defaultCallOptions: CallOptions
  internal var interceptors: Prompting_PromptingClientInterceptorFactoryProtocol?

  internal init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Prompting_PromptingClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

internal protocol Prompting_PromptingClientInterceptorFactoryProtocol: Sendable {

  /// - Returns: Interceptors to use when invoking 'host'.
  func makeHostInterceptors() -> [ClientInterceptor<Prompting_HostRequest, Prompting_HostResponse>]

  /// - Returns: Interceptors to use when invoking 'prompt'.
  func makePromptInterceptors() -> [ClientInterceptor<Prompting_PromptRequest, Prompting_PromptResponse>]
}

internal enum Prompting_PromptingClientMetadata {
  internal static let serviceDescriptor = GRPCServiceDescriptor(
    name: "Prompting",
    fullName: "prompting.Prompting",
    methods: [
      Prompting_PromptingClientMetadata.Methods.host,
      Prompting_PromptingClientMetadata.Methods.prompt,
    ]
  )

  internal enum Methods {
    internal static let host = GRPCMethodDescriptor(
      name: "Host",
      path: "/prompting.Prompting/Host",
      type: GRPCCallType.bidirectionalStreaming
    )

    internal static let prompt = GRPCMethodDescriptor(
      name: "Prompt",
      path: "/prompting.Prompting/Prompt",
      type: GRPCCallType.unary
    )
  }
}

/// Prompting allows clients to host and request prompting.
///
/// To build a server, implement a class that conforms to this protocol.
internal protocol Prompting_PromptingProvider: CallHandlerProvider {
  var interceptors: Prompting_PromptingServerInterceptorFactoryProtocol? { get }

  /// Host allows clients to perform prompt hosting.
  func host(context: StreamingResponseCallContext<Prompting_HostResponse>) -> EventLoopFuture<(StreamEvent<Prompting_HostRequest>) -> Void>

  /// Prompt performs prompting using a specific prompter.
  func prompt(request: Prompting_PromptRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Prompting_PromptResponse>
}

extension Prompting_PromptingProvider {
  internal var serviceName: Substring {
    return Prompting_PromptingServerMetadata.serviceDescriptor.fullName[...]
  }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  internal func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "Host":
      return BidirectionalStreamingServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Prompting_HostRequest>(),
        responseSerializer: ProtobufSerializer<Prompting_HostResponse>(),
        interceptors: self.interceptors?.makeHostInterceptors() ?? [],
        observerFactory: self.host(context:)
      )

    case "Prompt":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Prompting_PromptRequest>(),
        responseSerializer: ProtobufSerializer<Prompting_PromptResponse>(),
        interceptors: self.interceptors?.makePromptInterceptors() ?? [],
        userFunction: self.prompt(request:context:)
      )

    default:
      return nil
    }
  }
}

/// Prompting allows clients to host and request prompting.
///
/// To implement a server, implement an object which conforms to this protocol.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
internal protocol Prompting_PromptingAsyncProvider: CallHandlerProvider, Sendable {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Prompting_PromptingServerInterceptorFactoryProtocol? { get }

  /// Host allows clients to perform prompt hosting.
  func host(
    requestStream: GRPCAsyncRequestStream<Prompting_HostRequest>,
    responseStream: GRPCAsyncResponseStreamWriter<Prompting_HostResponse>,
    context: GRPCAsyncServerCallContext
  ) async throws

  /// Prompt performs prompting using a specific prompter.
  func prompt(
    request: Prompting_PromptRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Prompting_PromptResponse
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Prompting_PromptingAsyncProvider {
  internal static var serviceDescriptor: GRPCServiceDescriptor {
    return Prompting_PromptingServerMetadata.serviceDescriptor
  }

  internal var serviceName: Substring {
    return Prompting_PromptingServerMetadata.serviceDescriptor.fullName[...]
  }

  internal var interceptors: Prompting_PromptingServerInterceptorFactoryProtocol? {
    return nil
  }

  internal func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "Host":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Prompting_HostRequest>(),
        responseSerializer: ProtobufSerializer<Prompting_HostResponse>(),
        interceptors: self.interceptors?.makeHostInterceptors() ?? [],
        wrapping: { try await self.host(requestStream: $0, responseStream: $1, context: $2) }
      )

    case "Prompt":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Prompting_PromptRequest>(),
        responseSerializer: ProtobufSerializer<Prompting_PromptResponse>(),
        interceptors: self.interceptors?.makePromptInterceptors() ?? [],
        wrapping: { try await self.prompt(request: $0, context: $1) }
      )

    default:
      return nil
    }
  }
}

internal protocol Prompting_PromptingServerInterceptorFactoryProtocol: Sendable {

  /// - Returns: Interceptors to use when handling 'host'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeHostInterceptors() -> [ServerInterceptor<Prompting_HostRequest, Prompting_HostResponse>]

  /// - Returns: Interceptors to use when handling 'prompt'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makePromptInterceptors() -> [ServerInterceptor<Prompting_PromptRequest, Prompting_PromptResponse>]
}

internal enum Prompting_PromptingServerMetadata {
  internal static let serviceDescriptor = GRPCServiceDescriptor(
    name: "Prompting",
    fullName: "prompting.Prompting",
    methods: [
      Prompting_PromptingServerMetadata.Methods.host,
      Prompting_PromptingServerMetadata.Methods.prompt,
    ]
  )

  internal enum Methods {
    internal static let host = GRPCMethodDescriptor(
      name: "Host",
      path: "/prompting.Prompting/Host",
      type: GRPCCallType.bidirectionalStreaming
    )

    internal static let prompt = GRPCMethodDescriptor(
      name: "Prompt",
      path: "/prompting.Prompting/Prompt",
      type: GRPCCallType.unary
    )
  }
}
