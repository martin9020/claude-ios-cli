import Foundation

/// Defines tools that Claude can use autonomously during conversations
struct ToolDefinitions {

    /// All available tools for the Claude API
    static let allTools: [[String: Any]] = [bashTool, readFileTool, writeFileTool]

    /// bash — execute a shell command and return output
    static let bashTool: [String: Any] = [
        "name": "bash",
        "description": "Execute a shell command in the ClaudeShell environment. Returns stdout output. Available commands: ls, cat, cp, mv, rm, mkdir, touch, pwd, cd, find, chmod, du, grep, head, tail, wc, sort, uniq, sed, tr, cut, diff, echo, env, export, date, curl, wget.",
        "input_schema": [
            "type": "object",
            "properties": [
                "command": [
                    "type": "string",
                    "description": "The shell command to execute"
                ]
            ],
            "required": ["command"]
        ] as [String: Any]
    ]

    /// read_file — read the contents of a file
    static let readFileTool: [String: Any] = [
        "name": "read_file",
        "description": "Read the contents of a file from the filesystem. Path is relative to the current working directory, or absolute from the sandbox root /.",
        "input_schema": [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Path to the file to read"
                ]
            ],
            "required": ["path"]
        ] as [String: Any]
    ]

    /// write_file — write content to a file
    static let writeFileTool: [String: Any] = [
        "name": "write_file",
        "description": "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Path is relative to the current working directory, or absolute from the sandbox root /.",
        "input_schema": [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Path to the file to write"
                ],
                "content": [
                    "type": "string",
                    "description": "Content to write to the file"
                ]
            ],
            "required": ["path", "content"]
        ] as [String: Any]
    ]
}
