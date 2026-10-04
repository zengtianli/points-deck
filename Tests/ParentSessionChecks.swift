import Foundation

// 兼容既有 Chapter test 入口；验证新交易客户端的真实超时恢复协议。
private final class TransactionTransport: URLProtocol {
    static var paths: [String] = []
    static var mode = "timeout"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path; Self.paths.append(path)
        if path == "/api/adjust" && Self.mode == "timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
        }
        let status = Self.mode == "conflict" ? 409 : 200
        let json = status == 409 ? "{\"ok\":false,\"err\":\"配置已变化\"}" : "{\"ok\":true,\"found\":true,\"entry\":{\"id\":\"one-entry\",\"pts\":5,\"label\":\"阅读\"}}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct TransactionChecks {
    static func main() async throws {
        precondition(URLProtocol.registerClass(TransactionTransport.self))
        defer { URLProtocol.unregisterClass(TransactionTransport.self) }
        let receipt = try await Api.transaction("api/adjust", body: ["pts": 5], requestID: "stable-request-001")
        precondition(receipt.entryID == "one-entry" && receipt.message.contains("+5"))
        precondition(TransactionTransport.paths == ["/api/adjust", "/api/request_result"])
        TransactionTransport.mode = "conflict"
        do { _ = try await Api.configPut(kind: "rules", items: [], revision: "old"); preconditionFailure("拒绝冲突") }
        catch let failure as Api.Failure { precondition(failure.status == 409) }
        print("PASS: 超时先查询原交易；收到真实回执；配置冲突保留 HTTP 状态；未连接生产服务")
    }
}
