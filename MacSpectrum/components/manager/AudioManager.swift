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
    
//    private var smoothContrastScale: Float = 1.0
    
    // ── 双声道各自维护独立的环形缓冲区和峰值 ──────────────────────
    private var lastUIUpdateTime: Double = 0
    
    private var totalSamples: Int = 0
    private var ringBufferL: [Float]
    private var ringBufferR: [Float]
    private var prevBands: [Float]
    private var writeIndex: Int = 0
    
    private var peakL: Float = 1e-6
    private var peakR: Float = 1e-6
    private let peakDecay: Float = 0.9995
    
    private var currentSampleRate: Float = 44100
    
    // ── 🚀 内存优化：预分配 FFT 临时缓存与 Hann 窗，避免回调线程频繁 GC ─────────────
    private var window: [Float]
    private var samplesL: [Float]
    private var samplesR: [Float]
    
    // ── dB 映射参数 ───────────────────────────────────────────────
    private let noiseFloorDB: Float = -60.0
    private let ceilingDB:    Float = -6.0
    
    private var energies: [Float]
    private var result: [Float]
    
    // ── Attack / Release ─────────────────────────────────────────
    private let attack:  Float = 1.0
    private let release: Float = 0.2
    
    // ── 输出：左右各 32 个频段 ────────────────────────────────────
    @Published var leftMagnitudes:  [Float]
    @Published var rightMagnitudes: [Float]
    
    private var lastLeftRender:  [Float]
    private var lastRightRender: [Float]
    
    init() {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        result   = [Float](repeating: 0, count: bandCount)
        energies = [Float](repeating: 0, count: bandCount)
        
        leftMagnitudes = Array(repeating: 0, count: bandCount)
        rightMagnitudes = Array(repeating: 0, count: bandCount)
        
        lastLeftRender = Array(repeating: 0, count: bandCount)
        lastRightRender = Array(repeating: 0, count: bandCount)
        
        ringBufferL = Array(repeating: 0, count: fftSize)
        ringBufferR = Array(repeating: 0, count: fftSize)
        prevBands = Array(repeating: 0, count: fftSize)
        
        // 🚀 预分配与预计算
        samplesL = Array(repeating: 0, count: fftSize)
        samplesR = Array(repeating: 0, count: fftSize)
        window   = Array(repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }
    
    func installTap(on mixer: AVAudioMixerNode) {
        let format = mixer.outputFormat(forBus: 0)
        mixer.removeTap(onBus: 0)
        
        mixer.installTap(onBus: 0,
                         bufferSize: AVAudioFrameCount(fftSize / 4),
                         format: format) { [weak self] buffer, _ in
            self?.processAudio(buffer: buffer, channelCount: Int(format.channelCount))
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
        
        // 🚀 直接重用全局预分配的缓存，不重新初始化数组
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
        )
        let rawBandsR = computeBands(
            rawMags: magsR,
            previous: prevR,
            peak: &peakR
        )
        
        lastLeftRender  = rawBandsL
        lastRightRender = rawBandsR
        
        let currentTime = CACurrentMediaTime()
        // 🚀【核心节流】：限制最多每秒刷 60 次（约 0.016 秒），避免音频回调（每秒 86+ 次）把主线程塞爆
        if currentTime - lastUIUpdateTime >= 0.02 {
            lastUIUpdateTime = currentTime
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.leftMagnitudes = self.lastLeftRender
                self.rightMagnitudes = self.lastRightRender
            }
        }
    }
    
    // MARK: - FFT
    private func computeFFT(samples: [Float]) -> [Float] {
        guard let setup = fftSetup else { return [] }
        
        let halfSize = fftSize / 2
        let log2n    = vDSP_Length(log2(Float(fftSize)))
        
        var windowed = [Float](repeating: 0, count: fftSize)
        // 🚀 复用预存的 Hann 窗
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
        let radius = Float(bEnd - bStart) / 2.0
        
        let s = max(0, bStart)
        let e = min(bEnd, rawMags.count - 1)
        guard e >= s else { return rawMags[s] }
        
        var weightedSum: Float = 0.0
        var weightTotal: Float = 0.0
        
        for bin in s...e {
            let dist = (Float(bin) - centerBin) / radius
            let weight = exp(-dist * dist)
            
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
            
            let redistributedBass = i >= 2 ? kickImpact : 0.0
            
            var raw = Float(0.0)
            if mapped < 0.32 {
                raw = mapped * 0.88 + redistributedBass * 0.55
            } else {
                if mapped > 0.65 {
                    let delta = mapped - 0.65
                    raw = 0.65 + delta + pow(delta, 1.2) * 0.44
//                    if raw > 1.0 {
//                        raw = 1.0 + log1p((raw - 1.0) * 0.7) * 0.72
//                    }
                } else {
                    raw = mapped
                }
//            } else {
//                raw = mapped
            }
            
            let prev = previous[i]
            let smoothed = raw * 0.98 + prev * 0.02
            
            
//            let smoothed = raw > prev
//            ? prev * (1.0 - attack) + raw * attack
//            : prev * release + raw * (1.0 - release)
            
            rawValues[i] = max(0.0, smoothed)
        }
        
        // 🚀 修正对称去毛刺：使用临时的 finalBands，保证左右计算平等的未平滑原值
        var finalBands = [Float](repeating: 0, count: bandCount)
        for i in 0..<bandCount {
            var val = rawValues[i]
            
            if val > 1.0 {
                val = 1.0 + log1p((val - 1.0) * 0.7) * 0.72
            }
            
            let left = i > 0 ? rawValues[i - 1] : val
            let right = i < bandCount - 1 ? rawValues[i + 1] : val
            
            let isPeak = val > left && val > right
            let blendFactor: Float = isPeak ? 0.02 : 0.08
            
            let cleanVal = val * (1.0 - 2.0 * blendFactor) + (left + right) * blendFactor
            
            finalBands[i] = max(0.0, cleanVal)
        }
        
        result = finalBands
        prevBands = result
        return result
    }
    
    private func bins(band: Int, minFreq: Float, maxFreq: Float, sr: Float) -> (Int, Int) {
        let minMel = hzToMel(minFreq)
        let maxMel = hzToMel(maxFreq)
        
        let melStart = minMel + (maxMel - minMel) * (Float(band) / Float(bandCount))
        let melEnd   = minMel + (maxMel - minMel) * (Float(band + 1) / Float(bandCount))
        
        let f1 = melToHz(melStart)
        let f2 = melToHz(melEnd)
        
        let b1 = freqToBin(f1, sr: sr)
        var b2 = freqToBin(f2, sr: sr)
        
        if b2 <= b1 {
            b2 = b1 + 1
        }
        
        return (b1, b2)
    }
    
    private func hzToMel(_ hz: Float) -> Float {
        return 1127.0 * log(1.0 + hz / 700.0)
    }
    
    private func melToHz(_ mel: Float) -> Float {
        return 700.0 * (exp(mel / 1127.0) - 1.0)
    }
    
    private func freqToBin(_ freq: Float, sr: Float) -> Int {
        let ratio = freq / (sr / 2)
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
