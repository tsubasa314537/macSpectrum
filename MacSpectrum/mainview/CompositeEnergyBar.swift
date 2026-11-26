//
//  CompositeEnergyBar.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/7/21.
//

import SwiftUI

// MARK
//
// 把「三角形针尖 + 椭圆肚子」合并成**一条 path**。
//
// 为什么要合并：旧实现是 RoundedRectangle(针) + 两层 Ellipse.stroke(腰腹) 用 padding 硬算位置拼起来的，
// 能量一跳、两个几何量的换算不同步，针和圈之间就直接断开——这就是"断线"的根因。
// 现在针腿的落点直接用椭圆的参数方程算出（同一个 phiStart / rx / ry），两者共用一套几何量，
// 接缝在数学上就是同一点，所以不可能再断开。
// 标为 internal（而不是 private）是为了能被离屏渲染工具单独拉出来验几何。
struct EnergySpindle: Shape {
    /// 0...1 肚子鼓出程度，直接由能量驱动（做成可动画属性，配合下面的 .linear interpolation）
    var bulge: CGFloat
    /// 针腿落在椭圆上的位相角（弧度，0 = 椭圆顶点）：越大针腿越宽、针越粗
    var phiStart: CGFloat = 0.65
    /// 椭圆半高占整根柱子的比例：0.38 → 肚子 76%，针尖 24%
    var bellyHeightRatio: CGFloat = 0.35
    /// 针腿内凹程度：0 是直线（纯三角针），越大越像一根头发。取小值保持“针”的量感。
    var legTuck: CGFloat = 0.35

    var animatableData: CGFloat {
        get { bulge }
        set { bulge = newValue }
    }

    /// 椭圆上参数 phi 处的点：phi=0 顶点，π/2 最右，π 底，3π/2 最左
    private func point(_ phi: CGFloat, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPoint {
        CGPoint(x: cx + rx * sin(phi), y: cy - ry * cos(phi))
    }

    /// 椭圆弧的三次近似：k = 4/3·tan(Δφ/4)，端点切线 (rx·cosφ, ry·sinφ)
    /// 这是画椭圆用的标准常数，比用好几段 quad 拼要准，而且接缝处曲率连续。
    private func arc(_ p: inout Path, from phi0: CGFloat, to phi1: CGFloat,
                     _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        let k = (4.0 / 3.0) * tan((phi1 - phi0) / 4.0)
        let a = point(phi0, cx, cy, rx, ry)
        let b = point(phi1, cx, cy, rx, ry)
        p.addCurve(
            to: b,
            control1: CGPoint(x: a.x + rx * cos(phi0) * k, y: a.y + ry * sin(phi0) * k),
            control2: CGPoint(x: b.x - rx * cos(phi1) * k, y: b.y - ry * sin(phi1) * k)
        )
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height
        guard h > 2 else { return p }

        let cx = rect.midX
        let bottom = rect.maxY
        let top = rect.minY

        // 半宽：上限 ~0.68 rect.width。真实槽宽 = barWidth + spacing = 16，最宽 13 仍不碰邻柱。
        let rx = rect.width * (0.22 + bulge * 0.46)
        // 椭圆就是主体：肚子拿 76% 高度，针尖拿剩下 24%。
        // （6pt 宽的柱子不可能有“圆胖”的肚子，上一版把 ry 限在 1.2rx 以内，结果成了图钉。）
        // 能量在这里的作用是“变宽”而不是“变长”，所以鼓肚子能单独被看出来。
        let ry = h * bellyHeightRatio
        let cy = bottom - ry

        // ── 针尖 → 右针腿 ──
        // 针腿直接落在椭圆弧上（同一个 phiStart 算出的点），所以两者天然无缝，不存在对齐问题。
        let right = point(phiStart, cx, cy, rx, ry)
        p.move(to: CGPoint(x: cx, y: top))
        p.addQuadCurve(
            to: right,
            control: CGPoint(x: cx + rx * legTuck, y: top + (right.y - top) * 0.50)
        )

        // ── 椭圆：右针腿 → 最右 → 底 → 最左 → 左针腿 ──
        arc(&p, from: phiStart, to: .pi / 2, cx, cy, rx, ry)
        arc(&p, from: .pi / 2, to: .pi, cx, cy, rx, ry)
        arc(&p, from: .pi, to: 3 * .pi / 2, cx, cy, rx, ry)
        arc(&p, from: 3 * .pi / 2, to: 2 * .pi - phiStart, cx, cy, rx, ry)

        // ── 左针腿 → 回到针尖 ──
        p.addQuadCurve(
            to: CGPoint(x: cx, y: top),
            control: CGPoint(x: cx - rx * legTuck, y: top + (right.y - top) * 0.50)
        )

        p.closeSubpath()
        return p
    }
}

struct CompositeEnergyBar: View {
    var height: CGFloat          // 外部算好的总高度
    var intensity: CGFloat       // 能量 (0.0 ~ 1.0)
    var barWidth: CGFloat        // 单元格占位宽度 (6)
    var baseColor: Color         // core：描边 + 柱体根部，承担识别度
    var bellyColor: Color        // 主体：core 按**能量**向 wash 靠拢后的颜色，能量越大越白
    var glowColor: Color         // glow：柔光晕，真 blur 用色

    var maxH: CGFloat
    var minH: CGFloat

    var body: some View {
        let progress = max(0.0, min(1.0, Double((height - minH) / (maxH - minH))))
        // 能量 → 几何：腰腹鼓出程度。留 0.08 的起点，安静时是细针而不是消失。
        let bulge = CGFloat(0.08 + progress * 0.92)
        // 画布宽度随能量放大（肚子要真的鼓出来），但外层占位仍是 barWidth，相邻柱不会被推开。
        let shapeWidth = barWidth * (0.90 + bulge * 0.70)

        // 竖向渐变：椭圆整体吃能量白度，只有针尖锁 core。
        //
        // 两端都锁 core 是上一版的错：能量强的时候，肚子底下还顶着一圈主题色，
        // “越大越白”被根部那圈深色卡住，看着像柱底没化开。现在椭圆（0 → 0.76）
        // 整块都是 bellyColor，能量上去就是整块白下去。
        //
        // 针尖仍锁 core：那是跳动所在，纯白底 + 黄色主题时吃 wash 会和背景同色直接消失。
        // 能量为 0 时 bellyColor 恰好等于 core，所以安静的矮柱依旧是实体色，不会丢“根部扎实”。
        let bodyGradient = LinearGradient(
            stops: [
                .init(color: bellyColor,              location: 0.00),   // 椭圆底部：跟能量变白
                .init(color: bellyColor,              location: 0.76),   // 椭圆上沿（ry = 0.38h）
                .init(color: baseColor.opacity(0.95), location: 1.00)    // 针尖：锁 core
            ],
            startPoint: .bottom,
            endPoint: .top
        )

        ZStack(alignment: .bottom) {
            // ── 1. 柔光层：真 blur ────────────────────────────────────
            // 旧实现用两层 stroke 手搓"假 blur"，是为了省 CPU；现在 SpectrumAnalyser 整条
            // HStack 已经 drawingGroup 栅格化，这层模糊是 GPU 在算，可以直接上真模糊。
            EnergySpindle(bulge: bulge)
                .fill(glowColor.opacity(0.30 + intensity * 0.45))
                .blur(radius: 1.4 + intensity * 3.2)

            // ── 2. 实体填充：椭圆整块 bellyColor，针尖过渡到 core ────
            EnergySpindle(bulge: bulge)
                .fill(bodyGradient)

            // ── 3. 轮廓描边：浅底上的识别度全靠这一线，不能省 ─────────
            EnergySpindle(bulge: bulge)
                .stroke(
                    baseColor.opacity(0.85),
                    lineWidth: 0.7 + intensity * 0.8
                )
        }
        .frame(width: shapeWidth, height: height, alignment: .bottom)
        .frame(width: barWidth, height: height, alignment: .bottom)
        .animation(.linear(duration: 0.099), value: intensity)
    }
}
