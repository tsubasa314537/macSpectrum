import Foundation
import AVFoundation
import Accelerate
import Combine
import CoreAudio

class AudioManager: ObservableObject {
    
    private let fftSize   = 2048
    private let bandCount = 32
    private var fftSetup: FFTSetup?
    
    private var playerNode: AVAudioPlayerNode?
    
    private var smoothContrastScale: Float = 1.0
    
    // ── 双声道各自维护独立的环形缓冲区和峰值 ──────────────────────
    
    private var totalSamples: Int = 0
    private var ringBufferL: [Float]
    private var ringBufferR: [Float]
    private var prevBands: [Float]
    private var writeIndex: Int = 0
    
    private var peakL: Float = 1e-6
    private var peakR: Float = 1e-6
    private let peakDecay: Float = 0.9995
    
    private var currentSampleRate: Float = 44100
    
    // ── dB 映射参数 ───────────────────────────────────────────────
    private let noiseFloorDB: Float = -60.0
    private let ceilingDB:    Float = -6.0
    
    private var energies: [Float]
    private var result: [Float]
    
    // ── Attack / Release ─────────────────────────────────────────
    private let attack:  Float = 1.0
    private let release: Float = 0.2
    //基准值：1.4/0.3
    
    // ── 输出：左右各 48 个频段 ────────────────────────────────────
    @Published var leftMagnitudes:  [Float]
    @Published var rightMagnitudes: [Float]
    
    // 💾 【新增消噪沙盒】：用来死死记住上一帧光柱停留在屏幕上的真实渲染高度
    private var lastLeftRender:  [Float]
    private var lastRightRender: [Float]
    
    
//    var isTriggered: Bool = false
//    var triggerValue: Float = 0.0 // 👈 这个值可以传给 UI 驱动全局闪烁或鼓点爆炸动效
    
    
    init() {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        result   = [Float](repeating: 0, count: bandCount)
        energies = [Float](repeating: 0, count: bandCount)
        
        leftMagnitudes = Array(repeating: 0, count: bandCount)
        rightMagnitudes = Array(repeating: 0, count: bandCount)
        
        lastLeftRender = Array(repeating: 0, count: bandCount)
        lastRightRender = Array(repeating: 0, count: bandCount)
        
        //初始化时一次分配
        ringBufferL = Array(repeating: 0, count: fftSize)
        ringBufferR = Array(repeating: 0, count: fftSize)
        prevBands = Array(repeating: 0, count: fftSize)
        
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }
    
    func installTap(on mixer: AVAudioMixerNode) {
        
        let format = mixer.outputFormat(forBus: 0)
        
        mixer.removeTap(onBus: 0)
        
        mixer.installTap(onBus: 0,
                         //在一个fft窗口周期内回调4次
                         bufferSize: AVAudioFrameCount(fftSize / 4),
                         format: format) { [weak self] buffer, _ in
            self?.processAudio(buffer: buffer,
                               channelCount: Int(format.channelCount))
        }
    }
    
    // MARK: - 音频处理（回调线程）
    private func processAudio(buffer: AVAudioPCMBuffer, channelCount: Int) {
        guard let data = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        currentSampleRate = Float(buffer.format.sampleRate)
        
        for i in 0..<frameCount {
            ringBufferL[writeIndex] = data[0][i]
            ringBufferR[writeIndex] = channelCount >= 2 ? data[1][i] : data[0][i]
            writeIndex = (writeIndex + 1) % fftSize
        }
        
        totalSamples += frameCount
        if totalSamples < fftSize { return }
        
        var samplesL = [Float](repeating: 0, count: fftSize)
        var samplesR = [Float](repeating: 0, count: fftSize)
        let tailCount = fftSize - writeIndex
        samplesL[0..<tailCount] = ringBufferL[writeIndex..<fftSize]
        samplesR[0..<tailCount] = ringBufferR[writeIndex..<fftSize]
        samplesL[tailCount..<fftSize] = ringBufferL[0..<writeIndex]
        samplesR[tailCount..<fftSize] = ringBufferR[0..<writeIndex]
        
        let magsL = computeFFT(samples: samplesL)
        let magsR = computeFFT(samples: samplesR)
        
        let prevL = leftMagnitudes
        let prevR = rightMagnitudes
    
        let rawBandsL = computeBands(
            rawMags: magsL,
            previous: prevL,
            peak: &peakL
            //            triggered: isRealtimeKickTriggered
        )
        let rawBandsR = computeBands(
            rawMags: magsR,
            previous: prevR,
            peak: &peakR
            //            triggered: isRealtimeKickTriggered
        )
        
//        let currentTrigger = self.triggerValue
        
        lastLeftRender  = rawBandsL
        lastRightRender = rawBandsR
        
        // ── 统一打包派发给主线程 ──────────────────────────────────────────
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.leftMagnitudes = lastLeftRender
            self.rightMagnitudes = lastRightRender
        }
    }
    
    // MARK: - FFT
    private func computeFFT(samples: [Float]) -> [Float] {
        guard let setup = fftSetup else { return [] }
        
        let halfSize = fftSize / 2
        let log2n    = vDSP_Length(log2(Float(fftSize)))
        
        // Hann 窗
        var windowed = [Float](repeating: 0, count: fftSize)
        var window   = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        
        var real  = [Float](repeating: 0, count: halfSize)
        var imag  = [Float](repeating: 0, count: halfSize)
        var split = DSPSplitComplex(realp: &real, imagp: &imag)
        
        windowed.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(halfSize))
            }
        }
        
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        
        var mags: [Float] = [Float](repeating: 0, count: halfSize)
        vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(halfSize))
        
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(mags, 1, &scale, &mags, 1, vDSP_Length(halfSize))
        
        return mags
    }
    
    // 🎼 宏观抗噪 - 自适应高斯能量提取
    private func computeGaussianEnergy(
        centerBand: Int,
        rawMags: [Float],
        minFreq: Float,
        maxFreq: Float
    ) -> Float {
        let leftBand  = max(0, centerBand - 1)
        let rightBand = min(bandCount - 1, centerBand + 1)
        
        let (bStart, _) = bins(band: leftBand, minFreq: minFreq, maxFreq: maxFreq, sr: currentSampleRate)
        let (_, bEnd)   = bins(band: rightBand, minFreq: minFreq, maxFreq: maxFreq, sr: currentSampleRate)
        
        let centerBin = Float(bStart + bEnd) / 2.0
        let radius = max(Float(bEnd - bStart) / 2.0, 1.0)
        
        let s = max(0, bStart)
        let e = min(bEnd, rawMags.count - 1)
        guard e >= s else { return rawMags[s] }
        
        // 🎯 抗噪平滑：平滑求出当前区域的整体平均能量，避免被单一 bin 噪波干扰
        var sum: Float = 0.0
        for bin in s...e { sum += rawMags[bin] }
        let avg = sum / Float(e - s + 1)
        
        var weightedSum: Float = 0.0
        var weightTotal: Float = 0.0
        
        // 🎯 胖瘦系数平稳收敛在 1.8 ~ 2.8 之间，消灭微观抖动毛刺
        let factor: Float = 2.2
        
        for bin in s...e {
            let dist = (Float(bin) - centerBin) / radius
            let weight = exp(-dist * dist * factor)
            
            weightedSum += rawMags[bin] * weight
            weightTotal += weight
        }
        
        return weightTotal > 0 ? (weightedSum / weightTotal) : 0
    }
    
    // MARK: - 频段计算
    private func computeBands(rawMags: [Float], previous: [Float], peak: inout Float) -> [Float] {
        let minFreq: Float = 45
        let maxFreq: Float = 7500
        
        peak *= peakDecay
        
        var rawValues = [Float](repeating: 0, count: bandCount)
        
        // ── 🥁 1. 预计算低频（0, 1, 2）的平均鼓点爆发力 ──────────────────────────
        var bassEnergySum: Float = 0.0
        for i in 0..<2 {
            let (b1, b2) = bins(band: i, minFreq: minFreq, maxFreq: maxFreq, sr: currentSampleRate)
            let energy = computeEnergy(from: b1, to: b2, in: rawMags)
            let norm = energy / max(peak, 1e-10)
            let dB = log2(max(norm, 1e-10)) * 3.0103
            let mapped = (dB - noiseFloorDB) / (ceilingDB - noiseFloorDB)
            bassEnergySum += min(max(mapped, 0), 1)
        }
        
        let avgBassEnergy = bassEnergySum / 2.0
        let kickThreshold: Float = 0.65
        let kickImpact = max(0, avgBassEnergy - kickThreshold)
        
        for i in 0..<bandCount {
            let energy = computeGaussianEnergy(centerBand: i, rawMags: rawMags, minFreq: minFreq, maxFreq: maxFreq)
            energies[i] = energy
            
            peak = max(peak, energy)
            let normalized = energy / max(peak, 1e-10)
            
            let dB = log2(max(normalized, 1e-10)) * 3.0103
            let mapped = (dB - noiseFloorDB) / (ceilingDB - noiseFloorDB)
            
            let redistributedBass = i >= 3 ? kickImpact : 0.0
            let raw = i >= 3 ? mapped * 0.90 + redistributedBass * 0.85 : mapped
            let prev = previous[i]
            
            let smoothed = raw > prev
            ? prev * (1.0 - attack) + raw * attack
            : prev * release + raw * (1.0 - release)
            
            rawValues[i] = max(0.0, smoothed)
        }
        
        // 🎯 1. 全局动态 Gamma 指数
        let frameAvgEnergy = rawValues.reduce(0, +) / Float(bandCount)
        let dynamicGamma = 1.1 + min(max(frameAvgEnergy * 1.2, 0.0), 0.7)
        
        // 🎯 2. 邻柱自适应去毛刺（Slight Neighbor Anti-Aliasing）
        for i in 0..<bandCount {
            var val = rawValues[i]
            
            if val > 0 {
                val = pow(val, dynamicGamma)
            } else {
                val = 0
            }
            
            if val > 1.0 {
                val = 1.0 + log1p((val - 1.0) * 0.7) * 0.5
            }
            
            // 🚀【核心去毛刺】：仅与左右邻居做 8% 的极微量抗锯齿融合
            // 这样既消除了硬边缘毛刺，又完全不会破坏刺刀的硬度！
            let left = i > 0 ? result[i - 1] : val
            let right = i < bandCount - 1 ? rawValues[i + 1] : val
            
            // 动态抑制：如果当前柱是明显高于左右的尖峰（刺刀），融合度自动降低到 0
            let isPeak = val > left && val > right
            let blendFactor: Float = isPeak ? 0.02 : 0.08
            
            let cleanVal = val * (1.0 - 2.0 * blendFactor) + (left + right) * blendFactor
            
            result[i] = max(0.0, cleanVal)
        }
        
        prevBands = result
        return result
    }
    
    // MARK: - 🚀 升级版：纯正 Mel 声学刻度频段划分（彻底解决低频全抬、重叠问题）
    private func bins(band: Int, minFreq: Float, maxFreq: Float, sr: Float) -> (Int, Int) {
        let minMel = hzToMel(minFreq)
        let maxMel = hzToMel(maxFreq)
        
        let melStart = minMel + (maxMel - minMel) * (Float(band) / Float(bandCount))
        let melEnd   = minMel + (maxMel - minMel) * (Float(band + 1) / Float(bandCount))
        
        let f1 = melToHz(melStart)
        let f2 = melToHz(melEnd)
        
        let b1 = freqToBin(f1, sr: sr)
        var b2 = freqToBin(f2, sr: sr)
        
        // 🎯 核心防死区补丁：如果低频 bin1 == bin2，强制 b2 递增，确保每根柱子都有独立的物理采样点！
        if b2 <= b1 {
            b2 = b1 + 1
        }
        
        return (b1, b2)
    }
    
    // 🎼 Hz 转 Mel 经典声学公式
    private func hzToMel(_ hz: Float) -> Float {
        return 1127.0 * log(1.0 + hz / 700.0)
    }
    
    // 🎼 Mel 转 Hz 还原公式
    private func melToHz(_ mel: Float) -> Float {
        return 700.0 * (exp(mel / 1127.0) - 1.0)
    }
    
    private func freqToBin(_ freq: Float, sr: Float) -> Int {
        let ratio = freq / (sr / 2)
        // 向上取整，并确保至少占据一个物理 bin 窗口，防止低频重叠死区
        return min(max(Int(ceil(ratio * Float(fftSize / 2))), 0), fftSize / 2 - 1)
    }
    
    private func computeEnergy(from start: Int, to end: Int, in mags: [Float]) -> Float {
        let s = max(0, start)
        let e = min(end, mags.count - 1)
        if e <= s { return mags[s] }
        
        var sum: Float = 0
        for i in s...e {
            sum += mags[i]
        }
        
        return sum / Float(e - s + 1)
    }
}
