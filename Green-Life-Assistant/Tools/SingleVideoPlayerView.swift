//
//  SingleVideoPlayerView.swift
//  EA
//
//  Created by Steven Z on 2026/04/15.
//

import SwiftUI
import AVKit
import CoreMedia

struct SingleVideoPlayerView: View {
    @Environment(\.scenePhase) var scenePhase
    let fileName: String
    let fileType: String
    
    @State private var player: AVPlayer = AVPlayer()
    @State private var item: AVPlayerItem?
    
    init(fileName: String, fileType: String = "mp4") {
        self.fileName = fileName
        self.fileType = fileType
    }
    
    var body: some View {
        VideoPlayerController(player: player)
            .ignoresSafeArea()
            .transition(.opacity.animation(.easeInOut(duration: 0.5)))
            .onAppear {
                restorePlayerItem()
                enableLooping()
                player.play()
            }
            .onDisappear {
                player.pause()
                disableLooping()
                cleanup()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    player.play()
                }
            }
    }
    
    // MARK: - Lifecycle Helpers
    
    // 创建并绑定 AVPlayerItem
    private func restorePlayerItem() {
        if item == nil {
            if let url = Bundle.main.url(forResource: fileName, withExtension: fileType) {
                item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
            }
        }
    }
    
    // 释放内存
    private func cleanup() {
        player.replaceCurrentItem(with: nil)
        item = nil
    }
    
    // 循环播放
    private func enableLooping() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }
    
    // 移除循环播放通知
    private func disableLooping() {
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }
}

// MARK: - Video Player Controller
struct VideoPlayerController: UIViewControllerRepresentable {
    var player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        
    }
}
