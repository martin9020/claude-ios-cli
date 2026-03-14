import Foundation
import Network

/// Simple HTTP file server using NWListener
/// Serves static files from the current shell directory
class HttpServer {
    static let shared = HttpServer()

    private var listener: NWListener?
    private var isServing = false
    private var currentPort: UInt16 = 8080
    private var servingRoot: String = ""

    private let mimeTypes: [String: String] = [
        "html": "text/html",
        "css": "text/css",
        "js": "application/javascript",
        "json": "application/json",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "svg": "image/svg+xml",
        "txt": "text/plain",
        "xml": "application/xml",
        "ico": "image/x-icon",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "pdf": "application/pdf",
    ]

    /// Handle the `serve` command: serve [port], serve stop, serve status
    func handleCommand(args: [String], sandboxRoot: String, cwd: String,
                       output: @escaping (String) -> Void) -> Int32 {
        let subcommand = args.first ?? ""

        if subcommand == "stop" {
            return stopServer(output: output)
        }

        if subcommand == "status" {
            return showStatus(output: output)
        }

        // serve [port] — start
        let port: UInt16
        if let p = UInt16(subcommand), p > 0 {
            port = p
        } else if subcommand.isEmpty || subcommand == "start" {
            port = 8080
        } else {
            output("serve: unknown option '\(subcommand)'\n")
            output("Usage: serve [port]  — start HTTP server\n")
            output("       serve stop    — stop server\n")
            output("       serve status  — show server status\n")
            return 1
        }

        return startServer(port: port, sandboxRoot: sandboxRoot, cwd: cwd, output: output)
    }

    private func startServer(port: UInt16, sandboxRoot: String, cwd: String,
                             output: @escaping (String) -> Void) -> Int32 {
        if isServing {
            output("serve: already running on port \(currentPort). Use 'serve stop' first.\n")
            return 1
        }

        servingRoot = sandboxRoot + cwd
        currentPort = port

        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            output("serve: failed to create listener: \(error.localizedDescription)\n")
            return 1
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                output("serve: listener failed: \(error.localizedDescription)\n")
            default:
                break
            }
        }

        listener?.start(queue: DispatchQueue.global(qos: .userInitiated))
        isServing = true
        output("Serving files from \(cwd) on http://localhost:\(port)\n")
        output("Use 'serve stop' to stop the server.\n")
        return 0
    }

    private func stopServer(output: @escaping (String) -> Void) -> Int32 {
        guard isServing, let listener = listener else {
            output("serve: no server running\n")
            return 1
        }
        listener.cancel()
        self.listener = nil
        isServing = false
        output("Server stopped.\n")
        return 0
    }

    private func showStatus(output: @escaping (String) -> Void) -> Int32 {
        if isServing {
            output("HTTP server running on http://localhost:\(currentPort)\n")
            output("Serving from: \(servingRoot)\n")
        } else {
            output("HTTP server is not running.\n")
        }
        return 0
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }
            let request = String(data: data, encoding: .utf8) ?? ""
            let response = self.buildResponse(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func buildResponse(for request: String) -> Data {
        // Parse GET /path HTTP/1.x
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return errorResponse(400, "Bad Request") }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return errorResponse(400, "Bad Request") }

        var path = parts[1]
        // Remove query string
        if let qIdx = path.firstIndex(of: "?") { path = String(path[..<qIdx]) }
        // Serve index.html for /
        if path == "/" { path = "/index.html" }
        // Prevent directory traversal
        let cleaned = path.replacingOccurrences(of: "..", with: "")
        let filePath = servingRoot + cleaned

        guard FileManager.default.fileExists(atPath: filePath),
              let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            return errorResponse(404, "Not Found")
        }

        let ext = (filePath as NSString).pathExtension.lowercased()
        let contentType = mimeTypes[ext] ?? "application/octet-stream"

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(fileData.count)\r\n"
        header += "Connection: close\r\n\r\n"

        var response = header.data(using: .utf8) ?? Data()
        response.append(fileData)
        return response
    }

    private func errorResponse(_ code: Int, _ message: String) -> Data {
        let body = "<html><body><h1>\(code) \(message)</h1></body></html>"
        var header = "HTTP/1.1 \(code) \(message)\r\n"
        header += "Content-Type: text/html\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        return (header + body).data(using: .utf8) ?? Data()
    }
}
