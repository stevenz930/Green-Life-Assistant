//
//  FlowingGradientBackgroundView.swift
//  EA
//
//  Created by Steven Z on 2026/04/15.
//

import SwiftUI

struct FlowingGradientBackgroundView: View {
    // 渐变起点的偏移量
    @State private var gradientOffset: CGFloat = -1.0
    // 流动一次的时时间
    let animationDuration: Double = 4.0
    
    let colors: [Color]

    var body: some View {
        LinearGradient(
            // 根据 animateGradient 的状态在起始颜色和结束颜色之间交替
            gradient: Gradient(colors: colors),
            // 根据 gradientOffset 动态改变起点和终点
            // 从左上角(-1, -1)，到右下角(2, 2)
            startPoint: UnitPoint(x: gradientOffset, y: gradientOffset),
            endPoint: UnitPoint(x: gradientOffset + 1.0, y: gradientOffset + 1.0)
        )
        .ignoresSafeArea()
        .animation(
            Animation.easeInOut(duration: animationDuration).repeatForever(autoreverses: false),
            // 观察 gradientOffset 值的变化
            value: gradientOffset
        )
        // 启动动画
        .onAppear {
            // 设置首次状态为 1.0，触发从 -1.0 到 1.0 的动画
            gradientOffset = 1.0
        }
    }
}
