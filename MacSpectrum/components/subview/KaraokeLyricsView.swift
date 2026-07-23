//
//  Untitled.swift
//  ISpectrum
//
//  Created by 郭鹏 on 2026/6/13.
//

import SwiftUI

struct KaraokeLyricsView: View {
    // 💉 注入您的播放管理器，用来监听 currentTime 和当前正在放的歌
    @ObservedObject var player: PlayerManager
    
    @ObservedObject var lyricManager: LyricManager
    
    @ObservedObject var palette: PaletteManager
    
//    var onClick: (() -> Void)
    // 📝 动态查出当前高亮歌词在整首歌里的“第几行”（从 0 开始计数）
    private var currentIndex: Int {
        // 1. 安全检查：如果歌词数组空了，或者当前没有高亮的 LineId，直接判为第 0 行
        guard !allLyrics.isEmpty, let currentId = lyricManager.currentLineId else {
            return 0
        }
        
        // 2. 🎯 【核心对齐】：在整个歌词数组里，找出哪一行的 id 刚好等于当前的 currentId
        // firstIndex(where:) 会返回它在数组里的真实下标数字（比如第 12 句就会返回 11）
        if let index = allLyrics.firstIndex(where: { $0.id == currentId }) {
            return index
        }
        
        return 0 // 容错打底
    }
    
    // 📜 假定您的 LyricManager 解析出来的所有歌词纯文本数组 [String]
    private var allLyrics: [LyricLine] {
        // 这里获取整首歌的歌词数组，如果为空就返回空数组
        return lyricManager.lyrics
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // -----------------------------------------------------------
            // 🎤 第一行：左对齐车道（负责 1, 3, 5, 7... 单数句）
            // -----------------------------------------------------------
            HStack {
                Text(getLyricText(forLine: .odd))
                    .font(.system(size: 40, weight: /*isLineActive(.odd) ? .bold : */.medium, design: .rounded))
                    .foregroundColor(
                        /*isLineActive(.odd) ? .orange : */palette.bgPalette
                    ) // 激活时变亮（比如橙色），未激活时半透明
//                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
                Spacer() // 🎯 强行左对齐
            }
            .padding(.leading, 40) // 左边留出体面的呼吸感空间
            
            // -----------------------------------------------------------
            // 🎤 第二行：右对齐车道（负责 2, 4, 6, 8... 双数句）
            // -----------------------------------------------------------
            HStack {
                Spacer() // 🎯 强行右对齐
                Text(getLyricText(forLine: .even))
                    .font(.system(size: 40, weight: /*isLineActive(.even) ? .bold : */.medium, design: .rounded))
                    .foregroundColor(/*isLineActive(.even) ? .orange : */palette.bgPalette)
//                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
            }
            .padding(.trailing, 40) // 右边留出对称的空间
        }
        .onAppear {
            if let title = player.currentSong?.title {
                lyricManager.loadLyric(for: title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 切歌同步监听
        .onChange(of: player.currentSong?.id) {
            // 只要 ID 变了，说明切歌了，我们直接通过 player 拿到最新的 title 塞进去！
            if let song = player.currentSong {
                lyricManager.loadLyric(for: song.title)
            }
        }
        // ⏱️ 高频毫秒进度监听（在大排灯的主计时器里轮询触发即可，或者直接绑定进度状态）
        .onChange(of: player.currentTime) { _, newTime in
            lyricManager.updateCurrentLine(currentTime: newTime)
        }
    }
    
    // 判定当前行是不是正在唱的那一行
    private func isLineActive(_ type: LineType) -> Bool {
        if allLyrics.isEmpty { return false }
        // 索引 0 是第一句（单数），索引 1 是第二句（双数），以此类推
        let isCurrentEven = currentIndex % 2 == 1
        return type == .even ? isCurrentEven : !isCurrentEven
    }
    
    // 智能获取两行各自该显示的文本（含预加载下一句的魔法）
    private func getLyricText(forLine type: LineType) -> String {
        guard !allLyrics.isEmpty else { return "                                " }
        
        let isCurrentEven = currentIndex % 2 == 1
        
        switch type {
            case .odd:
                if !isCurrentEven {
                    // 当前正唱到单数句，直接显示它
                    return allLyrics[currentIndex].text
                } else {
                    // 当前唱到双数句了！那第一行（单数行）不能空着，它要提前预加载“下一句”！
                    let nextIndex = currentIndex + 1
                    return nextIndex < allLyrics.count ? allLyrics[nextIndex].text : ""
                }
                
            case .even:
                if isCurrentEven {
                    // 当前正唱到双数句，直接显示它
                    return allLyrics[currentIndex].text
                } else {
                    // 当前唱到单数句！那第二行（双数行）提前预加载显示再下一句！
                    let nextIndex = currentIndex + 1
                    return nextIndex < allLyrics.count ? allLyrics[nextIndex].text : ""
                }
        }
    }
}
