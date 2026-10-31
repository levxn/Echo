import os

enum Log {
    static let app = Logger(subsystem: "echo", category: "app")
    static let vad = Logger(subsystem: "echo", category: "vad")
    static let link = Logger(subsystem: "echo", category: "link")
    static let pipe = Logger(subsystem: "echo", category: "pipeline")
}
