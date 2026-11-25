//
//  SystemUser.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/11/24.
//

import AppKit
import Foundation

/// 当前登录用户的显示名与头像，给主界面 header 用。
///
/// 名字走 `NSFullUserName()`，公开 API，零成本。
///
/// 头像**没有公开 API**。能走的路子实测过：
/// - `/var/db/dslocal/nodes/Default/users/<short>.plist` 是 root:wheel 600，普通进程读不了；
/// - `/Library/User Pictures/`、`~/Library/User Picture.png` 本机根本不存在；
/// - `dscl . -read /Users/<short> JPEGPhoto` 走目录服务，普通用户读自己的记录是允许的，
///   实测本机免授权直接吐出 hex 串。
/// 所以取头像只能起一次子进程。它是几十毫秒级的阻塞调用，绝不能放在 body 里，
/// 统一走 `avatar()` 这个异步口，由视图的 `.task` 在后台拉。
enum SystemUser {
    static var displayName: String {
        let name = NSFullUserName()
        return name.isEmpty ? NSUserName() : name
    }

    private static var cached: NSImage?
    private static var loaded = false

    /// 一次性读取并缓存。没有设置头像时 dscl 返回 `<NULL>`，这里回 nil，
    /// 由调用方画一个 person.circle.fill 兜底。
    static func avatar() async -> NSImage? {
        if loaded { return cached }
        let image = await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: readAvatar())
            }
        }
        cached = image
        loaded = true
        return image
    }

    private static func readAvatar() -> NSImage? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(NSUserName())", "JPEGPhoto"]
        let pipe = Pipe()
        process.standardOutput = pipe
        // 错误直接丢进黑洞。接一个从不读的 Pipe 等于埋一个同样的死锁点：
        // 一旦 dscl 报错刷屏超过缓冲，它也会阻塞在 write。
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // ⚠️ 顺序不能反过来：先 waitUntilExit 再读管道会死锁。
        // 实测本机 dscl 单次输出 119,847 字节，是 64KB 管道缓冲的将近两倍：
        // dscl 写满管道后阻塞在 write，我们等它退出而阻塞在 waitUntilExit，两边永远互等。
        // readDataToEndOfFile 会持续排空直到子进程关闭描述符，所以它本身就是「等到结束」。
        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let text = String(data: raw, encoding: .ascii)
        else { return nil }

        guard let data = decodeHexAttribute(text) else { return nil }
        return NSImage(data: data)
    }

    /// dscl 的属性输出长这样：属性名一行，后面每 32 字节一行、行首缩进一格、空格分组。
    ///     JPEGPhoto:
    ///      ffd8ffe0 00104a46 49460001 ...
    /// 没有头像时值是 `<NULL>` —— 它不含任何 hex 字符，所以下面的长度门槛会直接把它挡掉。
    private static func decodeHexAttribute(_ text: String) -> Data? {
        let body = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .joined(separator: " ")
        let hex = body.filter { $0.isHexDigit }
        guard hex.count >= 8, hex.count % 2 == 0 else { return nil }

        var data = Data(capacity: hex.count / 2)
        var cursor = hex.startIndex
        while cursor < hex.endIndex {
            let next = hex.index(cursor, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[cursor..<next], radix: 16) {
                data.append(byte)
            }
            cursor = next
        }
        return data.isEmpty ? nil : data
    }
}
