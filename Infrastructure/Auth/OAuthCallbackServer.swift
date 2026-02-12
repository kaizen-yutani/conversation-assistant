import Foundation

/// Local HTTP server for receiving OAuth callbacks using BSD sockets
/// NWListener fails with hardened runtime, so we use low-level sockets
final class OAuthCallbackServer {

    private var serverSocket: Int32 = -1
    private var completion: ((String?, Error?) -> Void)?
    private var timeoutTask: DispatchWorkItem?
    private var activePort: UInt16 = 0
    private var isRunning = false

    /// Expected state parameter for CSRF validation
    var expectedState: String?

    /// Ports to try for OAuth callback
    static let callbackPorts: [UInt16] = [9876, 9877, 9878, 19876, 29876]

    /// The callback URL to use for OAuth redirect_uri
    var callbackURL: String {
        return "http://localhost:\(activePort)/callback"
    }

    /// Dedicated queue for the server
    private let serverQueue = DispatchQueue(label: "oauth.callback.server", qos: .userInitiated)

    deinit {
        stop()
    }

    /// Starts the server and waits for OAuth callback
    func start(timeout: TimeInterval = 300, onReady: @escaping (String) -> Void, completion: @escaping (String?, Error?) -> Void) {
        print("[OAuthCallbackServer] start() called")
        self.completion = completion

        serverQueue.async { [weak self] in
            self?.tryPorts(timeout: timeout, onReady: onReady, completion: completion)
        }
    }

    private func tryPorts(timeout: TimeInterval, onReady: @escaping (String) -> Void, completion: @escaping (String?, Error?) -> Void) {
        for port in Self.callbackPorts {
            print("[OAuthCallbackServer] Trying port \(port)...")

            // Create socket
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            if sock < 0 {
                print("[OAuthCallbackServer] Failed to create socket: \(errno)")
                continue
            }

            // Allow address reuse
            var reuse: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

            // Bind to port
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = INADDR_ANY

            let bindResult = withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    bind(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if bindResult < 0 {
                print("[OAuthCallbackServer] Port \(port) bind failed: \(errno)")
                close(sock)
                continue
            }

            // Listen
            if listen(sock, 1) < 0 {
                print("[OAuthCallbackServer] Port \(port) listen failed: \(errno)")
                close(sock)
                continue
            }

            // Success!
            print("[OAuthCallbackServer] Server listening on port \(port)")
            self.serverSocket = sock
            self.activePort = port
            self.isRunning = true

            // Set timeout
            let timeoutWork = DispatchWorkItem { [weak self] in
                print("[OAuthCallbackServer] Timeout waiting for callback")
                self?.complete(code: nil, error: OAuthCallbackError.timeout)
            }
            self.timeoutTask = timeoutWork
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            // Notify ready on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                onReady(self.callbackURL)
            }

            // Start accept loop
            self.acceptLoop()
            return
        }

        // All ports failed
        print("[OAuthCallbackServer] All ports unavailable")
        DispatchQueue.main.async {
            completion(nil, OAuthCallbackError.allPortsBusy)
        }
    }

    private func acceptLoop() {
        serverQueue.async { [weak self] in
            guard let self = self, self.isRunning, self.serverSocket >= 0 else { return }

            // Use poll() instead of select() - simpler API
            var pollFd = pollfd(fd: self.serverSocket, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pollFd, 1, 1000) // 1 second timeout

            if pollResult > 0 && (pollFd.revents & Int16(POLLIN)) != 0 {
                // Accept connection
                var clientAddr = sockaddr_in()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        accept(self.serverSocket, sockaddrPtr, &clientAddrLen)
                    }
                }

                if clientSocket >= 0 {
                    print("[OAuthCallbackServer] Accepted connection")
                    self.handleClient(clientSocket)
                }
            }

            // Continue accepting if still running
            if self.isRunning {
                self.acceptLoop()
            }
        }
    }

    private func handleClient(_ clientSocket: Int32) {
        // Read HTTP request
        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = read(clientSocket, &buffer, buffer.count - 1)

        guard bytesRead > 0 else {
            close(clientSocket)
            return
        }

        let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        print("[OAuthCallbackServer] Received request: \(request.prefix(100))...")

        // Parse and respond
        if let code = parseAuthorizationCode(from: request) {
            print("[OAuthCallbackServer] Got authorization code")
            sendSuccessResponse(to: clientSocket)
            close(clientSocket)
            complete(code: code, error: nil)
        } else if request.contains("error=") {
            let errorDesc = parseError(from: request)
            print("[OAuthCallbackServer] OAuth error: \(errorDesc)")
            sendErrorResponse(to: clientSocket, error: errorDesc)
            close(clientSocket)
            complete(code: nil, error: OAuthCallbackError.authorizationDenied(errorDesc))
        } else {
            // Not the callback request
            send404Response(to: clientSocket)
            close(clientSocket)
        }
    }

    /// Stops the server
    func stop() {
        isRunning = false
        timeoutTask?.cancel()
        timeoutTask = nil

        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        print("[OAuthCallbackServer] Server stopped")
    }

    // MARK: - Parsing

    private func parseAuthorizationCode(from request: String) -> String? {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              firstLine.contains("/callback?") else {
            return nil
        }

        guard let queryStart = firstLine.range(of: "?"),
              let queryEnd = firstLine.range(of: " HTTP") else {
            return nil
        }

        let queryString = String(firstLine[queryStart.upperBound..<queryEnd.lowerBound])
        let components = URLComponents(string: "http://localhost?\(queryString)")

        // Validate state parameter if expected (CSRF protection)
        if let expectedState = expectedState {
            let returnedState = components?.queryItems?.first(where: { $0.name == "state" })?.value
            guard returnedState == expectedState else {
                NSLog("OAuth: State mismatch in callback server — possible CSRF attack")
                return nil
            }
        }

        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }

    private func parseError(from request: String) -> String {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let queryStart = firstLine.range(of: "?"),
              let queryEnd = firstLine.range(of: " HTTP") else {
            return "Unknown error"
        }

        let queryString = String(firstLine[queryStart.upperBound..<queryEnd.lowerBound])
        let components = URLComponents(string: "http://localhost?\(queryString)")

        let errorValue = components?.queryItems?.first(where: { $0.name == "error" })?.value ?? "unknown"
        let description = components?.queryItems?.first(where: { $0.name == "error_description" })?.value ?? ""

        return description.isEmpty ? errorValue : "\(errorValue): \(description)"
    }

    // MARK: - HTTP Responses

    private func sendSuccessResponse(to socket: Int32) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Authorization Complete</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    margin: 0;
                    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                    color: #fff;
                }
                .container {
                    text-align: center;
                    padding: 40px;
                    background: rgba(255, 255, 255, 0.1);
                    border-radius: 16px;
                    backdrop-filter: blur(10px);
                    border: 1px solid rgba(255, 255, 255, 0.2);
                    max-width: 400px;
                }
                .checkmark {
                    width: 80px;
                    height: 80px;
                    margin: 0 auto 20px;
                    background: #22c55e;
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    animation: pulse 2s ease-in-out infinite;
                }
                .checkmark svg {
                    width: 40px;
                    height: 40px;
                    stroke: white;
                    stroke-width: 3;
                    fill: none;
                }
                h1 {
                    font-size: 24px;
                    margin: 0 0 10px;
                    font-weight: 600;
                }
                p {
                    color: rgba(255, 255, 255, 0.7);
                    margin: 0;
                    font-size: 16px;
                }
                @keyframes pulse {
                    0%, 100% { transform: scale(1); }
                    50% { transform: scale(1.05); }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="checkmark">
                    <svg viewBox="0 0 24 24">
                        <polyline points="20 6 9 17 4 12"></polyline>
                    </svg>
                </div>
                <h1>Authorization Successful</h1>
                <p>You can close this page and return to the app.</p>
            </div>
        </body>
        </html>
        """

        sendHTTPResponse(to: socket, statusCode: 200, body: html)
    }

    private func sendErrorResponse(to socket: Int32, error: String) {
        let escapedError = error
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Authorization Failed</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    margin: 0;
                    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                    color: #fff;
                }
                .container {
                    text-align: center;
                    padding: 40px;
                    background: rgba(255, 255, 255, 0.1);
                    border-radius: 16px;
                    backdrop-filter: blur(10px);
                    border: 1px solid rgba(255, 255, 255, 0.2);
                    max-width: 400px;
                }
                .error-icon {
                    width: 80px;
                    height: 80px;
                    margin: 0 auto 20px;
                    background: #ef4444;
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .error-icon svg {
                    width: 40px;
                    height: 40px;
                    stroke: white;
                    stroke-width: 3;
                    fill: none;
                }
                h1 {
                    font-size: 24px;
                    margin: 0 0 10px;
                    font-weight: 600;
                }
                p {
                    color: rgba(255, 255, 255, 0.7);
                    margin: 0;
                    font-size: 16px;
                }
                .error-detail {
                    margin-top: 15px;
                    padding: 10px;
                    background: rgba(239, 68, 68, 0.2);
                    border-radius: 8px;
                    font-size: 14px;
                    color: #fca5a5;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="error-icon">
                    <svg viewBox="0 0 24 24">
                        <line x1="18" y1="6" x2="6" y2="18"></line>
                        <line x1="6" y1="6" x2="18" y2="18"></line>
                    </svg>
                </div>
                <h1>Authorization Failed</h1>
                <p>You can close this page and try again.</p>
                <div class="error-detail">\(escapedError)</div>
            </div>
        </body>
        </html>
        """

        sendHTTPResponse(to: socket, statusCode: 400, body: html)
    }

    private func send404Response(to socket: Int32) {
        sendHTTPResponse(to: socket, statusCode: 404, body: "Not Found")
    }

    private func sendHTTPResponse(to socket: Int32, statusCode: Int, body: String) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        default: statusText = "Not Found"
        }

        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        if let data = response.data(using: .utf8) {
            data.withUnsafeBytes { bytes in
                _ = write(socket, bytes.baseAddress, data.count)
            }
        }
    }

    private func complete(code: String?, error: Error?) {
        guard let completion = self.completion else { return }
        self.completion = nil

        stop()

        DispatchQueue.main.async {
            completion(code, error)
        }
    }
}

// MARK: - Errors

enum OAuthCallbackError: Error, LocalizedError {
    case serverFailed(Error)
    case timeout
    case authorizationDenied(String)
    case allPortsBusy

    var errorDescription: String? {
        switch self {
        case .serverFailed(let underlyingError):
            return "Failed to start callback server: \(underlyingError.localizedDescription)"
        case .timeout:
            return "Authorization timed out"
        case .authorizationDenied(let reason):
            return "Authorization denied: \(reason)"
        case .allPortsBusy:
            return "All OAuth callback ports are busy. Please close other applications and try again."
        }
    }
}
