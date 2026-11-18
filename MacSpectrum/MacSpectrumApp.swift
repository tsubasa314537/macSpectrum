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
            
            // 🎚️ 主题切换：与 Cmd+T 完全对齐 —— 仅正在播放页可用，主视图/极简模式下置灰。
            // （nowPlayingShown 与 isAutopilotMode 互斥，故只判 nowPlayingShown 就等价于 Cmd+T 的条件。）
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
                    Text(player.themeType == "black" ? "||| 魔幻光柱" : "OOO 动感圈圈")
//                    Image(systemName: player.themeType == "black" ? "|||" : "OOO")
                }
            }
            .disabled(!player.nowPlayingShown)
            
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
