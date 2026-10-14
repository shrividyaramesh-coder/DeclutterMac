import Foundation
import ServiceManagement

/// Manages registration and lifecycle of the background cleanup LaunchAgent daemon.
public final class LaunchAgentManager: Sendable {
    public static let shared = LaunchAgentManager()
    
    public static let agentLabel = "com.tidymac.cleanup"
    public static let plistFileName = "\(agentLabel).plist"
    
    private init() {}
    
    /// Target path for the user's LaunchAgents directory.
    public var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }
    
    /// Target file URL for the Tidy Mac LaunchAgent plist.
    public var plistFileURL: URL {
        launchAgentsDirectory.appendingPathComponent(Self.plistFileName)
    }
    
    /// Path to Tidy Mac log directory.
    public var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TidyMac")
    }
    
    /// Checks if the LaunchAgent plist is currently installed on disk.
    public func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistFileURL.path)
    }
    
    /// Generates a valid XML Property List string for launchd.
    public func generatePlistContent(executableURL: URL, frequency: ScheduleFrequency) -> String {
        let intervalSeconds: Int
        switch frequency {
        case .daily:
            intervalSeconds = 86400
        case .weekly:
            intervalSeconds = 604800
        case .monthly:
            intervalSeconds = 2592000
        case .onLowDiskSpace:
            // For low disk space monitoring, launchd polls every 15 minutes (900 seconds)
            intervalSeconds = 900
        }
        
        let stdoutLog = logsDirectory.appendingPathComponent("stdout.log").path
        let stderrLog = logsDirectory.appendingPathComponent("stderr.log").path
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.agentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executableURL.path)</string>
                <string>--scheduled-run</string>
            </array>
            <key>StartInterval</key>
            <integer>\(intervalSeconds)</integer>
            <key>RunAtLoad</key>
            <false/>
            <key>ProcessType</key>
            <string>Background</string>
            <key>LowPriorityIO</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(stdoutLog)</string>
            <key>StandardErrorPath</key>
            <string>\(stderrLog)</string>
        </dict>
        </plist>
        """
    }
    
    /// Installs and loads the LaunchAgent for the given executable and frequency.
    @discardableResult
    public func install(executableURL: URL, frequency: ScheduleFrequency) throws -> URL {
        let fileManager = FileManager.default
        
        // Ensure parent directories exist
        if !fileManager.fileExists(atPath: launchAgentsDirectory.path) {
            try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: logsDirectory.path) {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }
        
        let plistString = generatePlistContent(executableURL: executableURL, frequency: frequency)
        try plistString.write(to: plistFileURL, atomically: true, encoding: .utf8)
        
        // Unload existing if loaded
        unloadLaunchAgent()
        // Load into launchctl
        loadLaunchAgent()
        
        return plistFileURL
    }
    
    /// Uninstalls and unloads the LaunchAgent.
    public func uninstall() {
        unloadLaunchAgent()
        try? FileManager.default.removeItem(at: plistFileURL)
    }
    
    /// Unloads the agent via launchctl.
    private func unloadLaunchAgent() {
        guard FileManager.default.fileExists(atPath: plistFileURL.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistFileURL.path]
        try? process.run()
        process.waitUntilExit()
    }
    
    /// Loads the agent via launchctl.
    private func loadLaunchAgent() {
        guard FileManager.default.fileExists(atPath: plistFileURL.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistFileURL.path]
        try? process.run()
        process.waitUntilExit()
    }
}
