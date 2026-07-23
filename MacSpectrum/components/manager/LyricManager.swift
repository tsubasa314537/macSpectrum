//
//  LyricManager.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/6/10.
//

import Combine
import Foundation

class LyricManager: ObservableObject {
    @Published var lyrics: [LyricLine] = []
    @Published var currentLineId: UUID? = nil
    
    let lyricPath: String
    
    init(path: String) {
        lyricPath = path
    }
    
    // 1. 模糊文件名匹配算法
    // 摘除 artist 参数，只用一整条 title 去盘它！
    func loadLyric(for songTitle: String) {
        self.lyrics = [] // 切歌时先清空
        
        let fileManager = FileManager.default
        let lyricsDirectoryURL = URL(fileURLWithPath: lyricPath)
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: lyricsDirectoryURL, includingPropertiesForKeys: nil) //
            
            // 🎯 【字符串立体清洗匹配】
            let matchedURL = fileURLs.first { url in
                // 1. 提取未编码的文件名，并全部转为小写
                let fileName = url.lastPathComponent.lowercased()
                
                // 2. ⚡️【核心解毒剂】：将 Mac 文件系统的 NFD 强制转换为标准 NFC 预组合字符
                let normalizedFileName = fileName.precomposedStringWithCanonicalMapping
                let normalizedSongTitle = songTitle.lowercased().precomposedStringWithCanonicalMapping
                
                // 3. 剔除两边的空格进行模糊包含匹配
                let cleanFileName = normalizedFileName.replacingOccurrences(of: " ", with: "")
                let cleanSongTitle = normalizedSongTitle.replacingOccurrences(of: " ", with: "")
                
                return cleanFileName.contains(cleanSongTitle) //
            }
            
            if let targetURL = matchedURL {
//                print("targetURL======\(targetURL)")
                
                var lyricContent: String? = nil
                
                // 1. 🥇 首先尝试用标准的 UTF-8 读取
                if let utf8Content = try? String(contentsOf: targetURL, encoding: .utf8) {
                    lyricContent = utf8Content
                }
                // 2. 🥈 如果 UTF-8 失败了，立刻启用 GBK (GB18030) 降级全面挽救
                else {
                    // 🎯 构造苹果底层的 GBK / GB18030 编码器
                    let gbkValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                    let gbkEncoding = String.Encoding(rawValue: gbkValue)
                    
                    if let gbkContent = try? String(contentsOf: targetURL, encoding: gbkEncoding) {
//                        print("💡 发现老古董 GBK 编码歌词，已成功自动复活转换！")
                        lyricContent = gbkContent
                    }
                }
                
                // 3. 最终成功拿到内容，送去解析
                if let content = lyricContent {
                    parseLrc(content: content)
                } else {
                    print("❌ 该歌词文件编码既不是 UTF-8 也不是 GBK，彻底没救了。")
                }
            } else {
                print("⚠️ 歌词库中未找到匹配项，当前歌名: \(songTitle)")
            }
        } catch {
            print("读取歌词目录失败，请检查路径是否存在: \(error)") //
        }
    }
    
    // 🔬 2. 高阶时间轴解析器
    func parseLrc(content: String) {
        // 🎯 通杀新老格式的正则
        let pattern = #"\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let nsString = line as NSString
            let range = NSRange(location: 0, length: nsString.length)
            
            // 1. 找出这一行里所有的时间标签（有的歌词一行带多个标签，如 [01:23][02:15] 歌词）
            let matches = regex.matches(in: line, options: [], range: range)
            
            // 2. 提取纯歌词文本（把所有时间标签替换为空）
            let text = regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 3. 遍历提取出来的时间，统一转化为秒数
            for match in matches {
                let minStr = nsString.substring(with: match.range(at: 1))
                let secStr = nsString.substring(with: match.range(at: 2))
                
                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                var fractionSeconds: Double = 0
                
                // ⚖️ 【关键善后】：判断有没有第 3 组（小数点后面的毫秒分量）
                if match.range(at: 3).location != NSNotFound {
                    let msStr = nsString.substring(with: match.range(at: 3))
                    if let msValue = Double(msStr) {
                        // 动态计算位数：如果是 .84 就是 84/100 = 0.84秒；如果是 .8 就是 8/10 = 0.8秒
                        let power = pow(10.0, Double(msStr.count))
                        fractionSeconds = msValue / power
                    }
                }
                
                // 得到最终精准的绝对时间（秒）
                let totalTimeInSeconds = (minutes * 60.0) + seconds + fractionSeconds
                
                // 🚀 接下来放心地塞进您的数组
                 let lrcLine = LyricLine(time: totalTimeInSeconds, text: text)
                 self.lyrics.append(lrcLine)
            }
        }
        
        // 别忘了最后按时间排个序，防止老歌词里有乱序的时间标签
         self.lyrics.sort { $0.time < $1.time }
    }
    // ⏱️ 3. 动态时间轮询锚定
    func updateCurrentLine(currentTime: TimeInterval) {
        guard !lyrics.isEmpty else { return }
        
        // 抓取当前播放时间“之后”的第一行歌词的索引
        let index = lyrics.firstIndex { $0.time > currentTime }
        
        if let nextIndex = index {
            if nextIndex > 0 {
                currentLineId = lyrics[nextIndex - 1].id // 当前正在唱的其实是上一行
            } else {
                currentLineId = lyrics.first?.id
            }
        } else {
            // 如果currentTime已经比最后一行歌词的时间还大，说明在唱最后一句
            currentLineId = lyrics.last?.id
        }
    }
}
