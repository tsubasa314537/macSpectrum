//
//  OfflineAudioOnsetDetector.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/6/18.
//

import Foundation
import AVFoundation
import Accelerate

class OfflineAudioOnsetDetector {
    
    var preciseKickTimestamps: [TimeInterval] = []
    
    func analyzeSongFile(fileURL: URL, completion: @escaping ([TimeInterval]) -> Void) {
        self.preciseKickTimestamps.removeAll()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // 1. 读取音频文件基本信息
                let audioFile = try AVAudioFile(forReading: fileURL)
                let format = audioFile.processingFormat
                let sampleRate = format.sampleRate
                let totalFrames = audioFile.length
                
                // 🎯 优化核心 A：把整首歌的所有采样点，一次性全部吞进内存大 Buffer！
                // 彻底消灭 while 循环里几十万次高频读取磁盘的 I/O 恶梦
                guard let fullBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
                    completion([])
                    return
                }
                try audioFile.read(into: fullBuffer, frameCount: AVAudioFrameCount(totalFrames))
                guard let channelData = fullBuffer.floatChannelData else { completion([]); return }
                
                let frameSize = 256
                let hopSize = 64
                let hasStereo = format.channelCount > 1
                
                // 🎯 优化核心 B：提前把左右声道的大指针准备好，在连续内存上全速前进
                let leftChannel = channelData[0]
                let rightChannel = hasStereo ? channelData[1] : channelData[0]
                
                var localTimestamps: [TimeInterval] = []
                var previousDB: Float = -120.0
                var lastTriggerTime: TimeInterval = 0.0
                let cooldownPeriod: TimeInterval = 0.08
                
                // 临时复用车间，避免在循环内部高频分配/销毁数组内存
                var mixedSignal = [Float](repeating: 0, count: frameSize)
                
                // 🚀 在纯内存大平原上进行全速指针滑行（HopSize = 64）
                // 以前跑 10 秒的歌，现在 0.1 秒纯内存计算直接冲到终点！
                var startFrame: Int64 = 0
                let maxStartFrame = totalFrames - Int64(frameSize)
                
                while startFrame < maxStartFrame {
                    let currentSeconds = Double(startFrame) / sampleRate
                    
                    // ⚙️ 1. 高速融合：直接通过指针对齐，取左右声道最大绝对值
                    let offset = Int(startFrame)
                    for s in 0..<frameSize {
                        let lVal = abs(leftChannel[offset + s])
                        let rVal = abs(rightChannel[offset + s])
                        mixedSignal[s] = max(lVal, rVal)
                    }
                    
                    // ⚙️ 2. 真实物理 RMS 分贝换算
                    var rmsValue: Float = 0.0
                    vDSP_rmsqv(mixedSignal, 1, &rmsValue, vDSP_Length(frameSize))
                    let currentDB = 20.0 * log10(max(rmsValue, 1e-6))
                    
                    // ── 🎯 暴力美学判定闸 ──────────────────────────────────
                    let deltaDB = currentDB - previousDB
                    
                    if /*deltaDB > 3.0 &&*/ currentDB >= -6.0 {
                        if currentSeconds - lastTriggerTime >= cooldownPeriod {
                            localTimestamps.append(currentSeconds)
//                            print("currentDB=======\(currentDB), currentSeconds=========\(currentSeconds)")
                            lastTriggerTime = currentSeconds
                        }
                    }
                    
                    previousDB = currentDB
                    
                    // 🎯 密网指针全速向前推进 64 个采样点
                    startFrame += Int64(hopSize)
                }
                
                self.preciseKickTimestamps = localTimestamps.sorted()
                
                DispatchQueue.main.async {
                    completion(self.preciseKickTimestamps)
                }
                
            } catch {
                print("🚨 离线音频读取失败: \(error)")
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
}
