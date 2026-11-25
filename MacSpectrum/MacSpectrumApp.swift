//
//  MacSpectrumApp.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/13.
//

import SwiftUI

@main
struct MacSpectrumApp: App {
    // 🚀 全局唯一的指挥官单例
    @StateObject private var player: PlayerManager

    @StateObject private var lyric: LyricManager
    
    @StateObject private var palette = PaletteManager()
    
    let songsURL: URL
    let lyricsURL: URL
    
    init() {
        let fileManager = FileManager.default
        let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // 动态构建通用路径：~/Documents/spectrumplayer/songs & lyrics
        let baseFolder = docURL.appendingPathComponent("spectrumplayer", isDirectory: true)
        
        let songsDir   = baseFolder.appendingPathComponent("songs", isDirectory: true)
        let lyricsDir  = baseFolder.appendingPathComponent("lyrics", isDirectory: true)
        
        self.songsURL = songsDir
        self.lyricsURL = lyricsDir
        
        // 初始化 PlayerManager，把准备好的路径喂给它
        self._player = StateObject(wrappedValue: PlayerManager(songsURL: songsDir, lyricsURL: lyricsDir))

        self._lyric = StateObject(wrappedValue: LyricManager(path: lyricsDir.path))

        // 🔤 把外部明朝体字面的解析/注册挡在启动阶段：它要读字体目录并注册 9MB 的 ttf，
        // 几十毫秒，不该发生在第一首日文歌的歌词上屏那一刻。
        LyricFontPolicy.prewarm()

    }
    
    var body: some Scene {
        WindowGroup {
            // 🚀 核心关键：必须把这个唯一的 player 和 palette 实体，通过参数强行喂给 MainPlayerView！
            MainPlayerView(
                player: player,
                palette: palette,
                lyricManager: lyric
            )
                .environmentObject(player)
                .environmentObject(palette)
                .environmentObject(lyric)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .windowSize) { }
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .toolbar) { }
        }
        
        // ── 🏝️ Mac 专属状态任务栏（保持昨天的精致縮小版不变） ──
        // ⚠️ 路由与主题切换限制：主题切换（魔幻光柱/动感圈圈 + Cmd+T）只在 NowPlayingView 内有效，
        // 故在主视图/极简模式下置灰；极简、卡啦OK 则相反，进入 NowPlayingView 后置灰。
        MenuBarExtra {
            // 📍 页路由：从主视图进入正在播放页（与 Cmd+N 同一入口，置灰条件保持一致）。
            Button("正在播放") {
                player.nowPlayingShown = true
            }
            .disabled(player.isAutopilotMode || player.nowPlayingShown)
            
            Divider()
            
            Toggle(isOn: $player.isAutopilotMode) {
                Text("极简模式")
            }
            .disabled(player.nowPlayingShown)
            Toggle(isOn: $player.karaoke) {
                Text("卡啦OK")
            }
            .disabled(!player.isAutopilotMode || player.nowPlayingShown)
            
            Divider()
            
            // 🎚️ 主题切换：与 Cmd+T 完全对齐 —— 主视图与正在播放页都可用，仅极简模式下置灰。
            // 以前锁在 nowPlayingShown 里，因为当时主界面只能黑底；现在两页共用同一套主题。
            // 文案不再叫「动感圈圈/魔幻光柱」：那两个名字描述的是正在播放页的唱片与光柱，
            // 主界面用它们会对不上。改按目标状态命名：当前是白就给【酷黑】，反之给【纯白】。
            Button(action: {
                if player.themeType == "black" {
                    player.themeType = "white"
                    player.standardTheme = false
                } else {
                    player.themeType = "black"
                    player.standardTheme = true
                }
            }) {
                HStack {
                    Text(player.themeType == "black" ? "纯白" : "酷黑")
                }
            }
            .disabled(player.isAutopilotMode)
            
            Divider()
            
            Button("退出 macSpectrum") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            
        } label: {
            if let originalImg = player.albumImages.first,
               let tinyIcon = resizeImage(image: originalImg, targetSize: NSSize(width: 22, height: 22), isAppIcon: false) {
                Image(nsImage: tinyIcon)
            } else {
                defaultAppIconPlaceholder
            }
        }
    }
    
    private var defaultAppIconPlaceholder: some View {
        Group {
            if let rawAppIcon = NSApplication.shared.applicationIconImage,
               let tinyAppIcon = resizeImage(image: rawAppIcon, targetSize: NSSize(width: 22, height: 22), isAppIcon: true) {
                Image(nsImage: tinyAppIcon)
            } else {
                Image(systemName: "waveform.path.ecg")
            }
        }
    }
    
    private func resizeImage(image: NSImage, targetSize: NSSize, isAppIcon: Bool) -> NSImage? {
        if isAppIcon {
            let targetRect = NSRect(origin: .zero, size: NSSize(width: 32, height: 32))
            if let rep = image.bestRepresentation(for: targetRect, context: nil, hints: nil) {
                let matchedImage = NSImage(size: rep.size)
                matchedImage.addRepresentation(rep)
                return scaleAndClipImage(matchedImage, to: targetSize, cornerRadius: 4)
            }
        }
        return scaleAndClipImage(image, to: targetSize, cornerRadius: 3)
    }
    
    private func scaleAndClipImage(_ image: NSImage, to targetSize: NSSize, cornerRadius: CGFloat) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        let rect = NSRect(origin: .zero, size: targetSize)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
