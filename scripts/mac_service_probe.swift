// Drives one of Die Kartei's Services menu items end to end, without UI or keystrokes: puts the
// text on a private pasteboard, asks the system to perform the service, prints what came back.
//
//   swift scripts/mac_service_probe.swift "Auf Deutsch (Sie)" "Hi Anna, can we move our call to Thursday?"
//
// `changed=false` means the provider wrote nothing (it turned the request away or fell back to the
// Schreibhilfe panel), and the pasteboard still holds the input. See docs/MACOS.md ▸ Schreibhilfe.
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: mac_service_probe.swift <service title> <text>\n".utf8))
    exit(2)
}

_ = NSApplication.shared
let pasteboard = NSPasteboard.withUniqueName()
pasteboard.clearContents()
pasteboard.setString(args[1], forType: .string)
let before = pasteboard.changeCount
let started = Date()

let ok = NSPerformService(args[0], pasteboard)

let seconds = Date().timeIntervalSince(started)
print("ok=\(ok) changed=\(pasteboard.changeCount != before) \(String(format: "%.1f", seconds))s")
print(pasteboard.string(forType: .string) ?? "<none>")
pasteboard.releaseGlobally()
