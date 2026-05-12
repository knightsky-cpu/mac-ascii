import Foundation

enum LuminanceMode: String, CaseIterable {
    case classic10
    case fine20

    var bucketCount: Int {
        switch self {
        case .classic10:
            return 10
        case .fine20:
            return 20
        }
    }
}

struct GridPreset {
    let name: String
    let cellSize: Float
}

struct VisualStyle {
    let name: String
    let mode: Int32
}

final class AppState {
    static let defaultGridName = "micro-ascii"
    static let defaultStyleName = "classic-amber"
    static let defaultLuminanceMode: LuminanceMode = .classic10
    static let defaultOverlayVisible = true
    static let defaultOverlayOpacity: Float = 0.90
    static let defaultBrightness: Float = 0.0
    static let defaultContrast: Float = 1.0
    static let defaultGamma: Float = 1.0
    static let defaultEdgeStrength: Float = 1.0
    static let brightnessCycle: [Float] = [
        0.00, 0.05, 0.10, 0.15, 0.20, 0.30, 0.40, 0.50,
        -0.50, -0.40, -0.30, -0.20, -0.10, -0.05,
    ]
    static let contrastCycle: [Float] = [
        1.00, 1.10, 1.20, 1.35, 1.50, 1.75, 2.00,
        0.50, 0.65, 0.80, 0.90,
    ]
    static let gammaCycle: [Float] = [
        1.00, 0.90, 0.80, 0.70, 0.60, 0.50,
        1.20, 1.40, 1.60, 1.80, 2.00,
    ]
    static let edgeStrengthCycle: [Float] = [
        1.00, 1.25, 1.50, 1.75, 2.00,
        0.00, 0.25, 0.50, 0.75,
    ]

    private enum SettingsKey {
        static let overlayVisible = "overlayVisible"
        static let gridName = "gridName"
        static let styleName = "styleName"
        static let luminanceMode = "luminanceMode"
    }

    private let defaults: UserDefaults

    let gridPresets = [
        GridPreset(name: "pixel-ascii", cellSize: 1),
        GridPreset(name: "nano-ascii", cellSize: 2),
        GridPreset(name: "ultra-fine-ascii", cellSize: 3),
        GridPreset(name: "micro-ascii", cellSize: 4),
        GridPreset(name: "small-ascii", cellSize: 5),
        GridPreset(name: "compact-ascii", cellSize: 6),
        GridPreset(name: "balanced-ascii", cellSize: 7),
        GridPreset(name: "fine-ascii", cellSize: 8),
        GridPreset(name: "soft-fine-ascii", cellSize: 9),
        GridPreset(name: "soft-large-ascii", cellSize: 10),
        GridPreset(name: "macbook-readable", cellSize: 12),
        GridPreset(name: "macbook-large", cellSize: 16),
        GridPreset(name: "macbook-xl", cellSize: 20),
    ]

    let visualStyles = [
        VisualStyle(name: "classic-amber", mode: 0),
        VisualStyle(name: "dark-amber", mode: 5),
        VisualStyle(name: "muted-crt", mode: 1),
        VisualStyle(name: "hybrid-edge-tint", mode: 2),
        VisualStyle(name: "invert", mode: 3),
        VisualStyle(name: "cyberpunk", mode: 4),
        VisualStyle(name: "green-phosphor", mode: 6),
        VisualStyle(name: "paper-ink", mode: 7),
        VisualStyle(name: "blueprint", mode: 8),
        VisualStyle(name: "moonlight", mode: 9),
        VisualStyle(name: "thermal-edge", mode: 10),
    ]

    private(set) var gridIndex = 3
    private(set) var styleIndex = 0
    private(set) var luminanceMode: LuminanceMode = .classic10
    private(set) var overlayVisible = true
    private(set) var overlayOpacity = AppState.defaultOverlayOpacity
    private(set) var brightness = AppState.defaultBrightness
    private(set) var contrast = AppState.defaultContrast
    private(set) var gamma = AppState.defaultGamma
    private(set) var edgeStrength = AppState.defaultEdgeStrength

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Recovery default: ignore persisted visual state until settings are reintroduced safely.
    }

    var activeGrid: GridPreset {
        gridPresets[gridIndex]
    }

    var activeStyle: VisualStyle {
        visualStyles[styleIndex]
    }

    var luminanceIndex: Int {
        LuminanceMode.allCases.firstIndex(of: luminanceMode) ?? 0
    }

    func toggleOverlay() {
        setOverlayVisible(!overlayVisible)
    }

    func cycleGrid() {
        setGridIndex((gridIndex + 1) % gridPresets.count)
    }

    func cycleStyle() {
        setStyleIndex((styleIndex + 1) % visualStyles.count)
    }

    func toggleLuminanceMode() {
        setLuminanceMode(luminanceMode == .classic10 ? .fine20 : .classic10)
    }

    func increaseOpacity() {
        setOverlayOpacity(overlayOpacity + 0.05)
    }

    func decreaseOpacity() {
        setOverlayOpacity(overlayOpacity - 0.05)
    }

    func increaseBrightness() {
        setBrightness(brightness + 0.05)
    }

    func decreaseBrightness() {
        setBrightness(brightness - 0.05)
    }

    func increaseContrast() {
        setContrast(contrast + 0.10)
    }

    func decreaseContrast() {
        setContrast(contrast - 0.10)
    }

    func increaseGamma() {
        setGamma(gamma + 0.10)
    }

    func decreaseGamma() {
        setGamma(gamma - 0.10)
    }

    func cycleBrightness() {
        setBrightness(nextCycleValue(current: brightness, values: Self.brightnessCycle))
    }

    func cycleContrast() {
        setContrast(nextCycleValue(current: contrast, values: Self.contrastCycle))
    }

    func cycleGamma() {
        setGamma(nextCycleValue(current: gamma, values: Self.gammaCycle))
    }

    func increaseEdgeStrength() {
        setEdgeStrength(edgeStrength + 0.25)
    }

    func decreaseEdgeStrength() {
        setEdgeStrength(edgeStrength - 0.25)
    }

    func cycleEdgeStrength() {
        setEdgeStrength(nextCycleValue(current: edgeStrength, values: Self.edgeStrengthCycle))
    }

    func setOverlayVisible(_ visible: Bool) {
        overlayVisible = visible
        save()
        logState("set-overlay")
    }

    func setGridIndex(_ index: Int) {
        guard gridPresets.indices.contains(index) else {
            return
        }

        gridIndex = index
        save()
        logState("set-grid")
    }

    func setStyleIndex(_ index: Int) {
        guard visualStyles.indices.contains(index) else {
            return
        }

        styleIndex = index
        save()
        logState("set-style")
    }

    func setLuminanceMode(_ mode: LuminanceMode) {
        luminanceMode = mode
        save()
        logState("set-luminance")
    }

    func setOverlayOpacity(_ opacity: Float) {
        overlayOpacity = min(1.0, max(0.10, opacity))
        logState("set-opacity")
    }

    func setBrightness(_ value: Float) {
        brightness = min(0.50, max(-0.50, value))
        logState("set-brightness")
    }

    func setContrast(_ value: Float) {
        contrast = min(2.0, max(0.50, value))
        logState("set-contrast")
    }

    func setGamma(_ value: Float) {
        gamma = min(2.0, max(0.50, value))
        logState("set-gamma")
    }

    func setEdgeStrength(_ value: Float) {
        edgeStrength = min(2.0, max(0.0, value))
        logState("set-edge-strength")
    }

    private func nextCycleValue(current: Float, values: [Float]) -> Float {
        guard !values.isEmpty else {
            return current
        }

        let epsilon: Float = 0.001
        if let index = values.firstIndex(where: { abs($0 - current) < epsilon }) {
            return values[(index + 1) % values.count]
        }

        return values[0]
    }

    func resetVisualDefaults() {
        overlayVisible = Self.defaultOverlayVisible
        gridIndex = gridPresets.firstIndex { $0.name == Self.defaultGridName } ?? 3
        styleIndex = visualStyles.firstIndex { $0.name == Self.defaultStyleName } ?? 0
        luminanceMode = Self.defaultLuminanceMode
        overlayOpacity = Self.defaultOverlayOpacity
        brightness = Self.defaultBrightness
        contrast = Self.defaultContrast
        gamma = Self.defaultGamma
        edgeStrength = Self.defaultEdgeStrength
        save()
        logState("reset-visual-defaults")
    }

    func sanitizedRenderState() -> (
        cellSize: Float,
        styleMode: Int32,
        luminanceBuckets: Int32,
        opacity: Float,
        brightness: Float,
        contrast: Float,
        gamma: Float,
        edgeStrength: Float
    ) {
        let cellSize = max(1.0, activeGrid.cellSize)
        let knownStyleModes = Set(visualStyles.map(\.mode))
        let styleMode = knownStyleModes.contains(activeStyle.mode) ? activeStyle.mode : 0
        let buckets = luminanceMode.bucketCount
        let luminanceBuckets = (buckets == 10 || buckets == 20) ? Int32(buckets) : 10
        let opacity = min(1.0, max(0.10, overlayOpacity))
        let brightness = min(0.50, max(-0.50, self.brightness))
        let contrast = min(2.0, max(0.50, self.contrast))
        let gamma = min(2.0, max(0.50, self.gamma))
        let edgeStrength = min(2.0, max(0.0, self.edgeStrength))

        return (cellSize, styleMode, luminanceBuckets, opacity, brightness, contrast, gamma, edgeStrength)
    }

    private func load() {
        if defaults.object(forKey: SettingsKey.overlayVisible) != nil {
            overlayVisible = defaults.bool(forKey: SettingsKey.overlayVisible)
        }

        if let gridName = defaults.string(forKey: SettingsKey.gridName),
           let index = gridPresets.firstIndex(where: { $0.name == gridName }) {
            gridIndex = index
        }

        if let styleName = defaults.string(forKey: SettingsKey.styleName),
           let index = visualStyles.firstIndex(where: { $0.name == styleName }) {
            styleIndex = index
        }

        if let luminanceName = defaults.string(forKey: SettingsKey.luminanceMode),
           let mode = LuminanceMode(rawValue: luminanceName) {
            luminanceMode = mode
        }
    }

    private func save() {
        defaults.set(overlayVisible, forKey: SettingsKey.overlayVisible)
        defaults.set(activeGrid.name, forKey: SettingsKey.gridName)
        defaults.set(activeStyle.name, forKey: SettingsKey.styleName)
        defaults.set(luminanceMode.rawValue, forKey: SettingsKey.luminanceMode)
    }

    func logState(_ reason: String) {
        print(
            "MacAscii: \(reason) visible=\(overlayVisible) " +
            "grid=\(activeGrid.name) cell-size=\(activeGrid.cellSize) " +
            "style=\(activeStyle.name) style-mode=\(activeStyle.mode) " +
            "luminance-buckets=\(luminanceMode.bucketCount) " +
            "opacity=\(Int(overlayOpacity * 100))% " +
            "brightness=\(String(format: "%.2f", brightness)) " +
            "contrast=\(String(format: "%.2f", contrast)) " +
            "gamma=\(String(format: "%.2f", gamma)) " +
            "edge=\(String(format: "%.2f", edgeStrength))"
        )
    }
}
