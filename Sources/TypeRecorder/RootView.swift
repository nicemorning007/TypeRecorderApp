import AppKit
import SceneKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SidebarRoute.allCases, selection: $model.selectedRoute) { route in
                Label(route.title, systemImage: route.symbol)
                    .tag(route)
            }
            .navigationTitle("TypeRecorder")
            .frame(minWidth: 210)
        } detail: {
            switch model.selectedRoute ?? .dashboard {
            case .dashboard:
                DashboardView()
            case .keyboard:
                KeyboardHeatmapView()
            case .keyboard3D:
                Keyboard3DHeatmapView()
            case .events:
                EventsView()
            case .settings:
                SettingsView()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if model.isMonitoringRunning {
                    Button {
                        model.stopMonitoring()
                    } label: {
                        Label("停止记录", systemImage: "pause.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("停止键盘记录")
                } else if model.isMonitoringStarting {
                    Button {} label: {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("启动中")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                    .help("正在启动键盘记录")
                } else {
                    Button {
                        model.startMonitoring()
                    } label: {
                        Label("开始记录", systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("开始键盘记录")
                }

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("刷新统计数据")
            }
        }
        .onAppear {
            model.refreshWhenShown()
        }
        .onChange(of: model.selectedRoute) { _, _ in
            model.refreshWhenShown()
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderStrip()
                StatGrid()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        CompactHeatmap()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .layoutPriority(1)
                        RecentEventsCard()
                            .frame(width: 260)
                            .layoutPriority(0)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        CompactHeatmap()
                        RecentEventsCard()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .navigationTitle("总览")
    }
}

struct HeaderStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))
                .overlay(Circle().stroke(.separator.opacity(0.45), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text("键盘输入记录")
                    .font(.title2.weight(.semibold))
                Text("会话 \(model.sessionID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .layoutPriority(1)

            Spacer()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    HeaderStatusPills()
                }
                VStack(alignment: .trailing, spacing: 8) {
                    HeaderStatusPills()
                }
            }
        }
        .padding(18)
        .glassPanel()
    }
}

struct HeaderStatusPills: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StatusPill(
            title: model.isMonitoringRunning ? "正在记录" : "记录停止",
            symbol: model.isMonitoringRunning ? "checkmark.circle.fill" : "pause.circle",
            color: model.isMonitoringRunning ? .green : .orange
        )
            StatusPill(
                title: model.isKeyboardPermissionGranted ? "全局记录已授权" : "需要全局记录权限",
                symbol: model.isKeyboardPermissionGranted ? "lock.open.fill" : "lock.trianglebadge.exclamationmark",
                color: model.isKeyboardPermissionGranted ? .blue : .red
            )
    }
}

struct StatusPill: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(color.opacity(0.10)))
            .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
    }
}

struct StatGrid: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            StatCard(title: "按键次数", value: model.snapshot.realtime.keystrokesCount.formatted(), symbol: "keyboard", tint: .blue)
            StatCard(title: "有效输入", value: model.snapshot.realtime.validInputCount.formatted(), symbol: "text.cursor", tint: .green)
            StatCard(title: "总字符", value: model.snapshot.realtime.charactersCount.formatted(), symbol: "character.cursor.ibeam", tint: .purple)
            StatCard(title: "删除次数", value: model.snapshot.realtime.deletedCount.formatted(), symbol: "delete.left", tint: .red)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(tint: tint.opacity(0.08))
    }
}

struct CompactHeatmap: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "按键热力图", symbol: "keyboard")
            KeyboardGrid(items: model.snapshot.frequencies, compact: true)
        }
        .padding(18)
        .glassPanel()
    }
}

struct RecentEventsCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "最近输入", symbol: "list.bullet.rectangle")
            ForEach(model.snapshot.events.prefix(8)) { event in
                HStack(spacing: 10) {
                    Text(event.displayKey)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .frame(width: 44, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateFormatter.typeRecorderTime.string(from: event.timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            if model.snapshot.events.isEmpty {
                EmptyHint(title: "还没有输入记录", systemImage: "keyboard.badge.ellipsis")
            }
        }
        .padding(18)
        .glassPanel()
    }
}

struct ApplicationUsageCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "应用输入排行", symbol: "macwindow")
            ForEach(model.snapshot.applications.prefix(6)) { item in
                HStack {
                    Text(item.applicationName)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text("\(item.keystrokes.formatted()) 次")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(item.activeSeconds.durationText)
                        .monospacedDigit()
                        .frame(width: 90, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            if model.snapshot.applications.isEmpty {
                EmptyHint(title: "还没有应用统计", systemImage: "macwindow.badge.plus")
            }
        }
        .padding(18)
        .glassPanel()
    }
}

struct KeyboardHeatmapView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: "键盘热力图", symbol: "keyboard")
                KeyboardGrid(items: model.snapshot.frequencies, compact: false)
                    .padding(18)
                    .glassPanel()
                FrequencyTablePanel()
                    .frame(minHeight: 360)
            }
            .padding(24)
        }
        .navigationTitle("键盘热力图")
    }
}

struct Keyboard3DHeatmapView: View {
    @EnvironmentObject private var model: AppModel
    @State private var resetViewToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "3D键盘热力图", symbol: "cube.transparent")
                    Spacer()
                    Text("柱体越高、颜色越暖，代表\(model.statisticsScopeTitle)使用次数越多")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        resetViewToken += 1
                    } label: {
                        Label("重置视图", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("恢复到前方斜45度视角")
                }

                Keyboard3DChart(items: model.snapshot.frequencies, resetToken: resetViewToken)
                    .frame(minHeight: 520)
                    .padding(18)
                    .glassPanel()

                Keyboard3DLegend()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("3D键盘热力图")
    }
}

struct Keyboard3DLegend: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Label("拖拽旋转视角", systemImage: "rotate.3d")
            Label("双指捏合缩放", systemImage: "plus.magnifyingglass")
            Label("数据基于\(model.statisticsScopeTitle)按键频率", systemImage: "calendar")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
    }
}

struct Keyboard3DChart: NSViewRepresentable {
    let items: [WordFrequencyItem]
    let resetToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = Keyboard3DSceneView()
        view.scene = SCNScene()
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor.controlBackgroundColor
        configure(view: view, context: context)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        configure(view: view, context: context)
        guard resetToken != context.coordinator.lastResetToken else {
            return
        }
        context.coordinator.lastResetToken = resetToken
        (view as? Keyboard3DSceneView)?.resetCamera()
    }

    private func configure(view: SCNView, context: Context) {
        let bars = Keyboard3DLayout.bars(from: items)
        let signature = bars.map { "\($0.id):\($0.count)" }.joined(separator: "|")
        guard signature != context.coordinator.lastSignature else {
            return
        }
        context.coordinator.lastSignature = signature

        let scene = SCNScene()
        scene.rootNode.addChildNode(Keyboard3DSceneFactory.makeCameraNode())
        scene.rootNode.addChildNode(Keyboard3DSceneFactory.makeAmbientLightNode())
        scene.rootNode.addChildNode(Keyboard3DSceneFactory.makeKeyLightNode())
        scene.rootNode.addChildNode(Keyboard3DSceneFactory.makeFloorNode())

        for bar in bars {
            scene.rootNode.addChildNode(Keyboard3DSceneFactory.makeBarNode(bar))
        }

        // 数据为空时仍保留键盘底座和相机，避免页面初次进入时出现空白区域。
        view.scene = scene
        (view as? Keyboard3DSceneView)?.syncConstrainedCamera()
    }

    final class Coordinator {
        var lastSignature = ""
        var lastResetToken = 0
    }
}

private final class Keyboard3DSceneView: SCNView {
    private static let defaultYaw: CGFloat = -.pi / 4
    private static let defaultElevation: CGFloat = .pi / 4
    private static let defaultDistance: CGFloat = 21.5

    private let target = SCNVector3(0, 0.8, 0)
    private var lastDragPoint: NSPoint?
    private var yaw: CGFloat = defaultYaw
    private var elevation: CGFloat = defaultElevation
    private var distance: CGFloat = defaultDistance

    override func mouseDown(with event: NSEvent) {
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let currentPoint = convert(event.locationInWindow, from: nil)
        guard let previousPoint = lastDragPoint else {
            lastDragPoint = currentPoint
            return
        }

        let deltaX = currentPoint.x - previousPoint.x
        let deltaY = currentPoint.y - previousPoint.y
        yaw -= deltaX * 0.008
        elevation = clamp(elevation + deltaY * 0.006, min: .pi / 18, max: .pi / 2.25)
        lastDragPoint = currentPoint
        syncConstrainedCamera()
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        distance = clamp(distance + event.scrollingDeltaY * 0.08, min: 8.5, max: 26)
        syncConstrainedCamera()
    }

    override func magnify(with event: NSEvent) {
        distance = clamp(distance * (1 - event.magnification), min: 8.5, max: 26)
        syncConstrainedCamera()
    }

    func resetCamera() {
        // 重置视图必须和首次打开保持一致，避免用户每次进入页面看到不同的起始角度。
        yaw = Self.defaultYaw
        elevation = Self.defaultElevation
        distance = Self.defaultDistance
        syncConstrainedCamera()
    }

    func syncConstrainedCamera() {
        guard let cameraNode = scene?.rootNode.childNode(withName: Keyboard3DSceneFactory.cameraNodeName, recursively: true) else {
            return
        }

        // elevation 始终被限制在正角度范围内，用户不能把视角拖到键盘平面以下。
        let horizontalDistance = distance * cos(elevation)
        let x = horizontalDistance * sin(yaw)
        let y = distance * sin(elevation)
        let z = horizontalDistance * cos(yaw)
        cameraNode.position = SCNVector3(x, y, z)
        cameraNode.look(at: target)
        pointOfView = cameraNode
    }

    private func clamp<T: Comparable>(_ value: T, min lowerBound: T, max upperBound: T) -> T {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}

private enum Keyboard3DLayout {
    private static let rows: [[Keyboard3DKeySpec]] = [
        [Keyboard3DKeySpec(label: "Esc", width: 1.15)]
            + (1...12).map { Keyboard3DKeySpec(label: "F\($0)", width: 0.95) }
            + [Keyboard3DKeySpec(label: "Touch ID", width: 1.35)],
        [
            Keyboard3DKeySpec(label: "`"),
            Keyboard3DKeySpec(label: "1"), Keyboard3DKeySpec(label: "2"), Keyboard3DKeySpec(label: "3"),
            Keyboard3DKeySpec(label: "4"), Keyboard3DKeySpec(label: "5"), Keyboard3DKeySpec(label: "6"),
            Keyboard3DKeySpec(label: "7"), Keyboard3DKeySpec(label: "8"), Keyboard3DKeySpec(label: "9"),
            Keyboard3DKeySpec(label: "0"), Keyboard3DKeySpec(label: "-"), Keyboard3DKeySpec(label: "="),
            Keyboard3DKeySpec(label: "Delete", width: 1.65)
        ],
        [
            Keyboard3DKeySpec(label: "Tab", width: 1.55), Keyboard3DKeySpec(label: "q"), Keyboard3DKeySpec(label: "w"),
            Keyboard3DKeySpec(label: "e"), Keyboard3DKeySpec(label: "r"), Keyboard3DKeySpec(label: "t"),
            Keyboard3DKeySpec(label: "y"), Keyboard3DKeySpec(label: "u"), Keyboard3DKeySpec(label: "i"),
            Keyboard3DKeySpec(label: "o"), Keyboard3DKeySpec(label: "p"), Keyboard3DKeySpec(label: "["),
            Keyboard3DKeySpec(label: "]"), Keyboard3DKeySpec(label: "\\")
        ],
        [
            Keyboard3DKeySpec(label: "Caps Lock", width: 1.82), Keyboard3DKeySpec(label: "a"), Keyboard3DKeySpec(label: "s"),
            Keyboard3DKeySpec(label: "d"), Keyboard3DKeySpec(label: "f"), Keyboard3DKeySpec(label: "g"),
            Keyboard3DKeySpec(label: "h"), Keyboard3DKeySpec(label: "j"), Keyboard3DKeySpec(label: "k"),
            Keyboard3DKeySpec(label: "l"), Keyboard3DKeySpec(label: ";"), Keyboard3DKeySpec(label: "'"),
            Keyboard3DKeySpec(label: "Return", width: 1.9)
        ],
        [
            Keyboard3DKeySpec(label: "Shift", width: 2.2), Keyboard3DKeySpec(label: "z"), Keyboard3DKeySpec(label: "x"),
            Keyboard3DKeySpec(label: "c"), Keyboard3DKeySpec(label: "v"), Keyboard3DKeySpec(label: "b"),
            Keyboard3DKeySpec(label: "n"), Keyboard3DKeySpec(label: "m"), Keyboard3DKeySpec(label: ","),
            Keyboard3DKeySpec(label: "."), Keyboard3DKeySpec(label: "/"), Keyboard3DKeySpec(label: "Shift", width: 2.55)
        ],
        [
            Keyboard3DKeySpec(label: "fn", width: 0.95), Keyboard3DKeySpec(label: "Control", width: 1.2),
            Keyboard3DKeySpec(label: "Option", width: 1.2), Keyboard3DKeySpec(label: "Command", width: 1.35),
            Keyboard3DKeySpec(label: "Space", width: 4.85), Keyboard3DKeySpec(label: "Command", width: 1.35),
            Keyboard3DKeySpec(label: "Option", width: 1.2), Keyboard3DKeySpec(label: "←", width: 0.9),
            Keyboard3DKeySpec(label: "↑", width: 0.9), Keyboard3DKeySpec(label: "↓", width: 0.9),
            Keyboard3DKeySpec(label: "→", width: 0.9)
        ]
    ]

    static func bars(from items: [WordFrequencyItem]) -> [Keyboard3DBar] {
        let frequency = Dictionary(grouping: items, by: { $0.displayWord })
            .mapValues { $0.reduce(0) { $0 + $1.count } }
        let maxCount = max(frequency.values.max() ?? 0, 1)

        // 布局按真实键盘行宽居中。每行单独计算起点，避免宽键把整张键盘挤偏。
        let rowGap: Float = 1.35
        let keyGap: Float = 0.18
        let centeredRowOffset = Float(rows.count - 1) * rowGap / 2

        return rows.enumerated().flatMap { rowIndex, row in
            let rowWidth = row.reduce(Float.zero) { $0 + $1.width } + Float(max(0, row.count - 1)) * keyGap
            var cursor = -rowWidth / 2
            let z = Float(rowIndex) * rowGap - centeredRowOffset

            return row.enumerated().map { keyIndex, key in
                let count = frequency[key.label, default: 0]
                let normalized = Double(count) / Double(maxCount)
                let x = cursor + key.width / 2
                cursor += key.width + keyGap

                return Keyboard3DBar(
                    id: "\(rowIndex)-\(keyIndex)-\(key.label)",
                    label: key.label,
                    count: count,
                    normalized: normalized,
                    position: SCNVector3(x, 0, z),
                    width: key.width,
                    depth: 0.92
                )
            }
        }
    }
}

private struct Keyboard3DKeySpec {
    let label: String
    var width: Float = 1
}

private struct Keyboard3DBar {
    let id: String
    let label: String
    let count: Int
    let normalized: Double
    let position: SCNVector3
    let width: Float
    let depth: Float

    var height: Float {
        // 没有使用次数的键也给一个很低的底座，让键盘轮廓始终完整可辨。
        Float(0.08 + normalized * 3.4)
    }
}

private enum Keyboard3DSceneFactory {
    static let cameraNodeName = "Keyboard3DConstrainedCamera"

    static func makeCameraNode() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.1
        camera.zFar = 100

        let node = SCNNode()
        node.name = cameraNodeName
        node.camera = camera
        node.position = SCNVector3(0, 8.8, 12.5)
        node.look(at: SCNVector3(0, 0.8, 0))
        return node
    }

    static func makeAmbientLightNode() -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 420
        light.color = NSColor.white

        let node = SCNNode()
        node.light = light
        return node
    }

    static func makeKeyLightNode() -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.intensity = 760
        light.castsShadow = false

        let node = SCNNode()
        node.light = light
        node.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        return node
    }

    static func makeFloorNode() -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial?.diffuse.contents = NSColor.windowBackgroundColor
        floor.firstMaterial?.roughness.contents = 0.9

        let node = SCNNode(geometry: floor)
        node.position = SCNVector3(0, -0.01, 0)
        return node
    }

    static func makeBarNode(_ bar: Keyboard3DBar) -> SCNNode {
        let container = SCNNode()

        let box = SCNBox(
            width: CGFloat(bar.width),
            height: CGFloat(bar.height),
            length: CGFloat(bar.depth),
            chamferRadius: 0.05
        )
        box.firstMaterial?.diffuse.contents = color(for: bar)
        box.firstMaterial?.roughness.contents = 0.72

        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(bar.position.x, CGFloat(bar.height) / 2, bar.position.z)
        container.addChildNode(boxNode)

        container.addChildNode(makeLabelNode(for: bar))
        return container
    }

    private static func makeLabelNode(for bar: Keyboard3DBar) -> SCNNode {
        let text = SCNText(string: labelText(for: bar), extrusionDepth: 0.01)
        text.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        text.flatness = 0.2
        text.firstMaterial?.diffuse.contents = NSColor.labelColor

        let node = SCNNode(geometry: text)
        centerPivot(for: node)
        node.scale = SCNVector3(0.026, 0.026, 0.026)
        node.position = SCNVector3(bar.position.x, CGFloat(bar.height) + 0.12, bar.position.z)

        // 标签始终朝向相机，旋转 3D 视角时仍能读出按键和次数。
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.X, .Y]
        node.constraints = [billboard]
        return node
    }

    private static func labelText(for bar: Keyboard3DBar) -> String {
        bar.count > 0 ? "\(bar.label)\n\(bar.count)" : bar.label
    }

    private static func color(for bar: Keyboard3DBar) -> NSColor {
        guard bar.count > 0 else {
            return NSColor.controlBackgroundColor
        }

        // 低频保持蓝绿色，高频逐步过渡到橙红色，和高度共同表达热度。
        let hue = CGFloat(0.55 - bar.normalized * 0.52)
        let saturation = CGFloat(0.70 + bar.normalized * 0.18)
        let brightness = CGFloat(0.78 + bar.normalized * 0.18)
        return NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    private static func centerPivot(for node: SCNNode) {
        let bounds = node.boundingBox
        let centerX = (bounds.min.x + bounds.max.x) / 2
        let centerY = (bounds.min.y + bounds.max.y) / 2
        node.pivot = SCNMatrix4MakeTranslation(centerX, centerY, 0)
    }
}

struct FrequencyTablePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "频率统计", symbol: "chart.bar.xaxis")
            Table(model.snapshot.frequencies) {
                TableColumn("按键") { item in
                    Text(item.displayWord)
                }
                TableColumn("类型") { item in
                    Text(item.type.title)
                }
                TableColumn("次数") { item in
                    Text(item.count.formatted())
                        .monospacedDigit()
                }
                TableColumn("最近使用") { item in
                    Text(item.lastUsed.map { DateFormatter.typeRecorderTime.string(from: $0) } ?? "-")
                }
            }
            .frame(minHeight: 300)
        }
        .padding(18)
        .glassPanel()
    }
}

struct ApplicationsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Table(model.snapshot.applications) {
            TableColumn("应用") { item in
                Text(item.applicationName)
            }
            TableColumn("按键次数") { item in
                Text(item.keystrokes.formatted())
                    .monospacedDigit()
            }
            TableColumn("字符数") { item in
                Text(item.characters.formatted())
                    .monospacedDigit()
            }
            TableColumn("估算活跃时长") { item in
                Text(item.activeSeconds.durationText)
            }
            TableColumn("最近窗口") { item in
                Text(item.lastWindowTitle.isEmpty ? "-" : item.lastWindowTitle)
                    .lineLimit(1)
            }
        }
        .navigationTitle("应用统计")
    }
}

struct EventsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Table(model.snapshot.events) {
            TableColumn("时间") { event in
                Text(DateFormatter.typeRecorderTime.string(from: event.timestamp))
                    .monospacedDigit()
            }
            TableColumn("按键") { event in
                Text(event.displayKey)
            }
            TableColumn("编码") { event in
                Text("\(event.keyCode)")
                    .monospacedDigit()
            }
        }
        .navigationTitle("事件明细")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isClearDataDialogPresented = false
    private let authorURL = URL(string: "https://nicemorning.cn")!
    private let githubURL = URL(string: "https://github.com/nicemorning007/TypeRecorderApp")!

    var body: some View {
        Form {
            Section("记录") {
                Toggle("启用键盘记录", isOn: Binding(
                    get: { model.isMonitoringRunning || model.isMonitoringStarting },
                    set: { $0 ? model.startMonitoring() : model.stopMonitoring() }
                ))
                .disabled(model.isMonitoringStarting)
                if model.isMonitoringStarting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在启动键盘记录...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("全局记录权限")
                    Spacer()
                    Text(model.isKeyboardPermissionGranted ? "已授权" : "需要授权")
                        .foregroundStyle(model.isKeyboardPermissionGranted ? .green : .red)
                }
                Button("请求全局记录权限") {
                    model.requestKeyboardPermission()
                }
                .buttonStyle(.bordered)
                if let message = model.monitorStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let error = model.monitorLastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("数据") {
                Toggle("每日0时自动重置统计", isOn: Binding(
                    get: { model.isDailyResetEnabled },
                    set: { model.setDailyResetEnabled($0) }
                ))
                Text("开启后每天 0 点从 0 开始重置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("当前统计口径")
                    Spacer()
                    Text(model.statisticsScopeTitle)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    isClearDataDialogPresented = true
                } label: {
                    Label("清空数据", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                if let error = model.lastStorageError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("关于") {
                HStack {
                    Text("作者")
                    Spacer()
                    Link("Nicemorning", destination: authorURL)
                }
                HStack {
                    Text("GitHub")
                    Spacer()
                    Link(destination: githubURL) {
                        HStack(spacing: 6) {
                            GitHubIcon()
                                .frame(width: 16, height: 16)
                            Text("Github")
                        }
                    }
                }
                HStack {
                    Text("版本号")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle("设置")
        .confirmationDialog(
            "清空数据",
            isPresented: $isClearDataDialogPresented,
            titleVisibility: .visible
        ) {
            Button("清除今日数据", role: .destructive) {
                Task {
                    await model.clearData(.today)
                }
            }
            Button("清除历史所有数据", role: .destructive) {
                Task {
                    await model.clearData(.all)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请选择要清空的数据范围。该操作会删除本机已保存的对应统计数据。")
        }
    }
}

private struct GitHubIcon: View {
    var body: some View {
        // SF Symbols 没有 GitHub 品牌图标，这里用本地绘制的小标识，
        // 保证关于页离线打开时也能稳定显示仓库入口。
        ZStack {
            Circle()
                .fill(.primary)
            Text("GH")
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(Color(nsColor: .controlBackgroundColor))
        }
        .accessibilityHidden(true)
    }
}

struct KeyboardGrid: View {
    let items: [WordFrequencyItem]
    let compact: Bool

    private var frequency: [String: Int] {
        Dictionary(grouping: items, by: { $0.displayWord })
            .mapValues { $0.reduce(0) { $0 + $1.count } }
    }

    private var maxCount: Int {
        max(frequency.values.max() ?? 0, 1)
    }

    private var rows: [KeyboardRowSpec] {
        [
            KeyboardRowSpec(keys: [KeyboardKeySpec("Esc", width: 1.15)]
                + (1...12).map { KeyboardKeySpec("F\($0)", width: 0.95) }
                + [KeyboardKeySpec("Touch ID", width: 1.35)]),
            KeyboardRowSpec(keys: [
                KeyboardKeySpec("`"), KeyboardKeySpec("1"), KeyboardKeySpec("2"), KeyboardKeySpec("3"),
                KeyboardKeySpec("4"), KeyboardKeySpec("5"), KeyboardKeySpec("6"), KeyboardKeySpec("7"),
                KeyboardKeySpec("8"), KeyboardKeySpec("9"), KeyboardKeySpec("0"), KeyboardKeySpec("-"),
                KeyboardKeySpec("="), KeyboardKeySpec("Delete", width: 1.65)
            ]),
            KeyboardRowSpec(keys: [
                KeyboardKeySpec("Tab", width: 1.55), KeyboardKeySpec("q"), KeyboardKeySpec("w"),
                KeyboardKeySpec("e"), KeyboardKeySpec("r"), KeyboardKeySpec("t"), KeyboardKeySpec("y"),
                KeyboardKeySpec("u"), KeyboardKeySpec("i"), KeyboardKeySpec("o"), KeyboardKeySpec("p"),
                KeyboardKeySpec("["), KeyboardKeySpec("]"), KeyboardKeySpec("\\", width: 1.1)
            ]),
            KeyboardRowSpec(keys: [
                KeyboardKeySpec("Caps Lock", width: 1.82), KeyboardKeySpec("a"), KeyboardKeySpec("s"),
                KeyboardKeySpec("d"), KeyboardKeySpec("f"), KeyboardKeySpec("g"), KeyboardKeySpec("h"),
                KeyboardKeySpec("j"), KeyboardKeySpec("k"), KeyboardKeySpec("l"), KeyboardKeySpec(";"),
                KeyboardKeySpec("'"), KeyboardKeySpec("Return", width: 1.9)
            ]),
            KeyboardRowSpec(keys: [
                KeyboardKeySpec("Shift", width: 2.2), KeyboardKeySpec("z"), KeyboardKeySpec("x"),
                KeyboardKeySpec("c"), KeyboardKeySpec("v"), KeyboardKeySpec("b"), KeyboardKeySpec("n"),
                KeyboardKeySpec("m"), KeyboardKeySpec(","), KeyboardKeySpec("."), KeyboardKeySpec("/"),
                KeyboardKeySpec("Shift", width: 2.55)
            ]),
            KeyboardRowSpec(keys: [
                KeyboardKeySpec("fn", width: 0.95), KeyboardKeySpec("Control", width: 1.2),
                KeyboardKeySpec("Option", width: 1.2), KeyboardKeySpec("Command", width: 1.35),
                KeyboardKeySpec("Space", width: 4.85), KeyboardKeySpec("Command", width: 1.35),
                KeyboardKeySpec("Option", width: 1.2), KeyboardKeySpec("←", width: 0.9),
                KeyboardKeySpec("↑", width: 0.9), KeyboardKeySpec("↓", width: 0.9),
                KeyboardKeySpec("→", width: 0.9)
            ])
        ]
    }

    private var baseSpacing: CGFloat {
        compact ? 5 : 8
    }

    private var baseHeight: CGFloat {
        compact ? 38 : 52
    }

    private var baseGridWidth: CGFloat {
        rows.map { $0.totalWidth(compact: compact, spacing: baseSpacing) }.max() ?? 1
    }

    private var baseGridHeight: CGFloat {
        CGFloat(rows.count) * baseHeight + CGFloat(rows.count - 1) * baseSpacing
    }

    var body: some View {
        GeometryReader { proxy in
            // 必须按容器真实宽度缩放，不能设置最小缩放下限。
            // 否则在“最近输入”挤占宽度时，键帽仍按下限绘制，会横向超出卡片。
            let scale = min(1, max(0.1, proxy.size.width / baseGridWidth))

            VStack(spacing: baseSpacing * scale) {
                ForEach(rows) { row in
                    KeyRow(
                        spec: row,
                        frequency: frequency,
                        maxCount: maxCount,
                        compact: compact,
                        scale: scale
                    )
                }
            }
            .frame(width: baseGridWidth * scale, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: baseGridHeight)
    }
}

struct KeyboardRowSpec: Identifiable {
    let keys: [KeyboardKeySpec]

    var id: String {
        keys.map { "\($0.title):\($0.width)" }.joined(separator: "|")
    }

    func keyWidth(_ key: KeyboardKeySpec, compact: Bool) -> CGFloat {
        key.width * (compact ? 42 : 56)
    }

    func totalWidth(compact: Bool, spacing: CGFloat) -> CGFloat {
        let keysWidth = keys.reduce(CGFloat.zero) { total, key in
            total + keyWidth(key, compact: compact)
        }
        return keysWidth + CGFloat(max(0, keys.count - 1)) * spacing
    }
}

struct KeyboardKeySpec {
    let title: String
    let width: CGFloat

    init(_ title: String, width: CGFloat = 1) {
        self.title = title
        self.width = width
    }
}

struct KeyRow: View {
    let spec: KeyboardRowSpec
    let frequency: [String: Int]
    let maxCount: Int
    let compact: Bool
    let scale: CGFloat

    var body: some View {
        HStack(spacing: (compact ? 5 : 8) * scale) {
            ForEach(Array(spec.keys.enumerated()), id: \.offset) { index, key in
                KeyTile(
                    title: key.title,
                    count: frequency[key.title, default: 0],
                    maxCount: maxCount,
                    compact: compact
                )
                .frame(
                    width: spec.keyWidth(key, compact: compact) * scale,
                    height: (compact ? 38 : 52) * scale
                )
            }
        }
    }
}

struct KeyTile: View {
    let title: String
    let count: Int
    let maxCount: Int
    let compact: Bool

    private var level: Double {
        min(1, Double(count) / Double(maxCount))
    }

    private var tint: Color {
        Color(hue: 0.58 - (level * 0.55), saturation: 0.78, brightness: 0.95)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(compact ? .caption : .body, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if count > 0 {
                Text(count.formatted())
                    .font(.system(size: compact ? 9 : 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                .fill(keyFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                .stroke(keyBorder, lineWidth: 1)
        }
        .help("\(title)：\(count) 次")
    }

    private var keyFill: Color {
        if count > 0 {
            return tint.opacity(0.20 + level * 0.34)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var keyBorder: Color {
        count > 0 ? tint.opacity(0.36) : Color(nsColor: .separatorColor).opacity(0.35)
    }
}

struct SectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
    }
}

struct EmptyHint: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

extension View {
    func glassPanel(tint: Color = .clear) -> some View {
        self.modifier(PerformancePanelModifier(tint: tint))
    }
}

private struct PerformancePanelModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
