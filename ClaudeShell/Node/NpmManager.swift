import Foundation

/// Handles npm package operations — install, list, remove
/// Downloads packages from registry.npmjs.org into the app's sandbox
class NpmManager {
    static let shared = NpmManager()

    private let registryURL = "https://registry.npmjs.org"
    private var sandboxRoot: String = ""
    private var nodeModulesPath: String { sandboxRoot + "/node_modules" }

    func setup(sandboxRoot: String) {
        self.sandboxRoot = sandboxRoot
        try? FileManager.default.createDirectory(atPath: nodeModulesPath,
                                                   withIntermediateDirectories: true)
    }

    /// Handle `npm` command with subcommands
    func handleCommand(args: [String], cwd: String, output: @escaping (String) -> Void) -> Int32 {
        guard !args.isEmpty else {
            output(usage())
            return 1
        }

        let subcommand = args[0]
        let rest = Array(args.dropFirst())

        switch subcommand {
        case "install", "i":
            if rest.isEmpty {
                output("npm install: specify a package name\n")
                output("Usage: npm install <package>\n")
                return 1
            }
            return installPackage(name: rest[0], output: output)

        case "uninstall", "remove", "rm":
            if rest.isEmpty {
                output("npm uninstall: specify a package name\n")
                return 1
            }
            return uninstallPackage(name: rest[0], output: output)

        case "list", "ls":
            return listPackages(output: output)

        case "init":
            return initPackage(cwd: cwd, output: output)

        case "run":
            if rest.isEmpty {
                output("npm run: specify a script name\n")
                return 1
            }
            return runScript(name: rest[0], cwd: cwd, output: output)

        case "help", "--help", "-h":
            output(usage())
            return 0

        default:
            output("npm: unknown command '\(subcommand)'\n")
            output(usage())
            return 1
        }
    }

    // MARK: - Install

    private func installPackage(name: String, output: @escaping (String) -> Void) -> Int32 {
        // Parse name@version
        let parts = name.split(separator: "@", maxSplits: 1)
        let packageName = String(parts[0])
        let requestedVersion = parts.count > 1 ? String(parts[1]) : "latest"

        output("npm: fetching \(packageName)@\(requestedVersion)...\n")

        // 1. Get package metadata from registry
        guard let metaURL = URL(string: "\(registryURL)/\(packageName)") else {
            output("npm ERR! invalid package name\n")
            return 1
        }

        var metaResult: Data?
        var metaError: String?
        let semaphore = DispatchSemaphore(value: 0)

        let metaTask = URLSession.shared.dataTask(with: metaURL) { data, response, error in
            if let error = error {
                metaError = error.localizedDescription
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                metaError = "package '\(packageName)' not found"
            } else {
                metaResult = data
            }
            semaphore.signal()
        }
        metaTask.resume()
        semaphore.wait()

        if let error = metaError {
            output("npm ERR! \(error)\n")
            return 1
        }

        guard let data = metaResult,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            output("npm ERR! failed to parse registry response\n")
            return 1
        }

        // 2. Find version
        guard let versions = json["versions"] as? [String: Any] else {
            output("npm ERR! no versions found for \(packageName)\n")
            return 1
        }

        let version: String
        if requestedVersion == "latest" {
            if let distTags = json["dist-tags"] as? [String: String],
               let latest = distTags["latest"] {
                version = latest
            } else {
                version = versions.keys.sorted().last ?? ""
            }
        } else {
            version = requestedVersion
        }

        guard let versionInfo = versions[version] as? [String: Any],
              let dist = versionInfo["dist"] as? [String: Any],
              let tarballURLStr = dist["tarball"] as? String,
              let tarballURL = URL(string: tarballURLStr) else {
            output("npm ERR! version '\(version)' not found for \(packageName)\n")
            return 1
        }

        output("npm: downloading \(packageName)@\(version)...\n")

        // 3. Download tarball
        var tarballData: Data?
        let dlSemaphore = DispatchSemaphore(value: 0)

        let dlTask = URLSession.shared.dataTask(with: tarballURL) { data, _, error in
            if error == nil { tarballData = data }
            dlSemaphore.signal()
        }
        dlTask.resume()
        dlSemaphore.wait()

        guard let tgzData = tarballData else {
            output("npm ERR! failed to download package\n")
            return 1
        }

        // 4. Extract tarball
        let packageDir = nodeModulesPath + "/" + packageName
        output("npm: extracting to node_modules/\(packageName)...\n")

        // Remove existing version
        try? FileManager.default.removeItem(atPath: packageDir)
        try? FileManager.default.createDirectory(atPath: packageDir,
                                                   withIntermediateDirectories: true)

        // Save the tarball temporarily
        let tmpTgz = sandboxRoot + "/tmp/\(packageName).tgz"
        try? FileManager.default.createDirectory(atPath: sandboxRoot + "/tmp",
                                                   withIntermediateDirectories: true)

        do {
            try tgzData.write(to: URL(fileURLWithPath: tmpTgz))
        } catch {
            output("npm ERR! failed to save package: \(error.localizedDescription)\n")
            return 1
        }

        // Extract using a simple tar.gz parser
        let extracted = extractTarGz(from: tmpTgz, to: packageDir)
        try? FileManager.default.removeItem(atPath: tmpTgz)

        if !extracted {
            // Fallback: save package.json and a stub
            let pkgJson: [String: Any] = [
                "name": packageName,
                "version": version,
                "main": "index.js"
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: pkgJson, options: .prettyPrinted) {
                try? jsonData.write(to: URL(fileURLWithPath: packageDir + "/package.json"))
            }
            try? "// Package: \(packageName)@\(version)\n// Downloaded from npm registry\nmodule.exports = {};\n"
                .write(toFile: packageDir + "/index.js", atomically: true, encoding: .utf8)
            output("npm: installed \(packageName)@\(version) (metadata only — tarball extraction limited on iOS)\n")
        } else {
            output("npm: installed \(packageName)@\(version)\n")
        }

        // 5. Install dependencies (top-level only, no deep resolution)
        if let deps = versionInfo["dependencies"] as? [String: String] {
            let depCount = deps.count
            if depCount > 0 {
                output("npm: installing \(depCount) dependencies...\n")
                for (depName, _) in deps.prefix(20) { // Limit to prevent infinite loops
                    if !FileManager.default.fileExists(atPath: nodeModulesPath + "/" + depName) {
                        let _ = installPackage(name: depName, output: output)
                    }
                }
            }
        }

        let sizeKB = folderSize(path: packageDir) / 1024
        output("\u{001B}[32m+ \(packageName)@\(version)\u{001B}[0m (\(sizeKB)KB)\n")
        return 0
    }

    // MARK: - Uninstall

    private func uninstallPackage(name: String, output: @escaping (String) -> Void) -> Int32 {
        let packageDir = nodeModulesPath + "/" + name
        guard FileManager.default.fileExists(atPath: packageDir) else {
            output("npm: '\(name)' is not installed\n")
            return 1
        }

        do {
            try FileManager.default.removeItem(atPath: packageDir)
            output("removed \(name)\n")
            return 0
        } catch {
            output("npm ERR! failed to remove: \(error.localizedDescription)\n")
            return 1
        }
    }

    // MARK: - List

    private func listPackages(output: @escaping (String) -> Void) -> Int32 {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: nodeModulesPath) else {
            output("node_modules/ (empty)\n")
            return 0
        }

        let packages = entries.filter { !$0.hasPrefix(".") }
        if packages.isEmpty {
            output("node_modules/ (empty)\n")
            return 0
        }

        output("node_modules/\n")
        for pkg in packages.sorted() {
            // Read version from package.json
            let pkgJsonPath = nodeModulesPath + "/" + pkg + "/package.json"
            var version = "?"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: pkgJsonPath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let v = json["version"] as? String {
                version = v
            }
            let sizeKB = folderSize(path: nodeModulesPath + "/" + pkg) / 1024
            output("  \(pkg)@\(version) (\(sizeKB)KB)\n")
        }
        output("\n\(packages.count) packages installed\n")
        return 0
    }

    // MARK: - Init

    private func initPackage(cwd: String, output: @escaping (String) -> Void) -> Int32 {
        let fullCwd = sandboxRoot + cwd
        let pkgPath = fullCwd + "/package.json"

        if FileManager.default.fileExists(atPath: pkgPath) {
            output("package.json already exists\n")
            return 1
        }

        let dirName = (cwd as NSString).lastPathComponent
        let pkg: [String: Any] = [
            "name": dirName.isEmpty ? "my-project" : dirName,
            "version": "1.0.0",
            "description": "",
            "main": "index.js",
            "scripts": ["start": "node index.js", "test": "echo \"no tests\""],
            "dependencies": [String: String]()
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: pkg, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: pkgPath))
            output("Created package.json\n")
            return 0
        } catch {
            output("npm ERR! \(error.localizedDescription)\n")
            return 1
        }
    }

    // MARK: - Run Script

    private func runScript(name: String, cwd: String, output: @escaping (String) -> Void) -> Int32 {
        let fullCwd = sandboxRoot + cwd
        let pkgPath = fullCwd + "/package.json"

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pkgPath)),
              let pkg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = pkg["scripts"] as? [String: String],
              let script = scripts[name] else {
            output("npm ERR! missing script: \(name)\n")
            return 1
        }

        // If script starts with "node ", run it via JsEngine
        if script.hasPrefix("node ") {
            let file = String(script.dropFirst(5))
            let filePath = fullCwd + "/" + file
            return JsEngine.shared.runFile(path: filePath, cwd: fullCwd, args: [], output: output)
        }

        output("npm run \(name): \(script)\n")
        output("(only 'node' scripts are supported)\n")
        return 1
    }

    // MARK: - Helpers

    private func usage() -> String {
        return """
        \u{001B}[1mnpm\u{001B}[0m — Node Package Manager for ClaudeShell

        \u{001B}[1mUsage:\u{001B}[0m
          npm install <package>    Install a package from npm registry
          npm uninstall <package>  Remove a package
          npm list                 List installed packages
          npm init                 Create package.json
          npm run <script>         Run a script from package.json
          npm help                 Show this help

        \u{001B}[1mExamples:\u{001B}[0m
          npm install lodash
          npm install chalk@5.0.0
          npm list
          npm init

        Packages are stored in ~/node_modules/
        """
    }

    /// Simple tar.gz extraction (handles gzip + tar headers)
    private func extractTarGz(from tgzPath: String, to destDir: String) -> Bool {
        guard let compressedData = try? Data(contentsOf: URL(fileURLWithPath: tgzPath)) else {
            return false
        }

        // Try to decompress gzip
        guard let decompressed = decompressGzip(compressedData) else {
            return false
        }

        // Parse tar archive
        return extractTar(data: decompressed, to: destDir)
    }

    /// Decompress gzip data using zlib (available on iOS)
    private func decompressGzip(_ data: Data) -> Data? {
        // Check gzip magic number
        guard data.count > 2, data[0] == 0x1f, data[1] == 0x8b else {
            return nil
        }

        var stream = z_stream()
        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: (data as NSData).bytes.bindMemory(to: Bytef.self, capacity: data.count))
        stream.avail_in = uint(data.count)

        // Initialize for gzip decompression (windowBits = 15 + 32 for auto-detect)
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }

        var result = Data()
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        repeat {
            stream.next_out = &buffer
            stream.avail_out = uint(bufferSize)

            let status = inflate(&stream, Z_NO_FLUSH)
            if status != Z_OK && status != Z_STREAM_END {
                inflateEnd(&stream)
                return nil
            }

            let bytesWritten = bufferSize - Int(stream.avail_out)
            result.append(buffer, count: bytesWritten)

            if status == Z_STREAM_END { break }
        } while stream.avail_out == 0

        inflateEnd(&stream)
        return result
    }

    /// Extract tar archive data
    private func extractTar(data: Data, to destDir: String) -> Bool {
        var offset = 0
        var extractedFiles = 0
        let fm = FileManager.default

        while offset + 512 <= data.count {
            // Read tar header (512 bytes)
            let header = data.subdata(in: offset..<offset + 512)

            // Check for end-of-archive (all zeros)
            if header.allSatisfy({ $0 == 0 }) { break }

            // Extract filename (bytes 0-99)
            let nameData = header.subdata(in: 0..<100)
            var name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""

            // Strip "package/" prefix that npm tarballs use
            if name.hasPrefix("package/") {
                name = String(name.dropFirst(8))
            }

            // Skip empty names
            if name.isEmpty {
                offset += 512
                continue
            }

            // Extract file size (bytes 124-135, octal)
            let sizeData = header.subdata(in: 124..<136)
            let sizeStr = String(data: sizeData, encoding: .utf8)?
                .trimmingCharacters(in: .init(charactersIn: " \0")) ?? "0"
            let fileSize = Int(sizeStr, radix: 8) ?? 0

            // File type (byte 156)
            let typeFlag = header[156]

            offset += 512 // Move past header

            let fullPath = destDir + "/" + name

            if typeFlag == 53 || name.hasSuffix("/") {
                // Directory
                try? fm.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
            } else if fileSize > 0 && offset + fileSize <= data.count {
                // Regular file
                let dir = (fullPath as NSString).deletingLastPathComponent
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

                let fileData = data.subdata(in: offset..<offset + fileSize)
                try? fileData.write(to: URL(fileURLWithPath: fullPath))
                extractedFiles += 1
            }

            // Advance to next 512-byte boundary
            let blocks = (fileSize + 511) / 512
            offset += blocks * 512
        }

        return extractedFiles > 0
    }

    private func folderSize(path: String) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var size: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            let fullPath = path + "/" + file
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let fileSize = attrs[.size] as? Int64 {
                size += fileSize
            }
        }
        return size
    }
}
