import Foundation

@preconcurrency
@objc public protocol VPNXPCProtocol {
    func start(with reply: @escaping (NSError?) -> Void)
    func stop(with reply: @escaping (NSError?) -> Void)
}

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     connectionToService = NSXPCConnection(serviceName: "com.coder.Coder-Desktop.VPNXPC")
     connectionToService.remoteObjectInterface = NSXPCInterface(with: VPNXPCProtocol.self)
     connectionToService.resume()

 Once you have a connection to the service, you can use it like this:

     if let proxy = connectionToService.remoteObjectProxy as? VPNXPCProtocol {
         proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
             NSLog("Result of calculation is: \(result)")
         }
     }

 And, when you are finished with the service, clean up the connection like this:

     connectionToService.invalidate()
 */
