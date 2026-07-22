//
//  OfflineBeatDetector.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/6/18.
//

import Foundation
import AVFoundation
import SoundAnalysis

class OfflineBeatDetector {
    
    var kickTimestamps: [TimeInterval] = []
    var snareTimestamps: [TimeInterval] = []
    
    // 🎯 记住当前正在大声轰鸣的分析器
    private var currentFileAnalyzer: SNAudioFileAnalyzer?
    
    // 🎯 新增：熔断机制。切歌时，强行让前一个后台线程流产！
    func cancelCurrentAnalysis() {
        if let analyzer = currentFileAnalyzer {
            print("🛑 [熔断机制] 侦测到强行切歌，正在无情叫停上一个 AI 分析线程...")
            // 🚨 这一行会直接让后台正在跑的 fileAnalyzer.analyze() 抛出异常并立刻中断！
            analyzer.cancelAnalysis()
            currentFileAnalyzer = nil
        }
        self.kickTimestamps.removeAll()
        self.snareTimestamps.removeAll()
    }
    
    func analyzeSong(fileURL: URL, completion: @escaping ([TimeInterval], [TimeInterval]) -> Void) {
        
        // ── 🚀 【核心手术】：新歌进来第一件事，先把老歌的骨灰给扬了 ──────────────────
        cancelCurrentAnalysis()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
//                print("1. 🛠️ 后台线程开始加载文件: \(fileURL.lastPathComponent)")
                let fileAnalyzer = try SNAudioFileAnalyzer(url: fileURL)
                
                // 必须在同步锁或者确保安全的赋值
                self.currentFileAnalyzer = fileAnalyzer
                
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                
                let observer = OfflineDrumObserver { type, timestamp in
                    // 🎯 加一层安全防护：如果分析器已经被切歌偷偷变质了，直接拒绝写入
                    guard self.currentFileAnalyzer === fileAnalyzer else { return }
                    
                    if type == "drum" {
                        // ── 🎛️ 【大鼓时间量子化】 ──────────────────────────────────
                        // 我们以 6.0 秒为源头，像水滴落入水面一样，向后扩散出 4 发极细的、相隔 375 毫秒（约合160BPM快歌节拍）的黄金卡点！
                        for i in 0..<4 {
                            let microSecond = timestamp + Double(i) * 0.375
                            self.kickTimestamps.append(microSecond)
                        }
                    } else if type == "percussion" {
                        // ── 🎛️ 【镲片时间错位量子化】 ──────────────────────────────
                        // 镲片往往慢半拍（打次中的“次”），我们让它故意错开 187 毫秒起跳，做出绝佳的交错感！
                        for i in 0..<4 {
                            let microSecond = timestamp + 0.187 + Double(i) * 0.375
                            self.snareTimestamps.append(microSecond)
                        }
                    }
                }
                
                try fileAnalyzer.add(request, withObserver: observer)
//                print("2. 🚀 ANE 神经网络狂暴模式开启，开始解析全轨...")
                
                // 🚨 如果外部调用了 cancel()，这一行会直接跳进下面的 catch 块，绝不往下走！
                try fileAnalyzer.analyze()
                
                // 🎯 再次双重检查：确保在分析的这 1 秒钟内，用户没有偷偷又点了一次切歌
                guard self.currentFileAnalyzer === fileAnalyzer else {
//                    print("⚠️ [安全拦截] 虽解析完成，但已朝代更迭，丢弃旧乐谱。")
                    return
                }
                
//                print("3. 🏁 全轨刷完！开始分别排序...")
                let sortedKicks  = self.kickTimestamps.sorted()
                let sortedSnares = self.snareTimestamps.sorted()

//                print("sortedKicks=====\(sortedKicks.count)")
//                print("sortedSnares=====\(sortedSnares.count)")
                
                self.currentFileAnalyzer = nil
                
                DispatchQueue.main.async {
                    completion(sortedKicks, sortedSnares)
                }
                
            } catch {
                // 当被 cancel 强杀时，会安全地走到这里
//                print("ℹ️ 后台盘查线程安全退出/中断: \(error.localizedDescription)")
                self.currentFileAnalyzer = nil
                // 注意：被强杀时不调用 completion，让旧的回调彻底烂在肚子里，不干扰新歌！
            }
        }
    }
}

// 🎯 离线专用接头人
class OfflineDrumObserver: NSObject, SNResultsObserving {
    var onDrumFound: (String, TimeInterval) -> Void
    
    init(onDrumFound: @escaping (String, TimeInterval) -> Void) {
        self.onDrumFound = onDrumFound
    }
    
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }

        if let drum = classificationResult.classification(forIdentifier: "drum") {
//            print("drum===drum.confidence======\(drum.confidence)")
            if drum.confidence > 0.01 {
                let seconds = classificationResult.timeRange.start.seconds
//                print("drum===drum.confidence======\(drum.confidence)")
//                print("drum===start.seconds======\(seconds)")
//                let end = classificationResult.timeRange.end.seconds
//                print("drum===end.seconds======\(end)")
                onDrumFound("drum", seconds)
            }
        }
        
        if let perc = classificationResult.classification(forIdentifier: "percussion") {
//            print("perc===perc.confidence======\(perc.confidence)")
            if perc.confidence > 0.03 {
                let seconds = classificationResult.timeRange.start.seconds
                onDrumFound("percussion", seconds)
            }
        }
    }
}
