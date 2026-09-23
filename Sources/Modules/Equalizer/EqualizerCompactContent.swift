import AppKit
import Combine

final class EqualizerCompactContent: AmpXCompactModuleView {
    let volumeSlider: AmpXSlider
    let balanceSlider: AmpXSlider
    private var cancellables = Set<AnyCancellable>()

    init(skin: any AmpXSkin, audioPlayer: AudioPlayer) {
        self.volumeSlider = AmpXSlider(skin: skin)
        self.balanceSlider = AmpXSlider(skin: skin)
        super.init(moduleID: .equalizer, skin: skin)
        self.addSubview(self.volumeSlider)
        self.addSubview(self.balanceSlider)
        for slider in [self.volumeSlider, self.balanceSlider] {
            slider.confinesHitTestingToBounds = true
            slider.focusRingInset = 1
            slider.accessibilityStep = 0.05
            slider.setAccessibilityElement(true)
        }
        self.volumeSlider.artwork = .compact(.volume)
        self.volumeSlider.accessibilityTitle = "Volume"
        self.volumeSlider.accessibilityRangeOverride = 0 ... 100
        self.volumeSlider.accessibilityValueFormatter = { "\(Int(($0 * 100).rounded()))%" }
        self.volumeSlider.onChange = { [weak audioPlayer] in audioPlayer?.setVolume(Float($0)) }
        self.balanceSlider.artwork = .compact(.balance)
        self.balanceSlider.accessibilityTitle = "Balance"
        self.balanceSlider.accessibilityRangeOverride = -100 ... 100
        self.balanceSlider.accessibilityValueFormatter = {
            let balance = Int((($0 * 2 - 1) * 100).rounded())
            return balance == 0 ? "Center" : "\(balance < 0 ? "Left" : "Right") \(abs(balance))%"
        }
        self.balanceSlider.onChange = { [weak audioPlayer] in audioPlayer?.setBalance(Float($0 * 2 - 1)) }
        audioPlayer.$volume.removeDuplicates().sink { [weak volumeSlider] value in
            volumeSlider?.setValue(Double(value), sendChange: false)
        }.store(in: &self.cancellables)
        audioPlayer.$balance.removeDuplicates().sink { [weak balanceSlider] value in
            balanceSlider?.setValue(Double((value + 1) / 2), sendChange: false)
        }.store(in: &self.cancellables)
    }

    override var protectedRects: [CGRect] {
        let layout = AmpXCompactMetrics.equalizerLayout()
        return super.protectedRects + [layout.volume, layout.balance]
    }

    override func layout() {
        super.layout()
        let layout = AmpXCompactMetrics.equalizerLayout()
        self.volumeSlider.frame = layout.volume
        self.balanceSlider.frame = layout.balance
        self.volumeSlider.trackSize = layout.volumeTrack.size
        self.balanceSlider.trackSize = layout.balanceTrack.size
        self.volumeSlider.thumbSize = layout.volumeThumbSize
        self.balanceSlider.thumbSize = layout.balanceThumbSize
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        self.drawSeparator(AmpXCompactMetrics.equalizerLayout().separator, in: context)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
