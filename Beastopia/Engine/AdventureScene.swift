//
//  AdventureScene.swift
//  Beastopia
//

import SpriteKit
import SwiftUI
import UIKit

/// The walkable 2D world for a story region. Movement is tile-by-tile, driven either by
/// tapping a destination (tap-to-walk) or by holding a direction on the joystick.
/// The scene only reports events; SwiftUI decides what they mean for the quest.
final class AdventureScene: SKScene {
    enum ControlMode: String, CaseIterable, Identifiable {
        case tap, joystick
        var id: String { rawValue }
        var displayName: String { self == .tap ? "Tap to Walk" : "Joystick" }
    }

    /// How an NPC or boss is drawn on the map.
    struct EntityStyle {
        let name: String
        let symbol: String
        let color: UIColor
        /// Sprite to use instead of `npc_<objectiveID>`, e.g. to reuse a story character's art.
        var art: String? = nil
    }

    /// 48 pt keeps 16 px tile art on whole-pixel scales (6× at @2x, 9× at @3x).
    static let tileSize: CGFloat = 48
    private static let stepDuration: TimeInterval = 0.2

    let map: AdventureMap
    private let entityStyles: [String: EntityStyle]

    var controlMode: ControlMode = .tap {
        didSet { if controlMode == .joystick { route.removeAll() } }
    }

    /// Disabled while dialogue or battles are on screen so the player can't wander off.
    var isInputEnabled = true {
        didSet {
            if isInputEnabled {
                stepIfIdle()
            } else {
                route.removeAll()
                pendingInteraction = nil
            }
        }
    }

    /// The direction the joystick is held in, or `nil` when released.
    var heldDirection: StepDirection? {
        didSet { stepIfIdle() }
    }

    /// The joystick's weaker axis when it's held diagonally. Used to slide along walls.
    var secondaryDirection: StepDirection?

    /// The keeper's signature color and walking figure, from character creation. Set before presenting.
    var playerColor: UIColor = .systemIndigo
    var playerSymbol = "figure.walk"

    /// Field abilities lent by the keeper's beasts: swim across water, fly over chasms, blink past walls.
    var abilities: Set<TraversalAbility> = [] {
        didSet { updatePlayerLook() }
    }

    /// Something the player can walk up to and use.
    private enum Interaction: Equatable {
        case objective(String)
        case station(Tile)
        /// Walk up to a boulder and push it.
        case boulder(Tile)
    }

    /// Something that happened in the region's element puzzle, for SwiftUI to explain.
    enum FieldEvent: Equatable {
        /// Walked into (or stood on) an erupting geyser.
        case scorched
        /// Walked into (or stood on) a live lightning arc.
        case zapped
        /// The tide came in and carried the keeper back to dry land.
        case washedAshore
        /// A gust picked the keeper up.
        case gust
        case boulderPushed
        /// A boulder was pushed into water and filled it in.
        case boulderSank
        /// The boulder has nowhere to go.
        case boulderStuck
        /// A bloom was stepped on; `remaining` are still unlit.
        case bloomLit(remaining: Int)
        case bramblesOpened
        /// Tried to walk through closed brambles.
        case brambleBlocked
    }

    /// The region's element puzzle as it stands: boulders, filled water, blooms and the tide.
    private(set) var fieldState: FieldState
    /// Reports element puzzle events (geysers, tides, boulders, blooms…).
    var onFieldEvent: ((FieldEvent) -> Void)?
    /// How far the keeper can see in a dark region, in tiles. Set before presenting.
    var lightRadius: CGFloat = 2.6 {
        didSet { if oldValue != lightRadius { rebuildDarkness() } }
    }

    /// The player walked up to an objective's NPC or boss.
    var onInteract: ((String) -> Void)?
    /// The player walked up to a care station such as the Stable or Market.
    var onFacility: ((Facility) -> Void)?
    /// The player finished a step onto a new tile.
    var onStep: ((Tile, Terrain) -> Void)?
    /// The player tried to cross terrain that needs an ability they don't have.
    var onBlocked: ((TraversalAbility) -> Void)?
    /// The player blinked to a new tile.
    var onBlink: (() -> Void)?

    /// How far Blink reaches, in tiles (any direction, diagonals included).
    static let blinkRange = 5

    private(set) var playerTile: Tile
    private var facing: StepDirection = .down
    private var isMoving = false
    private var route: [Tile] = []
    private var pendingInteraction: Interaction?
    private var hasBuiltWorld = false
    private var treasureNodes: [String: SKSpriteNode] = [:]
    /// The tile the keeper stood on before the current one, for geyser and arc knockback.
    private var previousTile: Tile?
    /// Seconds the scene has been running, which drives the geyser, arc and tide cycles.
    private var clock: TimeInterval = 0
    private var lastUpdateTime: TimeInterval?
    private var hazardNodes: [Tile: SKNode] = [:]
    private var hazardOn: [Tile: Bool] = [:]
    private var boulderNodes: [Tile: SKNode] = [:]
    private var brambleNodes: [Tile: SKNode] = [:]
    private var bloomNodes: [Tile: SKSpriteNode] = [:]
    private var tideNodes: [SKNode] = []
    private var darknessNode: SKSpriteNode?
    private var glyphNode: SKNode?
    private var trailNodes: [SKNode] = []

    private let player = SKNode()
    private let playerIcon = SKSpriteNode()
    /// The player's sprite from the asset catalog, if one has been added.
    private var playerArt: SKTexture?
    private let cameraNode = SKCameraNode()
    private var entityNodes: [String: SKNode] = [:]
    private var questMarker: SKSpriteNode?

    /// Region names for exit signposts, keyed by destination region ID.
    private let exitNames: [Int: String]

    init(map: AdventureMap, start: Tile, entityStyles: [String: EntityStyle], exitNames: [Int: String]) {
        self.map = map
        self.entityStyles = entityStyles
        self.exitNames = exitNames
        self.playerTile = map.isWalkable(start) || map.treasure(at: start) != nil ? start : map.start
        self.fieldState = map.initialState
        super.init(size: CGSize(width: 390, height: 700))
        scaleMode = .resizeFill
        backgroundColor = map.theme.look(for: .tree).color
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - World building

    override func didMove(to view: SKView) {
        guard !hasBuiltWorld else { return }
        hasBuiltWorld = true
        buildTerrain()
        buildExits()
        buildEntities()
        buildStations()
        buildTreasures()
        buildFeatures()
        buildPlayer()
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = cameraTarget()
    }

    private func buildTerrain() {
        let size = CGSize(width: Self.tileSize, height: Self.tileSize)
        let buildingArt = map.buildingArt.flatMap { Self.artTexture($0) }
        for row in 0..<map.height {
            for col in 0..<map.width {
                let tile = Tile(col: col, row: row)
                guard let mapTerrain = map.terrain(at: tile) else { continue }
                // A single-art building sits on plain ground, which shows through its transparent corners.
                let isUnderBuildingArt = mapTerrain == .building && buildingArt != nil
                let terrain = isUnderBuildingArt ? .grass : mapTerrain
                let noise = Self.noise(tile)
                let ground: SKSpriteNode
                if let art = tileArt(at: tile, terrain: terrain) {
                    ground = SKSpriteNode(texture: art, size: size)
                } else {
                    // Nudge each tile's shade so the ground reads as natural, not a flat grid.
                    ground = SKSpriteNode(color: color(for: terrain).adjustingBrightness(by: (noise - 0.5) * 0.08), size: size)
                    if let (symbol, tint, scale) = decoration(for: terrain) {
                        let icon = SKSpriteNode(texture: Self.symbolTexture(symbol, color: tint))
                        let jitteredScale = scale * (0.9 + noise * 0.2)
                        icon.size = CGSize(width: Self.tileSize * jitteredScale, height: Self.tileSize * jitteredScale)
                        icon.position = CGPoint(x: (noise - 0.5) * Self.tileSize * 0.16,
                                                y: (Self.noise(tile, salt: 7) - 0.5) * Self.tileSize * 0.12)
                        icon.zRotation = (Self.noise(tile, salt: 13) - 0.5) * 0.25
                        ground.addChild(icon)
                    }
                }
                ground.position = point(for: tile)
                ground.zPosition = 0
                addChild(ground)
                // Tile-shaped shadows would stick out past single-art buildings, so they get none.
                let isBelowBuildingArt = buildingArt != nil && map.terrain(at: Tile(col: col, row: row - 1)) == .building
                if !isUnderBuildingArt && !isBelowBuildingArt {
                    addDepthShading(at: tile, terrain: terrain)
                }
            }
        }
        if let buildingArt { addBuildingArt(buildingArt) }
    }

    static let buildingArtName = "map.buildingArt"

    /// Draws `map.buildingArt` once, centered on the map's building tiles and as tall as them. The art
    /// keeps its shape, so a 3×3 image can sit centered on a 4-wide footprint.
    private func addBuildingArt(_ texture: SKTexture) {
        let tiles = (0..<map.height).flatMap { row in
            (0..<map.width).map { Tile(col: $0, row: row) }
        }.filter { map.terrain(at: $0) == .building }
        guard let minCol = tiles.map(\.col).min(), let maxCol = tiles.map(\.col).max(),
              let minRow = tiles.map(\.row).min(), let maxRow = tiles.map(\.row).max() else { return }
        let topLeft = point(for: Tile(col: minCol, row: minRow))
        let bottomRight = point(for: Tile(col: maxCol, row: maxRow))
        let height = CGFloat(maxRow - minRow + 1) * Self.tileSize
        let textureSize = texture.size()
        let building = SKSpriteNode(texture: texture,
                                    size: CGSize(width: height * textureSize.width / textureSize.height, height: height))
        building.name = Self.buildingArtName
        building.position = CGPoint(x: (topLeft.x + bottomRight.x) / 2, y: (topLeft.y + bottomRight.y) / 2)
        building.zPosition = 1
        addChild(building)
    }

    /// Final tile art: the region's own tile if it has one, otherwise the generic `tile_<terrain>`.
    private func tileArt(at tile: Tile, terrain: Terrain) -> SKTexture? {
        let themed = "tile_\(map.theme)_"
        // Indoors never falls back to the outdoor tiles (no grass on the inn floor).
        if map.theme == .interior && Self.artTexture("\(themed)\(terrain)") == nil { return nil }
        let prefix = Self.artTexture("\(themed)\(terrain)") != nil ? themed : "tile_"
        guard let base = Self.artTexture("\(prefix)\(terrain)") else { return nil }
        let part: String?
        switch terrain {
        case .building: part = buildingPart(at: tile)
        case .fence: part = fencePart(at: tile)
        default: part = nil
        }
        guard let part else { return base }
        // Wall, door and fence pieces come from the same set as the base tile, so styles never mix.
        return Self.artTexture("\(prefix)\(part)") ?? base
    }

    /// Picks the fence piece that joins up with neighboring fence tiles. Corner names list the two
    /// directions they connect (`fenceNE` joins north and east). Returns `nil` for a horizontal run.
    private func fencePart(at tile: Tile) -> String? {
        func isFence(_ col: Int, _ row: Int) -> Bool {
            map.terrain(at: Tile(col: tile.col + col, row: tile.row + row)) == .fence
        }
        let north = isFence(0, -1)
        let south = isFence(0, 1)
        let east = isFence(1, 0)
        let west = isFence(-1, 0)
        switch (north, south, east, west) {
        case (true, false, true, false): return "fenceNE"
        case (true, false, false, true): return "fenceNW"
        case (false, true, true, false): return "fenceSE"
        case (false, true, false, true): return "fenceSW"
        case (_, _, false, false) where north || south: return "fenceV"
        default: return nil
        }
    }

    /// Buildings are drawn as roof on top with a front wall along the bottom row, and a door in
    /// the middle of that wall. Returns `nil` for roof tiles.
    private func buildingPart(at tile: Tile) -> String? {
        guard map.terrain(at: Tile(col: tile.col, row: tile.row + 1)) != .building else { return nil }
        // Find this stretch of front wall so the door can sit at its center.
        var first = tile.col
        while map.terrain(at: Tile(col: first - 1, row: tile.row)) == .building,
              map.terrain(at: Tile(col: first - 1, row: tile.row + 1)) != .building {
            first -= 1
        }
        var last = tile.col
        while map.terrain(at: Tile(col: last + 1, row: tile.row)) == .building,
              map.terrain(at: Tile(col: last + 1, row: tile.row + 1)) != .building {
            last += 1
        }
        return tile.col == (first + last) / 2 ? "buildingDoor" : "buildingWall"
    }

    /// Fakes height: tall terrain casts a shadow onto the tile below it, and water gets a
    /// darker bank wherever it meets land.
    private func addDepthShading(at tile: Tile, terrain: Terrain) {
        func isTall(_ terrain: Terrain?) -> Bool {
            guard let terrain else { return false }
            return [.tree, .building, .fence].contains(terrain)
        }
        let above = map.terrain(at: Tile(col: tile.col, row: tile.row - 1))

        var shade: (alpha: CGFloat, height: CGFloat)?
        if isTall(above) && !isTall(terrain) {
            shade = (0.22, 0.22)
        } else if terrain == .water && above != nil && above != .water {
            shade = (0.3, 0.16)
        }
        guard let shade else { return }
        let strip = SKSpriteNode(color: UIColor.black.withAlphaComponent(shade.alpha),
                                 size: CGSize(width: Self.tileSize, height: Self.tileSize * shade.height))
        var position = point(for: tile)
        position.y += Self.tileSize * (0.5 - shade.height / 2)
        strip.position = position
        strip.zPosition = 0.5
        addChild(strip)
    }

    /// A stable pseudo-random value in 0...1 for a tile, so variation doesn't change between visits.
    private static func noise(_ tile: Tile, salt: Int = 0) -> CGFloat {
        let hash = (tile.col &* 73_856_093) ^ (tile.row &* 19_349_663) ^ (salt &* 83_492_791)
        return CGFloat(UInt(bitPattern: hash) % 1000) / 1000
    }

    /// A soft oval shadow that grounds a character or object on the map.
    private static func groundShadow() -> SKShapeNode {
        let shadow = SKShapeNode(ellipseOf: CGSize(width: tileSize * 0.62, height: tileSize * 0.2))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.28)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -tileSize * 0.34)
        shadow.zPosition = -1
        return shadow
    }

    private func color(for terrain: Terrain) -> UIColor {
        map.theme.look(for: terrain).color
    }

    private func decoration(for terrain: Terrain) -> (String, UIColor, CGFloat)? {
        let look = map.theme.look(for: terrain)
        guard let symbol = look.symbol else { return nil }
        return (symbol, look.tint, look.scale)
    }

    /// Arrows on each exit tile, plus one signpost per exit naming the region it leads to.
    private func buildExits() {
        for (tile, _) in map.exits {
            let arrow: SKSpriteNode
            if let art = Self.artTexture("marker_exit") {
                // The art points right; turn it to face the edge it leads off.
                arrow = SKSpriteNode(texture: art)
                arrow.size = CGSize(width: Self.tileSize * 2 / 3, height: Self.tileSize * 2 / 3)
                arrow.zRotation = arrowRotation(for: tile)
            } else {
                arrow = SKSpriteNode(texture: Self.symbolTexture(arrowSymbol(for: tile), color: .white))
                arrow.size = CGSize(width: Self.tileSize * 0.45, height: Self.tileSize * 0.45)
            }
            arrow.position = point(for: tile)
            arrow.zPosition = 1
            arrow.alpha = 0.85
            arrow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.7), .fadeAlpha(to: 0.85, duration: 0.7)])))
            addChild(arrow)
        }

        let groups = Dictionary(grouping: map.exits.keys, by: { map.exits[$0] ?? 0 })
        for (destination, tiles) in groups {
            guard let name = exitNames[destination], let first = tiles.min(by: { ($0.row, $0.col) < ($1.row, $1.col) }) else { continue }
            let label = Self.mapLabel(name, size: 12, alignment: .center)
            let background = SKNode()
            let labelWidth = label.calculateAccumulatedFrame().width
            if let board = Self.artTexture("ui_signpost") {
                // A wooden board stretched to fit the name. The 4 px border (with its rivets) isn't stretched.
                let sign = SKSpriteNode(texture: board)
                sign.centerRect = CGRect(x: 4.0 / 24, y: 4.0 / 16, width: 16.0 / 24, height: 8.0 / 16)
                sign.size = CGSize(width: labelWidth + 24, height: 32)
                background.addChild(sign)
            } else {
                let plate = SKShapeNode(rectOf: CGSize(width: labelWidth + 16, height: 22), cornerRadius: 11)
                plate.fillColor = UIColor.black.withAlphaComponent(0.55)
                plate.strokeColor = .clear
                background.addChild(plate)
            }
            background.addChild(label)
            background.zPosition = 8

            // Place the sign just inside the map, beside the exit.
            var anchor = point(for: first)
            if first.col == map.width - 1 {
                anchor.x -= Self.tileSize * 0.5 + background.calculateAccumulatedFrame().width / 2
                anchor.y += Self.tileSize * 0.5
            } else if first.row == map.height - 1 {
                anchor.x += Self.tileSize * 0.5
                anchor.y += Self.tileSize * 0.95
            }
            background.position = anchor
            addChild(background)
        }
    }

    private func arrowRotation(for tile: Tile) -> CGFloat {
        if tile.row == map.height - 1 { return -.pi / 2 }
        if tile.row == 0 { return .pi / 2 }
        if tile.col == 0 { return .pi }
        return 0
    }

    /// A white map label in the pixel font, with a 1 pt dark drop shadow so it reads on any ground.
    private static func mapLabel(_ text: String, size: CGFloat,
                                 alignment: SKLabelVerticalAlignmentMode = .baseline) -> SKLabelNode {
        func make(_ color: UIColor) -> SKLabelNode {
            let label = SKLabelNode(text: text)
            label.fontName = GameFont.mapLabelName
            label.fontSize = size
            label.fontColor = color
            label.verticalAlignmentMode = alignment
            return label
        }
        let label = make(.white)
        let shadow = make(UIColor.black.withAlphaComponent(0.7))
        shadow.position = CGPoint(x: 1, y: -1)
        shadow.zPosition = -0.1
        label.addChild(shadow)
        return label
    }

    private func arrowSymbol(for tile: Tile) -> String {
        if tile.row == map.height - 1 { return "chevron.down" }
        if tile.row == 0 { return "chevron.up" }
        if tile.col == 0 { return "chevron.left" }
        return "chevron.right"
    }

    private func buildEntities() {
        for (objectiveID, tile) in map.placements {
            guard let style = entityStyles[objectiveID] else { continue }
            let node = SKNode()
            node.position = point(for: tile)
            node.zPosition = 5
            node.addChild(Self.groundShadow())

            if let art = Self.artTexture(style.art ?? "npc_\(objectiveID)") {
                let sprite = SKSpriteNode(texture: art)
                sprite.size = CGSize(width: Self.tileSize, height: Self.tileSize)
                node.addChild(sprite)
            } else {
                let body = SKShapeNode(circleOfRadius: Self.tileSize * 0.4)
                body.fillColor = style.color
                body.strokeColor = .white
                body.lineWidth = 2
                node.addChild(body)

                let icon = SKSpriteNode(texture: Self.symbolTexture(style.symbol, color: .white))
                icon.size = CGSize(width: Self.tileSize * 0.45, height: Self.tileSize * 0.45)
                node.addChild(icon)
            }

            let label = Self.mapLabel(style.name, size: 11)
            label.position = CGPoint(x: 0, y: -Self.tileSize * 0.72)
            node.addChild(label)

            addChild(node)
            entityNodes[objectiveID] = node
        }
    }

    private func buildStations() {
        for (tile, facility) in map.stations {
            let node = SKNode()
            node.position = point(for: tile)
            node.zPosition = 5
            node.addChild(Self.groundShadow())

            if let art = Self.artTexture("station_\(facility.rawValue)") {
                let sprite = SKSpriteNode(texture: art)
                sprite.size = CGSize(width: Self.tileSize, height: Self.tileSize)
                node.addChild(sprite)
            } else {
                let base = SKShapeNode(rectOf: CGSize(width: Self.tileSize * 0.8, height: Self.tileSize * 0.8),
                                       cornerRadius: Self.tileSize * 0.2)
                base.fillColor = UIColor.systemTeal
                base.strokeColor = .white
                base.lineWidth = 2
                node.addChild(base)

                let icon = SKSpriteNode(texture: Self.symbolTexture(facility.symbol, color: .white))
                icon.size = CGSize(width: Self.tileSize * 0.45, height: Self.tileSize * 0.45)
                node.addChild(icon)
            }

            let label = Self.mapLabel(facility.name, size: 11)
            label.position = CGPoint(x: 0, y: -Self.tileSize * 0.72)
            node.addChild(label)
            addChild(node)
        }
    }

    private func buildTreasures() {
        for treasure in map.treasures {
            let art = Self.artTexture("chest")
            let node = SKSpriteNode(texture: art ?? Self.symbolTexture("shippingbox.fill", color: .systemYellow))
            // 16 px art fills the tile like the other map sprites; the symbol placeholder stays small.
            let side = art == nil ? Self.tileSize * 0.55 : Self.tileSize
            node.size = CGSize(width: side, height: side)
            node.position = point(for: treasure.tile)
            node.zPosition = 4
            let glint = SKAction.sequence([.scale(to: 1.12, duration: 0.6), .scale(to: 1, duration: 0.6)])
            node.run(.repeatForever(glint))
            addChild(node)
            treasureNodes[treasure.id] = node
        }
    }

    /// Shows looted chests with their lid open.
    func updateTreasures(opened: Set<String>) {
        for (id, node) in treasureNodes where opened.contains(id) {
            node.removeAllActions()
            // Stopping the glint can leave the chest mid-pulse.
            node.setScale(1)
            if let openArt = Self.artTexture("chest_open") {
                node.texture = openArt
            } else {
                node.texture = Self.symbolTexture("shippingbox", color: .white)
                node.alpha = 0.35
            }
        }
    }

    /// Pops a chest open with a little burst.
    func playTreasureOpened(_ id: String) {
        guard let node = treasureNodes[id] else { return }
        node.removeAllActions()
        playSparkle(at: node.position, tint: nil, symbolColor: .systemYellow, growTo: 1.8, duration: 0.5, zPosition: 12)
        node.run(.sequence([.scale(to: 1.4, duration: 0.12), .scale(to: 1, duration: 0.12)])) { [weak self] in
            self?.updateTreasures(opened: [id])
        }
    }

    /// A one-shot sparkle burst that grows and fades. Uses the animated `fx_sparkle_1…3` frames when
    /// they exist, then `fx_sparkle`, then an SF Symbol. `tint` recolors the art (e.g. purple for Blink).
    private func playSparkle(at position: CGPoint, tint: UIColor?, symbolColor: UIColor,
                             growTo scale: CGFloat, duration: TimeInterval, zPosition: CGFloat) {
        let frames = (1...3).compactMap { Self.artTexture("fx_sparkle_\($0)") }
        let art = frames.first ?? Self.artTexture("fx_sparkle")
        let sparkle = SKSpriteNode(texture: art ?? Self.symbolTexture("sparkles", color: symbolColor))
        sparkle.size = CGSize(width: Self.tileSize, height: Self.tileSize)
        sparkle.position = position
        sparkle.zPosition = zPosition
        if art != nil, let tint {
            sparkle.color = tint
            sparkle.colorBlendFactor = 0.6
        }
        addChild(sparkle)
        var effects: [SKAction] = [.scale(to: scale, duration: duration), .fadeOut(withDuration: duration)]
        if frames.count > 1 {
            effects.append(.animate(with: frames, timePerFrame: duration / Double(frames.count)))
        }
        sparkle.run(.sequence([.group(effects), .removeFromParent()]))
    }

    /// Breadcrumbs from the player to the nearest of `goals`, which fade after a few seconds.
    /// Returns `false` if there's no way there with the player's current abilities.
    @discardableResult
    func showTrail(toNeighborOf target: Tile?, orAnyOf goals: Set<Tile> = []) -> Bool {
        trailNodes.forEach { $0.removeFromParent() }
        trailNodes.removeAll()
        let steps: [Tile]?
        if let target {
            steps = map.path(from: playerTile, toNeighborOf: target, abilities: abilities, in: fieldState)
        } else {
            steps = map.path(from: playerTile, toAnyOf: goals, abilities: abilities, in: fieldState)
        }
        guard let steps else { return false }
        for (index, tile) in steps.enumerated() {
            let dot: SKNode
            if let art = Self.artTexture("marker_trail") {
                // 16 px art at 16 pt keeps each pixel whole.
                dot = SKSpriteNode(texture: art, size: CGSize(width: 16, height: 16))
            } else {
                let circle = SKShapeNode(circleOfRadius: Self.tileSize * 0.09)
                circle.fillColor = .systemYellow
                circle.strokeColor = .white
                circle.lineWidth = 1
                dot = circle
            }
            dot.position = point(for: tile)
            dot.zPosition = 3
            dot.alpha = 0
            dot.run(.sequence([
                .wait(forDuration: Double(index) * 0.03),
                .fadeAlpha(to: 0.95, duration: 0.15),
                .wait(forDuration: 3.5),
                .fadeOut(withDuration: 0.6),
                .removeFromParent(),
            ]))
            addChild(dot)
            trailNodes.append(dot)
        }
        return true
    }

    private func buildPlayer() {
        player.addChild(Self.groundShadow())

        if let art = Self.artTexture("player") {
            // Final art replaces the placeholder badge; the icon itself becomes the sprite.
            playerArt = art
            playerIcon.texture = art
            playerIcon.size = CGSize(width: Self.tileSize, height: Self.tileSize)
        } else {
            let body = SKShapeNode(circleOfRadius: Self.tileSize * 0.38)
            body.fillColor = .white
            body.strokeColor = playerColor
            body.lineWidth = 3
            player.addChild(body)

            playerIcon.texture = Self.symbolTexture(playerSymbol, color: playerColor)
            playerIcon.size = CGSize(width: Self.tileSize * 0.5, height: Self.tileSize * 0.5)
        }
        player.addChild(playerIcon)

        player.position = point(for: playerTile)
        player.zPosition = 10
        addChild(player)
        updatePlayerLook()
    }

    /// Swimming and flying change how the player looks, so it's clear a beast is carrying them.
    private func updatePlayerLook() {
        let onWater = isWaterNow(playerTile)
        let swimming = onWater && (map.theme.hasLiquidWater || map.isFlooded(playerTile, in: fieldState))
            && abilities.contains(.swim)
        if let playerArt {
            if onWater {
                playerIcon.texture = Self.artTexture(swimming ? "player_swim" : "player_fly") ?? playerArt
            } else {
                playerIcon.texture = playerArt
            }
            return
        }
        let symbol = onWater ? (swimming ? "figure.open.water.swim" : "bird.fill") : playerSymbol
        playerIcon.texture = Self.symbolTexture(symbol, color: playerColor)
    }

    /// Highlights the NPC or boss for the current quest step and dims finished ones.
    func updateQuestState(activeObjectiveID: String?, completed: Set<String>) {
        questMarker?.removeFromParent()
        questMarker = nil
        for (id, node) in entityNodes {
            node.alpha = completed.contains(id) ? 0.5 : 1
        }
        guard let activeObjectiveID, let node = entityNodes[activeObjectiveID] else { return }
        let marker = SKSpriteNode(texture: Self.artTexture("marker_quest")
                                  ?? Self.symbolTexture("exclamationmark.circle.fill", color: .systemYellow))
        marker.size = CGSize(width: Self.tileSize / 2, height: Self.tileSize / 2)
        marker.position = CGPoint(x: 0, y: Self.tileSize * 0.65)
        let bob = SKAction.sequence([.moveBy(x: 0, y: 5, duration: 0.5), .moveBy(x: 0, y: -5, duration: 0.5)])
        bob.timingMode = .easeInEaseOut
        marker.run(.repeatForever(bob))
        node.addChild(marker)
        questMarker = marker
    }

    // MARK: - Coordinates

    /// The scene position of a tile's center. Also used by map dressing such as the Arena Hall's crowd.
    func point(for tile: Tile) -> CGPoint {
        CGPoint(x: (CGFloat(tile.col) + 0.5) * Self.tileSize,
                y: (CGFloat(map.height - tile.row) - 0.5) * Self.tileSize)
    }

    private func tile(at point: CGPoint) -> Tile {
        Tile(col: Int(floor(point.x / Self.tileSize)),
             row: map.height - 1 - Int(floor(point.y / Self.tileSize)))
    }

    /// Follows the player but stops at the map edges (or centers a map smaller than the screen).
    private func cameraTarget() -> CGPoint {
        let mapSize = CGSize(width: CGFloat(map.width) * Self.tileSize, height: CGFloat(map.height) * Self.tileSize)
        func clamp(_ value: CGFloat, view: CGFloat, map: CGFloat) -> CGFloat {
            map <= view ? map / 2 : min(max(value, view / 2), map - view / 2)
        }
        return CGPoint(x: clamp(player.position.x, view: size.width, map: mapSize.width),
                       y: clamp(player.position.y, view: size.height, map: mapSize.height))
    }

    override func update(_ currentTime: TimeInterval) {
        cameraNode.position = cameraTarget()
        // Clamp the step so the cycles don't jump after the app was in the background.
        if let lastUpdateTime { clock += min(currentTime - lastUpdateTime, 0.1) }
        lastUpdateTime = currentTime
        darknessNode?.position = player.position
        updateFieldCycles()
    }

    // MARK: - Input

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isInputEnabled, let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Tapping an NPC, boss or station walks over and interacts, in either control mode.
        if let interaction = entity(near: location) {
            if case .boulder(let boulder) = interaction {
                approachBoulder(boulder)
                return
            }
            guard let steps = map.path(from: playerTile, toNeighborOf: tile(of: interaction), abilities: abilities, in: fieldState) else {
                reportBramblesIfClosed()
                return
            }
            route = steps
            pendingInteraction = interaction
            stepIfIdle()
            return
        }

        guard controlMode == .tap else { return }
        let tapped = tile(at: location)
        if isClosedBramble(tapped) {
            onFieldEvent?(.brambleBlocked)
            return
        }
        // Tapping water you can't cross explains which beast you'd need.
        if let needed = map.abilityNeeded(for: tapped, in: fieldState), !canEnter(tapped) {
            onBlocked?(needed)
            return
        }
        guard let target = nearestWalkableTile(to: location) else { return }
        if let steps = map.path(from: playerTile, toAnyOf: [target], abilities: abilities, in: fieldState) {
            route = steps
            pendingInteraction = nil
            showTapMarker(at: target)
            stepIfIdle()
        } else if abilities.contains(.teleport), chebyshev(playerTile, target) <= Self.blinkRange {
            // No way round on foot: a teleporting beast blinks you there.
            if !isMoving { blink(to: target) }
        } else {
            // Walled off: explain Blink (or that the spot is out of Blink range).
            onBlocked?(.teleport)
        }
    }

    private func tile(of interaction: Interaction) -> Tile {
        switch interaction {
        case .objective(let id): map.placements[id] ?? playerTile
        case .station(let tile), .boulder(let tile): tile
        }
    }

    private func chebyshev(_ a: Tile, _ b: Tile) -> Int {
        max(abs(a.col - b.col), abs(a.row - b.row))
    }

    /// The NPC, boss or station under (or very close to) a tap, so characters are easy to hit.
    private func entity(near location: CGPoint) -> Interaction? {
        let objectives = map.placements.map { (Interaction.objective($0.key), $0.value) }
        let stations = map.stations.keys.map { (Interaction.station($0), $0) }
        let boulders = fieldState.boulders.map { (Interaction.boulder($0), $0) }
        return (objectives + stations + boulders)
            .map { (interaction: $0.0, distance: distance(point(for: $0.1), location)) }
            .filter { $0.distance < Self.tileSize * 0.8 }
            .min { $0.distance < $1.distance }?
            .interaction
    }

    /// Taps that land on a wall, fence or water snap to the closest tile you can stand on,
    /// so you don't have to hit narrow doorways exactly.
    private func nearestWalkableTile(to location: CGPoint) -> Tile? {
        let tapped = tile(at: location)
        if canEnter(tapped) { return tapped }
        var best: (tile: Tile, distance: CGFloat)?
        for dRow in -2...2 {
            for dCol in -2...2 {
                let candidate = Tile(col: tapped.col + dCol, row: tapped.row + dRow)
                guard canEnter(candidate) else { continue }
                let d = distance(point(for: candidate), location)
                if d < (best?.distance ?? .infinity) { best = (candidate, d) }
            }
        }
        return best?.tile
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// The joystick's action button: talk to, challenge or use whatever is next to the player.
    func interactWithNearby() {
        guard isInputEnabled, !isMoving else { return }
        let ahead = playerTile.moved(facing)
        let candidates = [ahead] + playerTile.neighbors
        let interaction = candidates.lazy.compactMap { tile -> Interaction? in
            if let id = self.map.objectiveID(at: tile) { return .objective(id) }
            if self.map.stations[tile] != nil { return .station(tile) }
            return nil
        }.first
        if let interaction { interact(with: interaction) }
    }

    // MARK: - Accessibility

    /// Walks over to an NPC or boss and talks to or challenges it, like tapping it.
    /// Returns `false` if there's no way there. Used by the map's VoiceOver actions.
    @discardableResult
    func walkToInteract(objectiveID: String) -> Bool { approach(.objective(objectiveID)) }

    /// Walks over to a station and uses it.
    @discardableResult
    func walkToStation(at tile: Tile) -> Bool { approach(.station(tile)) }

    /// Walks to a tile such as a chest or exit, blinking there if it's walled in and in range.
    @discardableResult
    func walk(to tile: Tile) -> Bool {
        guard isInputEnabled else { return false }
        if let steps = map.path(from: playerTile, toAnyOf: [tile], abilities: abilities, in: fieldState) {
            route = steps
            pendingInteraction = nil
            stepIfIdle()
            return true
        }
        guard abilities.contains(.teleport), !isMoving, chebyshev(playerTile, tile) <= Self.blinkRange,
              canEnter(tile) else { return false }
        blink(to: tile)
        return true
    }

    /// One step in a direction, for VoiceOver users swiping on the joystick.
    func step(_ direction: StepDirection) {
        guard isInputEnabled, !isMoving else { return }
        face(direction)
        if pushBoulder(at: playerTile.moved(direction)) { return }
        if let next = assistedStep(toward: direction) { move(to: next) }
    }

    private func approach(_ interaction: Interaction) -> Bool {
        guard isInputEnabled,
              let steps = map.path(from: playerTile, toNeighborOf: tile(of: interaction), abilities: abilities, in: fieldState) else {
            reportBramblesIfClosed()
            return false
        }
        route = steps
        pendingInteraction = interaction
        stepIfIdle()
        return true
    }

    /// Teleport past whatever is in front of the player, up to a few tiles ahead.
    /// Returns `false` if there's nowhere to land.
    @discardableResult
    func blinkForward() -> Bool {
        guard isInputEnabled, !isMoving, abilities.contains(.teleport) else { return false }
        for distance in 2...Self.blinkRange {
            let landing = Tile(col: playerTile.col + facing.dx * distance, row: playerTile.row + facing.dy * distance)
            if canEnter(landing) {
                blink(to: landing)
                return true
            }
        }
        return false
    }

    private func blink(to tile: Tile) {
        route.removeAll()
        pendingInteraction = nil
        isMoving = true
        let from = player.position
        playerTile = tile
        playSparkle(at: from, tint: .systemPurple, symbolColor: .systemPurple, growTo: 1.6, duration: 0.3, zPosition: 11)
        player.run(.sequence([
            .group([.fadeOut(withDuration: 0.15), .scale(to: 0.3, duration: 0.15)]),
            .move(to: point(for: tile), duration: 0),
            .group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.15)]),
        ])) { [weak self] in
            guard let self else { return }
            self.isMoving = false
            self.updatePlayerLook()
            self.onBlink?()
            if let terrain = self.map.terrain(at: tile) { self.onStep?(tile, terrain) }
            self.stepIfIdle()
        }
    }

    private func showTapMarker(at tile: Tile) {
        let marker = SKShapeNode(circleOfRadius: Self.tileSize * 0.2)
        marker.strokeColor = .white
        marker.lineWidth = 2
        marker.position = point(for: tile)
        marker.zPosition = 2
        addChild(marker)
        marker.run(.sequence([.group([.scale(to: 1.8, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
    }

    // MARK: - Movement

    private func stepIfIdle() {
        guard !isMoving, isInputEnabled else { return }
        if !route.isEmpty {
            let next = route.removeFirst()
            if canEnter(next) { move(to: next) } else { route.removeAll() }
            return
        }
        if let interaction = pendingInteraction {
            pendingInteraction = nil
            interact(with: interaction)
            return
        }
        if let direction = heldDirection {
            face(direction)
            if pushBoulder(at: playerTile.moved(direction)) { return }
            if let next = assistedStep(toward: direction) { move(to: next) }
        }
    }

    /// The joystick's next step, with a little help so the player doesn't snag on walls:
    /// holding diagonally slides along a wall, and a doorway one tile to the side pulls you in.
    private func assistedStep(toward direction: StepDirection) -> Tile? {
        let ahead = playerTile.moved(direction)
        if canEnter(ahead) { return ahead }

        if let secondary = secondaryDirection, canEnter(playerTile.moved(secondary)) {
            return playerTile.moved(secondary)
        }

        // Prefer the side the stick leans toward, then either side.
        let sides = [secondaryDirection].compactMap { $0 } + direction.perpendicular
        for side in sides {
            let beside = playerTile.moved(side)
            if canEnter(beside), canEnter(beside.moved(direction)) { return beside }
        }
        if let needed = map.abilityNeeded(for: ahead, in: fieldState) { onBlocked?(needed) }
        if isClosedBramble(ahead) { onFieldEvent?(.brambleBlocked) }
        return nil
    }

    /// Steps onto `tile`. Gusts slide the keeper along instead of walking.
    private func move(to tile: Tile, carriedByGust: Bool = false) {
        if let direction = StepDirection.between(playerTile, tile) { face(direction) }
        // An erupting geyser or live arc throws the keeper back instead.
        if let event = activeHazard(at: tile) {
            stun(event)
            return
        }
        isMoving = true
        previousTile = playerTile
        playerTile = tile
        let duration = carriedByGust ? Self.stepDuration * 0.6 : Self.stepDuration
        if !carriedByGust {
            // A small hop each step so walking reads as walking, not sliding.
            let half = duration / 2
            let hop = SKAction.sequence([.moveBy(x: 0, y: 4, duration: half), .moveBy(x: 0, y: -4, duration: half)])
            playerIcon.run(hop)
        }
        player.run(.move(to: point(for: tile), duration: duration)) { [weak self] in
            guard let self else { return }
            self.isMoving = false
            self.updatePlayerLook()
            if let terrain = self.map.terrain(at: tile) { self.onStep?(tile, terrain) }
            self.lightBloom(at: tile)
            if self.ride(gustAt: tile, alreadyRiding: carriedByGust) { return }
            self.stepIfIdle()
        }
    }

    private func face(_ direction: StepDirection) {
        // Sliding sideways shouldn't change which way the player is "looking" for the A button.
        if let held = heldDirection, held != direction, route.isEmpty {
            facing = held
            return
        }
        facing = direction
        if direction == .left { playerIcon.xScale = -1 }
        if direction == .right { playerIcon.xScale = 1 }
    }

    private func interact(with interaction: Interaction) {
        if let direction = StepDirection.between(playerTile, tile(of: interaction)) {
            face(direction)
        }
        switch interaction {
        case .objective(let id): onInteract?(id)
        case .station(let tile): if let facility = map.stations[tile] { onFacility?(facility) }
        case .boulder(let tile): pushBoulder(at: tile)
        }
    }

    // MARK: - Element mechanics

    /// Whether the keeper can step onto `tile` right now, given their beasts and the puzzle's state.
    private func canEnter(_ tile: Tile) -> Bool {
        map.canEnter(tile, with: abilities, in: fieldState)
    }

    /// Real water (not filled in, not a gust), or tidal sand that's flooded right now.
    private func isWaterNow(_ tile: Tile) -> Bool {
        if map.isFlooded(tile, in: fieldState) { return true }
        return map.terrain(at: tile) == .water && map.features.gusts[tile] == nil && !fieldState.filled.contains(tile)
    }

    private func isClosedBramble(_ tile: Tile) -> Bool {
        !fieldState.bramblesOpen && map.features.brambles.contains(tile)
    }

    /// When a walk fails, closed brambles are the likely reason, so say so.
    private func reportBramblesIfClosed() {
        if !fieldState.bramblesOpen && !map.features.brambles.isEmpty { onFieldEvent?(.brambleBlocked) }
    }

    /// Opens the brambles straight away, for a puzzle the keeper solved on an earlier visit.
    func restoreOpenBrambles() {
        fieldState.bramblesOpen = true
        fieldState.litBlooms = map.features.blooms
        for node in brambleNodes.values { node.removeFromParent() }
        brambleNodes.removeAll()
        for (tile, node) in bloomNodes { styleBloom(node, lit: true, at: tile) }
    }

    /// Whether the region's Element Glyph has already been awakened. Set before presenting.
    var isGlyphClaimed = false {
        didSet { updateGlyph() }
    }

    /// Dims the Element Glyph once its beast has been awakened, otherwise makes it pulse.
    private func updateGlyph() {
        guard let glyphNode else { return }
        glyphNode.removeAction(forKey: "glow")
        glyphNode.alpha = isGlyphClaimed ? 0.35 : 1
        if !isGlyphClaimed {
            let glow = SKAction.sequence([.fadeAlpha(to: 0.65, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])
            glyphNode.run(.repeatForever(glow), withKey: "glow")
        }
    }

    /// Plays the glyph's awakening burst.
    func playGlyphAwakened() {
        guard let glyphNode else { return }
        playSparkle(at: glyphNode.position, tint: nil, symbolColor: .systemYellow, growTo: 2.4, duration: 0.7, zPosition: 32)
        isGlyphClaimed = true
    }

    private func buildFeatures() {
        let features = map.features
        let size = CGSize(width: Self.tileSize, height: Self.tileSize)

        for tile in features.geysers.keys {
            let vent = SKShapeNode(ellipseOf: CGSize(width: Self.tileSize * 0.6, height: Self.tileSize * 0.3))
            vent.fillColor = UIColor(red: 0.2, green: 0.1, blue: 0.08, alpha: 1)
            vent.strokeColor = .systemOrange
            vent.lineWidth = 2
            vent.position = point(for: tile)
            vent.zPosition = 2
            addChild(vent)
            let plume = SKSpriteNode(texture: Self.artTexture("feature_geyser")
                                     ?? Self.symbolTexture("flame.fill", color: .systemOrange))
            plume.size = CGSize(width: Self.tileSize * 0.8, height: Self.tileSize * 1.3)
            plume.anchorPoint = CGPoint(x: 0.5, y: 0.1)
            plume.position = CGPoint(x: 0, y: -Self.tileSize * 0.1)
            plume.zPosition = 9
            plume.setScale(0.01)
            plume.alpha = 0
            vent.addChild(plume)
            hazardNodes[tile] = plume
        }

        for tile in features.arcs.keys {
            let base = SKSpriteNode(texture: Self.artTexture("feature_arc")
                                    ?? Self.symbolTexture("bolt.fill", color: .systemYellow))
            base.size = CGSize(width: Self.tileSize * 0.7, height: Self.tileSize * 0.7)
            base.position = point(for: tile)
            base.zPosition = 4
            base.alpha = 0.25
            addChild(base)
            hazardNodes[tile] = base
        }

        for (tile, direction) in features.gusts {
            let arrow = SKSpriteNode(texture: Self.artTexture("feature_gust")
                                     ?? Self.symbolTexture("wind", color: UIColor.white.withAlphaComponent(0.85)))
            arrow.size = CGSize(width: Self.tileSize * 0.7, height: Self.tileSize * 0.7)
            arrow.position = point(for: tile)
            arrow.zRotation = switch direction {
            case .right: 0
            case .up: .pi / 2
            case .left: .pi
            case .down: -.pi / 2
            }
            arrow.zPosition = 3
            // Drifts the way it blows, so it's clear where it'll carry you.
            let drift = CGVector(dx: CGFloat(direction.dx) * 8, dy: CGFloat(-direction.dy) * 8)
            let reverse = CGVector(dx: -drift.dx, dy: -drift.dy)
            arrow.run(.repeatForever(.sequence([
                .group([.move(by: drift, duration: 0.5), .fadeAlpha(to: 0.4, duration: 0.5)]),
                .group([.move(by: reverse, duration: 0), .fadeAlpha(to: 1, duration: 0)]),
            ])))
            addChild(arrow)
        }

        for tile in features.boulders {
            let node = makeBoulderNode()
            node.position = point(for: tile)
            addChild(node)
            boulderNodes[tile] = node
        }

        for tile in features.brambles where !fieldState.bramblesOpen {
            let thorns = SKSpriteNode(texture: Self.artTexture("feature_bramble")
                                      ?? Self.symbolTexture("leaf.fill", color: UIColor(red: 0.15, green: 0.35, blue: 0.12, alpha: 1)))
            thorns.size = size
            thorns.position = point(for: tile)
            thorns.zPosition = 6
            let spikes = SKSpriteNode(texture: Self.symbolTexture("staroflife.fill", color: UIColor(red: 0.45, green: 0.25, blue: 0.1, alpha: 1)))
            spikes.size = CGSize(width: Self.tileSize * 0.45, height: Self.tileSize * 0.45)
            spikes.zPosition = 0.1
            thorns.addChild(spikes)
            addChild(thorns)
            brambleNodes[tile] = thorns
        }

        for tile in features.blooms {
            let bloom = SKSpriteNode()
            bloom.size = CGSize(width: Self.tileSize * 0.7, height: Self.tileSize * 0.7)
            bloom.position = point(for: tile)
            bloom.zPosition = 3
            styleBloom(bloom, lit: fieldState.litBlooms.contains(tile), at: tile)
            addChild(bloom)
            bloomNodes[tile] = bloom
        }

        for tile in features.tideFlats {
            let water = SKSpriteNode(color: MapTheme.coast.look(for: .water).color, size: size)
            water.position = point(for: tile)
            water.zPosition = 1.5
            water.alpha = 0
            let waves = SKSpriteNode(texture: Self.symbolTexture("water.waves", color: UIColor.white.withAlphaComponent(0.5)))
            waves.size = CGSize(width: Self.tileSize * 0.5, height: Self.tileSize * 0.5)
            water.addChild(waves)
            addChild(water)
            tideNodes.append(water)
        }

        if let glyph = map.glyph {
            let node = SKNode()
            node.position = point(for: glyph.tile)
            // Above the Spire's darkness, so its light draws the keeper in.
            node.zPosition = 31
            let tint = UIColor(glyph.species?.element.color ?? .yellow)
            let halo = SKShapeNode(circleOfRadius: Self.tileSize * 0.42)
            halo.fillColor = tint.withAlphaComponent(0.3)
            halo.strokeColor = tint
            halo.lineWidth = 2
            halo.glowWidth = 4
            node.addChild(halo)
            let stone = SKSpriteNode(texture: Self.artTexture("glyph_stone") ?? Self.symbolTexture("hexagon.fill", color: tint))
            stone.size = CGSize(width: Self.tileSize * 0.6, height: Self.tileSize * 0.6)
            stone.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 6)))
            node.addChild(stone)
            let label = Self.mapLabel("Element Glyph", size: 10)
            label.position = CGPoint(x: 0, y: -Self.tileSize * 0.72)
            node.addChild(label)
            addChild(node)
            glyphNode = node
            updateGlyph()
        }

        rebuildDarkness()
    }

    private func makeBoulderNode() -> SKNode {
        let node = SKNode()
        node.zPosition = 5
        node.addChild(Self.groundShadow())
        if let art = Self.artTexture("feature_boulder") {
            node.addChild(SKSpriteNode(texture: art, size: CGSize(width: Self.tileSize, height: Self.tileSize)))
        } else {
            let rock = SKShapeNode(circleOfRadius: Self.tileSize * 0.4)
            rock.fillColor = UIColor(red: 0.5, green: 0.44, blue: 0.38, alpha: 1)
            rock.strokeColor = UIColor(red: 0.3, green: 0.26, blue: 0.22, alpha: 1)
            rock.lineWidth = 3
            node.addChild(rock)
            let crack = SKSpriteNode(texture: Self.symbolTexture("bolt.horizontal.fill", color: UIColor(red: 0.3, green: 0.26, blue: 0.22, alpha: 1)))
            crack.size = CGSize(width: Self.tileSize * 0.4, height: Self.tileSize * 0.25)
            node.addChild(crack)
        }
        return node
    }

    private func styleBloom(_ node: SKSpriteNode, lit: Bool, at tile: Tile) {
        node.removeAllActions()
        node.texture = Self.artTexture(lit ? "feature_bloom_lit" : "feature_bloom")
            ?? Self.symbolTexture("camera.macro", color: lit ? .systemPink : UIColor.white.withAlphaComponent(0.8))
        node.setScale(1)
        if !lit {
            // Pulses until stepped on, so it reads as a switch.
            node.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.6), .scale(to: 1, duration: 0.6)])))
        }
    }

    /// The dark overlay with a soft hole of light around the keeper.
    private func rebuildDarkness() {
        darknessNode?.removeFromParent()
        darknessNode = nil
        guard map.features.isDark else { return }
        // Big enough to cover any screen wherever the keeper stands.
        let side: CGFloat = 3200
        let radius = lightRadius * Self.tileSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.5
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(red: 0.02, green: 0.01, blue: 0.05, alpha: 0.93).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            cg.setBlendMode(.destinationOut)
            let colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                let center = CGPoint(x: side / 2, y: side / 2)
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
        }
        let node = SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: side, height: side))
        node.zPosition = 30
        node.position = player.position
        addChild(node)
        darknessNode = node
    }

    /// The erupting geyser or live arc on `tile` right now, as the event it would cause.
    private func activeHazard(at tile: Tile) -> FieldEvent? {
        if let phase = map.features.geysers[tile], FieldTiming.isErupting(phase: phase, at: clock) { return .scorched }
        if let phase = map.features.arcs[tile], FieldTiming.isArcLive(phase: phase, at: clock) { return .zapped }
        return nil
    }

    /// Runs the geyser, arc and tide cycles, and throws the keeper off anything that turns dangerous.
    private func updateFieldCycles() {
        let features = map.features
        for (tile, phase) in features.geysers {
            setHazard(tile, on: FieldTiming.isErupting(phase: phase, at: clock))
        }
        for (tile, phase) in features.arcs {
            setHazard(tile, on: FieldTiming.isArcLive(phase: phase, at: clock))
        }
        if !features.tideFlats.isEmpty {
            let high = FieldTiming.isHighTide(at: clock)
            if high != fieldState.highTide {
                fieldState.highTide = high
                for node in tideNodes {
                    node.removeAllActions()
                    node.run(.fadeAlpha(to: high ? 0.9 : 0, duration: 1.2))
                }
                updatePlayerLook()
            }
            // Standing on the sandbar without a swimmer when the sea comes in: back to shore.
            if high, !isMoving, features.tideFlats.contains(playerTile), !canEnter(playerTile) { washAshore() }
        }
        if !isMoving, let event = activeHazard(at: playerTile) {
            // It erupted under the keeper: knocked back to where they came from.
            if let back = previousTile, canEnter(back), activeHazard(at: back) == nil {
                knockBack(to: back, event: event)
            } else {
                stun(event)
            }
        }
    }

    private func setHazard(_ tile: Tile, on: Bool) {
        guard hazardOn[tile] != on, let node = hazardNodes[tile] else { return }
        hazardOn[tile] = on
        node.removeAllActions()
        if map.features.geysers[tile] != nil {
            node.run(on
                ? .group([.scale(to: 1, duration: 0.15), .fadeIn(withDuration: 0.1)])
                : .group([.scale(to: 0.01, duration: 0.3), .fadeOut(withDuration: 0.3)]))
        } else {
            node.alpha = on ? 1 : 0.25
            if on {
                node.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.06), .fadeAlpha(to: 1, duration: 0.06)])))
            }
        }
    }

    /// The keeper reels for a moment: stopped, shaking, unable to move.
    private func stun(_ event: FieldEvent) {
        route.removeAll()
        pendingInteraction = nil
        isMoving = true
        onFieldEvent?(event)
        let tint: UIColor = event == .zapped ? .systemYellow : .systemOrange
        playSparkle(at: player.position, tint: tint, symbolColor: tint, growTo: 1.4, duration: 0.3, zPosition: 11)
        let shake = SKAction.sequence([.moveBy(x: -4, y: 0, duration: 0.05), .moveBy(x: 8, y: 0, duration: 0.1),
                                       .moveBy(x: -4, y: 0, duration: 0.05)])
        playerIcon.run(.sequence([.repeat(shake, count: 2), .wait(forDuration: 0.2)])) { [weak self] in
            self?.isMoving = false
            self?.stepIfIdle()
        }
    }

    private func knockBack(to tile: Tile, event: FieldEvent) {
        route.removeAll()
        pendingInteraction = nil
        isMoving = true
        previousTile = nil
        playerTile = tile
        player.run(.move(to: point(for: tile), duration: 0.15)) { [weak self] in
            guard let self else { return }
            self.isMoving = false
            self.updatePlayerLook()
            self.stun(event)
        }
    }

    /// The tide carried the keeper back to the nearest dry tile.
    private func washAshore() {
        var queue = [playerTile]
        var seen: Set<Tile> = [playerTile]
        var head = 0
        var shore: Tile?
        while head < queue.count, shore == nil {
            let current = queue[head]
            head += 1
            for next in current.neighbors where !seen.contains(next) && map.terrain(at: next) != nil {
                seen.insert(next)
                if canEnter(next) && !map.features.tideFlats.contains(next) {
                    shore = next
                    break
                }
                queue.append(next)
            }
        }
        guard let shore else { return }
        route.removeAll()
        pendingInteraction = nil
        isMoving = true
        playerTile = shore
        onFieldEvent?(.washedAshore)
        player.run(.move(to: point(for: shore), duration: 0.5)) { [weak self] in
            self?.isMoving = false
            self?.updatePlayerLook()
            self?.stepIfIdle()
        }
    }

    /// Landing on a gust carries the keeper on. Returns `true` if it did.
    private func ride(gustAt tile: Tile, alreadyRiding: Bool) -> Bool {
        guard isInputEnabled, let direction = map.features.gusts[tile] else { return false }
        let next = tile.moved(direction)
        guard canEnter(next) else { return false }
        if !alreadyRiding { onFieldEvent?(.gust) }
        // Routes are planned with the gusts in mind; anything else is blown off course.
        if route.first == next {
            route.removeFirst()
        } else {
            route.removeAll()
            pendingInteraction = nil
        }
        move(to: next, carriedByGust: true)
        return true
    }

    private func lightBloom(at tile: Tile) {
        guard map.features.blooms.contains(tile), !fieldState.litBlooms.contains(tile), !fieldState.bramblesOpen else { return }
        fieldState.litBlooms.insert(tile)
        if let node = bloomNodes[tile] {
            styleBloom(node, lit: true, at: tile)
            playSparkle(at: node.position, tint: .systemPink, symbolColor: .systemPink, growTo: 1.8, duration: 0.5, zPosition: 12)
        }
        let remaining = map.features.blooms.subtracting(fieldState.litBlooms).count
        guard remaining == 0 else {
            onFieldEvent?(.bloomLit(remaining: remaining))
            return
        }
        fieldState.bramblesOpen = true
        for (tile, node) in brambleNodes {
            playSparkle(at: point(for: tile), tint: .systemGreen, symbolColor: .systemGreen, growTo: 1.6, duration: 0.5, zPosition: 12)
            node.run(.sequence([.group([.scale(to: 0.1, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
        brambleNodes.removeAll()
        onFieldEvent?(.bramblesOpened)
    }

    /// Where a boulder at `boulder` would go if pushed from `from`, or `nil` if it can't move.
    private func pushDestination(of boulder: Tile, from: Tile) -> Tile? {
        guard let direction = StepDirection.between(from, boulder) else { return nil }
        let target = boulder.moved(direction)
        guard let terrain = map.terrain(at: target), !map.isOccupied(target), !fieldState.boulders.contains(target),
              map.doors[target] == nil, map.exits[target] == nil, map.treasure(at: target) == nil,
              map.glyph?.tile != target, !isClosedBramble(target), map.features.gusts[target] == nil,
              map.features.geysers[target] == nil, map.features.arcs[target] == nil else { return nil }
        return terrain.isWalkable || terrain == .water || fieldState.filled.contains(target) ? target : nil
    }

    /// Pushes the boulder at `tile` away from the keeper, if there is one next to them.
    /// Returns `true` if `tile` held a boulder (pushed or stuck), so the caller doesn't also walk there.
    @discardableResult
    private func pushBoulder(at tile: Tile) -> Bool {
        guard fieldState.boulders.contains(tile), !isMoving else { return false }
        guard let target = pushDestination(of: tile, from: playerTile), let node = boulderNodes[tile] else {
            onFieldEvent?(.boulderStuck)
            return true
        }
        fieldState.boulders.remove(tile)
        boulderNodes[tile] = nil
        let sinks = map.terrain(at: target) == .water && !fieldState.filled.contains(target)
        if sinks {
            // Filling the water: the boulder becomes solid ground.
            fieldState.filled.insert(target)
            node.run(.sequence([.move(to: point(for: target), duration: Self.stepDuration),
                                .group([.scale(to: 0.85, duration: 0.25), .fadeAlpha(to: 0.7, duration: 0.25)])]))
            node.zPosition = 1.6
            onFieldEvent?(.boulderSank)
        } else {
            fieldState.boulders.insert(target)
            boulderNodes[target] = node
            node.run(.move(to: point(for: target), duration: Self.stepDuration))
            onFieldEvent?(.boulderPushed)
        }
        move(to: tile)
        return true
    }

    /// Walks round to the far side of a tapped boulder and pushes it.
    private func approachBoulder(_ boulder: Tile) {
        if StepDirection.between(playerTile, boulder) != nil {
            pushBoulder(at: boulder)
            return
        }
        let spots = boulder.neighbors.filter { canEnter($0) && pushDestination(of: boulder, from: $0) != nil }
        let best = spots.compactMap { spot in
            map.path(from: playerTile, toAnyOf: [spot], abilities: abilities, in: fieldState).map { (spot, $0) }
        }.min { $0.1.count < $1.1.count }
        guard let (_, steps) = best else {
            onFieldEvent?(.boulderStuck)
            return
        }
        route = steps
        pendingInteraction = .boulder(boulder)
        stepIfIdle()
    }

    // MARK: - Art

    private static var textureCache: [String: SKTexture] = [:]

    /// Placeholder art: SF Symbols rendered into textures until real sprites exist.
    static func symbolTexture(_ name: String, color: UIColor) -> SKTexture {
        let key = "\(name)-\(color.description)"
        if let cached = textureCache[key] { return cached }
        let configuration = UIImage.SymbolConfiguration(pointSize: 64, weight: .bold)
        let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
        let texture = SKTexture(image: image)
        textureCache[key] = texture
        return texture
    }

    private static var artCache: [String: SKTexture?] = [:]

    /// Final art from the asset catalog, or `nil` if that image hasn't been added yet.
    /// Small images are treated as pixel art and scaled without smoothing.
    static func artTexture(_ name: String) -> SKTexture? {
        if let cached = artCache[name] { return cached }
        let texture = UIImage(named: name).map { image in
            let texture = SKTexture(image: image)
            texture.filteringMode = GameArt.isPixelArt(image) ? .nearest : .linear
            return texture
        }
        artCache[name] = texture
        return texture
    }
}

private extension UIColor {
    func adjustingBrightness(by amount: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: min(max(brightness + amount, 0), 1), alpha: alpha)
    }
}

// MARK: - Region themes

/// How one kind of terrain is drawn: a ground color plus an optional SF Symbol decoration.
struct TerrainLook {
    let color: UIColor
    var symbol: String? = nil
    var tint: UIColor = .clear
    var scale: CGFloat = 0.5
}

private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(red: red, green: green, blue: blue, alpha: alpha)
}

extension MapTheme {
    func look(for terrain: Terrain) -> TerrainLook {
        switch (self, terrain) {
        // Beast Haven: orchards and meadows.
        case (.meadow, .grass): TerrainLook(color: rgb(0.45, 0.72, 0.38))
        case (.meadow, .tallGrass): TerrainLook(color: rgb(0.3, 0.58, 0.27), symbol: "leaf.fill", tint: rgb(0.2, 0.45, 0.18), scale: 0.45)
        case (.meadow, .path): TerrainLook(color: rgb(0.82, 0.72, 0.52))
        case (.meadow, .flowers): TerrainLook(color: rgb(0.45, 0.72, 0.38), symbol: "camera.macro", tint: .systemPink, scale: 0.45)
        case (.meadow, .tree): TerrainLook(color: rgb(0.2, 0.42, 0.22), symbol: "tree.fill", tint: rgb(0.1, 0.3, 0.12), scale: 0.8)
        case (.meadow, .water): TerrainLook(color: rgb(0.3, 0.55, 0.85), symbol: "water.waves", tint: rgb(1, 1, 1, 0.5))
        case (.meadow, .fence): TerrainLook(color: rgb(0.55, 0.38, 0.22), symbol: "square.split.1x2.fill", tint: rgb(0.4, 0.26, 0.14), scale: 0.6)
        case (.meadow, .building): TerrainLook(color: rgb(0.7, 0.25, 0.2))

        // Emberfall Caldera: ash, ember fields and lava.
        case (.volcano, .grass): TerrainLook(color: rgb(0.42, 0.33, 0.3))
        case (.volcano, .tallGrass): TerrainLook(color: rgb(0.52, 0.3, 0.22), symbol: "flame.fill", tint: .systemOrange, scale: 0.4)
        case (.volcano, .path): TerrainLook(color: rgb(0.6, 0.5, 0.42))
        case (.volcano, .flowers): TerrainLook(color: rgb(0.42, 0.33, 0.3), symbol: "sparkle", tint: .systemOrange, scale: 0.4)
        case (.volcano, .tree): TerrainLook(color: rgb(0.28, 0.2, 0.18), symbol: "mountain.2.fill", tint: rgb(0.18, 0.13, 0.12), scale: 0.75)
        case (.volcano, .water): TerrainLook(color: rgb(0.95, 0.4, 0.1), symbol: "flame.fill", tint: .systemYellow, scale: 0.45)
        case (.volcano, .fence): TerrainLook(color: rgb(0.15, 0.12, 0.14))
        case (.volcano, .building): TerrainLook(color: rgb(0.55, 0.32, 0.26))

        // Tidewhisper Coast: sand, dunes and the grey sea.
        case (.coast, .grass): TerrainLook(color: rgb(0.92, 0.85, 0.62))
        case (.coast, .tallGrass): TerrainLook(color: rgb(0.72, 0.76, 0.48), symbol: "leaf.fill", tint: rgb(0.45, 0.55, 0.3), scale: 0.45)
        case (.coast, .path): TerrainLook(color: rgb(0.62, 0.47, 0.32), symbol: "square.split.1x2", tint: rgb(0.45, 0.33, 0.22), scale: 0.7)
        case (.coast, .flowers): TerrainLook(color: rgb(0.92, 0.85, 0.62), symbol: "star.fill", tint: .systemOrange, scale: 0.35)
        case (.coast, .tree): TerrainLook(color: rgb(0.85, 0.78, 0.55), symbol: "tree.fill", tint: rgb(0.3, 0.55, 0.3), scale: 0.8)
        case (.coast, .water): TerrainLook(color: rgb(0.45, 0.55, 0.62), symbol: "water.waves", tint: rgb(1, 1, 1, 0.5))
        case (.coast, .fence): TerrainLook(color: rgb(0.5, 0.38, 0.25))
        case (.coast, .building): TerrainLook(color: rgb(0.3, 0.5, 0.7))

        // Greenmantle Wilds: deep forest and overgrown ruins.
        case (.forest, .grass): TerrainLook(color: rgb(0.3, 0.55, 0.3))
        case (.forest, .tallGrass): TerrainLook(color: rgb(0.2, 0.42, 0.2), symbol: "leaf.fill", tint: rgb(0.12, 0.3, 0.12), scale: 0.5)
        case (.forest, .path): TerrainLook(color: rgb(0.55, 0.42, 0.28))
        case (.forest, .flowers): TerrainLook(color: rgb(0.3, 0.55, 0.3), symbol: "camera.macro", tint: .systemPurple, scale: 0.45)
        case (.forest, .tree): TerrainLook(color: rgb(0.12, 0.3, 0.15), symbol: "tree.fill", tint: rgb(0.05, 0.2, 0.08), scale: 0.85)
        case (.forest, .water): TerrainLook(color: rgb(0.25, 0.5, 0.6), symbol: "water.waves", tint: rgb(1, 1, 1, 0.4))
        case (.forest, .fence): TerrainLook(color: rgb(0.25, 0.3, 0.15))
        case (.forest, .building): TerrainLook(color: rgb(0.5, 0.52, 0.45), symbol: "circle.hexagongrid.fill", tint: .systemGreen, scale: 0.6)

        // Skyreach Peaks: rock, snowdrifts and a cloud-filled chasm.
        case (.peaks, .grass): TerrainLook(color: rgb(0.62, 0.63, 0.66))
        case (.peaks, .tallGrass): TerrainLook(color: rgb(0.9, 0.93, 0.97), symbol: "snowflake", tint: rgb(0.55, 0.7, 0.9), scale: 0.4)
        case (.peaks, .path): TerrainLook(color: rgb(0.75, 0.72, 0.68))
        case (.peaks, .flowers): TerrainLook(color: rgb(0.62, 0.63, 0.66), symbol: "wind", tint: .white, scale: 0.45)
        case (.peaks, .tree): TerrainLook(color: rgb(0.38, 0.38, 0.43), symbol: "mountain.2.fill", tint: rgb(0.85, 0.88, 0.92), scale: 0.75)
        case (.peaks, .water): TerrainLook(color: rgb(0.15, 0.18, 0.28), symbol: "cloud.fill", tint: rgb(1, 1, 1, 0.35), scale: 0.6)
        case (.peaks, .fence): TerrainLook(color: rgb(0.45, 0.35, 0.25))
        case (.peaks, .building): TerrainLook(color: rgb(0.35, 0.35, 0.42), symbol: "airplane", tint: rgb(0.6, 0.6, 0.65), scale: 0.5)

        // Gravel Hollow: quarry gravel, rubble and flooded pits.
        case (.quarry, .grass): TerrainLook(color: rgb(0.62, 0.55, 0.45))
        case (.quarry, .tallGrass): TerrainLook(color: rgb(0.5, 0.44, 0.36), symbol: "circle.grid.2x2.fill", tint: rgb(0.38, 0.33, 0.27), scale: 0.4)
        case (.quarry, .path): TerrainLook(color: rgb(0.72, 0.67, 0.56))
        case (.quarry, .flowers): TerrainLook(color: rgb(0.62, 0.55, 0.45), symbol: "gearshape.fill", tint: .gray, scale: 0.4)
        case (.quarry, .tree): TerrainLook(color: rgb(0.38, 0.32, 0.26), symbol: "mountain.2.fill", tint: rgb(0.28, 0.23, 0.18), scale: 0.75)
        case (.quarry, .water): TerrainLook(color: rgb(0.25, 0.35, 0.4), symbol: "water.waves", tint: rgb(1, 1, 1, 0.3))
        case (.quarry, .fence): TerrainLook(color: rgb(0.3, 0.3, 0.32), symbol: "square.split.1x2.fill", tint: rgb(0.2, 0.2, 0.22), scale: 0.6)
        case (.quarry, .building): TerrainLook(color: rgb(0.35, 0.35, 0.38), symbol: "circle", tint: rgb(0.6, 0.6, 0.62), scale: 0.4)

        // Voltmarsh: bog, charged reeds and dead trees.
        case (.marsh, .grass): TerrainLook(color: rgb(0.34, 0.42, 0.3))
        case (.marsh, .tallGrass): TerrainLook(color: rgb(0.26, 0.36, 0.22), symbol: "bolt.fill", tint: .systemYellow, scale: 0.4)
        case (.marsh, .path): TerrainLook(color: rgb(0.48, 0.42, 0.33))
        case (.marsh, .flowers): TerrainLook(color: rgb(0.34, 0.42, 0.3), symbol: "bolt.fill", tint: .cyan, scale: 0.35)
        case (.marsh, .tree): TerrainLook(color: rgb(0.2, 0.25, 0.18), symbol: "tree", tint: rgb(0.45, 0.45, 0.4), scale: 0.8)
        case (.marsh, .water): TerrainLook(color: rgb(0.22, 0.34, 0.3), symbol: "water.waves", tint: rgb(0.6, 0.9, 0.6, 0.4))
        case (.marsh, .fence): TerrainLook(color: rgb(0.3, 0.3, 0.25))
        case (.marsh, .building): TerrainLook(color: rgb(0.3, 0.3, 0.36), symbol: "bolt.circle.fill", tint: .systemYellow, scale: 0.5)

        // Null Spire: glyph floors suspended over the void.
        case (.spire, .grass): TerrainLook(color: rgb(0.22, 0.19, 0.28))
        case (.spire, .tallGrass): TerrainLook(color: rgb(0.3, 0.22, 0.38), symbol: "circle.dotted", tint: .systemPurple, scale: 0.5)
        case (.spire, .path): TerrainLook(color: rgb(0.36, 0.3, 0.46), symbol: "square.grid.3x3", tint: rgb(0.6, 0.5, 0.8, 0.5), scale: 0.6)
        case (.spire, .flowers): TerrainLook(color: rgb(0.22, 0.19, 0.28), symbol: "sparkles", tint: rgb(0.8, 0.7, 1), scale: 0.4)
        case (.spire, .tree): TerrainLook(color: rgb(0.13, 0.1, 0.18), symbol: "diamond.fill", tint: rgb(0.4, 0.25, 0.55), scale: 0.6)
        case (.spire, .water): TerrainLook(color: rgb(0.04, 0.03, 0.07), symbol: "circle.dotted", tint: rgb(0.5, 0.5, 0.6, 0.3), scale: 0.4)
        case (.spire, .fence): TerrainLook(color: rgb(0.4, 0.3, 0.5))
        case (.spire, .building): TerrainLook(color: rgb(0.3, 0.25, 0.4))

        // Inside buildings: plank floors, rugs, potted plants, counters and walls.
        case (.interior, .grass), (.interior, .tallGrass): TerrainLook(color: rgb(0.6, 0.44, 0.3))
        case (.interior, .path): TerrainLook(color: rgb(0.62, 0.22, 0.2), symbol: "square.grid.3x3.fill", tint: rgb(0.8, 0.55, 0.3, 0.5), scale: 0.7)
        case (.interior, .flowers): TerrainLook(color: rgb(0.6, 0.44, 0.3), symbol: "leaf.fill", tint: rgb(0.25, 0.55, 0.25), scale: 0.6)
        case (.interior, .tree): TerrainLook(color: rgb(0.32, 0.22, 0.16))
        case (.interior, .water): TerrainLook(color: rgb(0.4, 0.65, 0.85), symbol: "water.waves", tint: rgb(1, 1, 1, 0.5))
        case (.interior, .fence): TerrainLook(color: rgb(0.45, 0.3, 0.18), symbol: "rectangle.fill", tint: rgb(0.55, 0.38, 0.24), scale: 0.8)
        case (.interior, .building): TerrainLook(color: rgb(0.32, 0.22, 0.16))
        }
    }
}
