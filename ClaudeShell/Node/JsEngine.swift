import Foundation
import JavaScriptCore

/// Lightweight JavaScript engine using iOS's built-in JavaScriptCore
/// Provides Node.js-like environment with polyfills for require, console, fs, process
class JsEngine {
    static let shared = JsEngine()

    private var context: JSContext?
    private var sandboxRoot: String = ""
    private var outputCallback: ((String) -> Void)?

    /// Initialize the JS engine with a sandbox root directory
    func setup(sandboxRoot: String) {
        self.sandboxRoot = sandboxRoot

        // Create node_modules directory
        let nodeModules = sandboxRoot + "/node_modules"
        try? FileManager.default.createDirectory(atPath: nodeModules,
                                                   withIntermediateDirectories: true)
    }

    /// Run a JavaScript file
    func runFile(path: String, cwd: String, args: [String], output: @escaping (String) -> Void) -> Int32 {
        outputCallback = output

        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            output("node: cannot open '\(path)': No such file or directory\n")
            return 1
        }

        return execute(source: source, filename: path, cwd: cwd, args: args)
    }

    /// Run inline JavaScript
    func runEval(source: String, cwd: String, output: @escaping (String) -> Void) -> Int32 {
        outputCallback = output
        return execute(source: source, filename: "<eval>", cwd: cwd, args: [])
    }

    /// Execute JavaScript source code
    private func execute(source: String, filename: String, cwd: String, args: [String]) -> Int32 {
        let ctx = JSContext()!
        context = ctx
        var exitCode: Int32 = 0

        // --- console polyfill ---
        let consoleObj = JSValue(newObjectIn: ctx)!
        let logBlock: @convention(block) () -> Void = { [weak self] in
            let args = JSContext.currentArguments() ?? []
            let line = args.map { ($0 as? JSValue)?.toString() ?? "undefined" }.joined(separator: " ")
            self?.outputCallback?(line + "\n")
        }
        consoleObj.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        consoleObj.setObject(logBlock, forKeyedSubscript: "info" as NSString)
        consoleObj.setObject(logBlock, forKeyedSubscript: "warn" as NSString)

        let errorBlock: @convention(block) () -> Void = { [weak self] in
            let args = JSContext.currentArguments() ?? []
            let line = args.map { ($0 as? JSValue)?.toString() ?? "undefined" }.joined(separator: " ")
            self?.outputCallback?("\u{001B}[31m" + line + "\u{001B}[0m\n")
        }
        consoleObj.setObject(errorBlock, forKeyedSubscript: "error" as NSString)
        ctx.setObject(consoleObj, forKeyedSubscript: "console" as NSString)

        // --- process polyfill ---
        let processObj = JSValue(newObjectIn: ctx)!
        processObj.setObject(["node", filename] + args, forKeyedSubscript: "argv" as NSString)
        processObj.setObject(cwd, forKeyedSubscript: "cwd" as NSString)
        processObj.setObject("darwin", forKeyedSubscript: "platform" as NSString)
        processObj.setObject("ios", forKeyedSubscript: "arch" as NSString)
        processObj.setObject(["HOME": sandboxRoot, "NODE_PATH": sandboxRoot + "/node_modules"],
                            forKeyedSubscript: "env" as NSString)

        let exitBlock: @convention(block) (Int32) -> Void = { code in
            exitCode = code
        }
        processObj.setObject(exitBlock, forKeyedSubscript: "exit" as NSString)
        ctx.setObject(processObj, forKeyedSubscript: "process" as NSString)

        // --- require polyfill ---
        let requireBlock: @convention(block) (String) -> JSValue = { [weak self] moduleName in
            guard let self = self else { return JSValue(undefinedIn: ctx) }
            return self.requireModule(moduleName, from: cwd, ctx: ctx)
        }
        ctx.setObject(requireBlock, forKeyedSubscript: "require" as NSString)

        // --- module/exports ---
        let moduleObj = JSValue(newObjectIn: ctx)!
        let exportsObj = JSValue(newObjectIn: ctx)!
        moduleObj.setObject(exportsObj, forKeyedSubscript: "exports" as NSString)
        moduleObj.setObject(filename, forKeyedSubscript: "filename" as NSString)
        ctx.setObject(moduleObj, forKeyedSubscript: "module" as NSString)
        ctx.setObject(exportsObj, forKeyedSubscript: "exports" as NSString)

        // --- __dirname / __filename ---
        ctx.setObject((filename as NSString).deletingLastPathComponent,
                      forKeyedSubscript: "__dirname" as NSString)
        ctx.setObject(filename, forKeyedSubscript: "__filename" as NSString)

        // --- setTimeout/setInterval stubs ---
        let setTimeoutBlock: @convention(block) (JSValue, Double) -> Int = { callback, ms in
            DispatchQueue.global().asyncAfter(deadline: .now() + ms / 1000.0) {
                callback.call(withArguments: [])
            }
            return 1
        }
        ctx.setObject(setTimeoutBlock, forKeyedSubscript: "setTimeout" as NSString)

        // --- Exception handler ---
        ctx.exceptionHandler = { [weak self] _, exception in
            if let exception = exception {
                self?.outputCallback?("\u{001B}[31m\(exception)\u{001B}[0m\n")
                exitCode = 1
            }
        }

        // Run the code
        ctx.evaluateScript(source)

        return exitCode
    }

    /// Basic require() implementation
    private func requireModule(_ name: String, from cwd: String, ctx: JSContext) -> JSValue {
        // Built-in modules
        switch name {
        case "path":
            return createPathModule(ctx: ctx)
        case "fs":
            return createFsModule(ctx: ctx)
        case "os":
            return createOsModule(ctx: ctx)
        default:
            break
        }

        // Try to load from node_modules or relative path
        let searchPaths: [String]
        if name.hasPrefix("./") || name.hasPrefix("../") || name.hasPrefix("/") {
            // Relative/absolute require
            let resolved: String
            if name.hasPrefix("/") {
                resolved = sandboxRoot + name
            } else {
                resolved = cwd + "/" + name
            }
            searchPaths = [resolved, resolved + ".js", resolved + "/index.js"]
        } else {
            // node_modules require
            let nmPath = sandboxRoot + "/node_modules/" + name
            searchPaths = [
                nmPath + "/index.js",
                nmPath + "/main.js",
                nmPath + "/" + name + ".js"
            ]

            // Check package.json for main field
            let pkgPath = nmPath + "/package.json"
            if let pkgData = try? Data(contentsOf: URL(fileURLWithPath: pkgPath)),
               let pkg = try? JSONSerialization.jsonObject(with: pkgData) as? [String: Any],
               let main = pkg["main"] as? String {
                let mainPath = nmPath + "/" + main
                if let source = try? String(contentsOfFile: mainPath, encoding: .utf8) {
                    let moduleCtx = JSValue(newObjectIn: ctx)!
                    let exportsCtx = JSValue(newObjectIn: ctx)!
                    moduleCtx.setObject(exportsCtx, forKeyedSubscript: "exports" as NSString)

                    let wrapped = "(function(module, exports, require, __dirname, __filename) {\n\(source)\n})"
                    if let fn = ctx.evaluateScript(wrapped) {
                        let requireBlock: @convention(block) (String) -> JSValue = { [weak self] subName in
                            guard let self = self else { return JSValue(undefinedIn: ctx) }
                            return self.requireModule(subName, from: (mainPath as NSString).deletingLastPathComponent, ctx: ctx)
                        }
                        fn.call(withArguments: [
                            moduleCtx,
                            exportsCtx,
                            unsafeBitCast(requireBlock, to: AnyObject.self),
                            (mainPath as NSString).deletingLastPathComponent,
                            mainPath
                        ])
                    }
                    return moduleCtx.objectForKeyedSubscript("exports")!
                }
            }
        }

        // Try each search path
        for path in searchPaths {
            if let source = try? String(contentsOfFile: path, encoding: .utf8) {
                let moduleCtx = JSValue(newObjectIn: ctx)!
                let exportsCtx = JSValue(newObjectIn: ctx)!
                moduleCtx.setObject(exportsCtx, forKeyedSubscript: "exports" as NSString)

                let wrapped = "(function(module, exports, require, __dirname, __filename) {\n\(source)\n})"
                if let fn = ctx.evaluateScript(wrapped) {
                    let dir = (path as NSString).deletingLastPathComponent
                    let requireBlock: @convention(block) (String) -> JSValue = { [weak self] subName in
                        guard let self = self else { return JSValue(undefinedIn: ctx) }
                        return self.requireModule(subName, from: dir, ctx: ctx)
                    }
                    fn.call(withArguments: [
                        moduleCtx,
                        exportsCtx,
                        unsafeBitCast(requireBlock, to: AnyObject.self),
                        dir,
                        path
                    ])
                }
                return moduleCtx.objectForKeyedSubscript("exports")!
            }
        }

        outputCallback?("Error: Cannot find module '\(name)'\n")
        return JSValue(undefinedIn: ctx)
    }

    // MARK: - Built-in Module Polyfills

    private func createPathModule(ctx: JSContext) -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        let joinBlock: @convention(block) () -> String = {
            let args = JSContext.currentArguments() ?? []
            let parts = args.compactMap { ($0 as? JSValue)?.toString() }
            return parts.joined(separator: "/")
                .replacingOccurrences(of: "//", with: "/")
        }
        obj.setObject(joinBlock, forKeyedSubscript: "join" as NSString)

        let basenameBlock: @convention(block) (String) -> String = { path in
            return (path as NSString).lastPathComponent
        }
        obj.setObject(basenameBlock, forKeyedSubscript: "basename" as NSString)

        let dirnameBlock: @convention(block) (String) -> String = { path in
            return (path as NSString).deletingLastPathComponent
        }
        obj.setObject(dirnameBlock, forKeyedSubscript: "dirname" as NSString)

        let extnameBlock: @convention(block) (String) -> String = { path in
            let ext = (path as NSString).pathExtension
            return ext.isEmpty ? "" : ".\(ext)"
        }
        obj.setObject(extnameBlock, forKeyedSubscript: "extname" as NSString)

        obj.setObject("/", forKeyedSubscript: "sep" as NSString)

        return obj
    }

    private func createFsModule(ctx: JSContext) -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let root = sandboxRoot

        let readFileSync: @convention(block) (String, String?) -> String = { path, encoding in
            let fullPath: String
            if path.hasPrefix("/") {
                fullPath = root + path
            } else {
                fullPath = path
            }
            return (try? String(contentsOfFile: fullPath, encoding: .utf8)) ?? ""
        }
        obj.setObject(readFileSync, forKeyedSubscript: "readFileSync" as NSString)

        let writeFileSync: @convention(block) (String, String) -> Void = { path, content in
            let fullPath: String
            if path.hasPrefix("/") {
                fullPath = root + path
            } else {
                fullPath = path
            }
            try? content.write(toFile: fullPath, atomically: true, encoding: .utf8)
        }
        obj.setObject(writeFileSync, forKeyedSubscript: "writeFileSync" as NSString)

        let existsSync: @convention(block) (String) -> Bool = { path in
            let fullPath = path.hasPrefix("/") ? root + path : path
            return FileManager.default.fileExists(atPath: fullPath)
        }
        obj.setObject(existsSync, forKeyedSubscript: "existsSync" as NSString)

        let readdirSync: @convention(block) (String) -> [String] = { path in
            let fullPath = path.hasPrefix("/") ? root + path : path
            return (try? FileManager.default.contentsOfDirectory(atPath: fullPath)) ?? []
        }
        obj.setObject(readdirSync, forKeyedSubscript: "readdirSync" as NSString)

        let mkdirSync: @convention(block) (String) -> Void = { path in
            let fullPath = path.hasPrefix("/") ? root + path : path
            try? FileManager.default.createDirectory(atPath: fullPath,
                                                      withIntermediateDirectories: true)
        }
        obj.setObject(mkdirSync, forKeyedSubscript: "mkdirSync" as NSString)

        return obj
    }

    private func createOsModule(ctx: JSContext) -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        obj.setObject("Darwin", forKeyedSubscript: "type" as NSString)
        obj.setObject("darwin", forKeyedSubscript: "platform" as NSString)

        let homedirBlock: @convention(block) () -> String = { [weak self] in
            return self?.sandboxRoot ?? "/"
        }
        obj.setObject(homedirBlock, forKeyedSubscript: "homedir" as NSString)
        obj.setObject("\n", forKeyedSubscript: "EOL" as NSString)

        return obj
    }
}
