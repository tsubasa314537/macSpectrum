//
//  EdgeFadeMask.swift
//  MacSpectrum
//
//  视口上下两端的 alpha 渐隐遮罩。目前给歌词墙用。
//

import SwiftUI

// MARK: - 视口上下渐隐遮罩

/// 把视图上下两端按 alpha 渐隐掉，中间保持完全不透明。用作 `.mask` 的内容。
///
/// 两个带子**不等宽**（top 104 > bottom 78）：歌词是往上走的，离开视线的那一句需要
/// "一点一点"退场，所以上面的过渡要长；而从下面进来的那一句马上就要被读，
/// 渐隐带拖长了反而像没对上焦。
///
/// 带子内部也不是线性斜坡：在 45% 处先压一个 0.08 的中间档，让起头那一段几乎看不见、
/// 后面才快速升起。线性渐隐在文字上会读成"上面盖了块磨砂板"，带缓度的才读成"远处失焦"。
///
/// ⚠️ 只能加在**视口**（ScrollView 本身）上，不能加在它的内容上——加在内容上，
/// 渐隐带会跟着文字一起滚走，等于没加。
struct EdgeFadeMask: View {
    /// 顶部渐隐带高度（pt）
    var top: CGFloat
    /// 底部渐隐带高度（pt）
    var bottom: CGFloat

    /// 视口被压矮时的保护：单侧渐隐带最多吃掉这么多高度，
    /// 否则上下带相接，中间的可读区会被完全封死。
    private let maxShare: CGFloat = 0.40

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let t = min(top, h * maxShare) / h
            let b = min(bottom, h * maxShare) / h

            LinearGradient(
                stops: [
                    .init(color: .clear,                   location: 0),
                    .init(color: .white.opacity(0.08),     location: t * 0.45),
                    .init(color: .white,                   location: t),
                    .init(color: .white,                   location: 1 - b),
                    .init(color: .white.opacity(0.08),     location: 1 - b * 0.45),
                    .init(color: .clear,                   location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
