//
//  ArenaHallAmbience.swift
//  Beastopia
//

import SpriteKit
import UIKit

/// Dressing that brings the Arena Hall to life: a crowd in the arena building's stands, banners on its front wall,
/// torches on the ring's corners, spotlights sweeping the sand and dust drifting through the light.
/// Only the Arena Hall uses this; story regions don't call it.
extension AdventureScene {
    private static let spectatorName = "arena.spectator"
    private static let crowdColors: [UIColor] = [
        .systemOrange, .systemPurple, .systemTeal, .systemRed, .systemYellow, .systemBlue, .systemPink, .systemGreen,
    ]
    /// Front-wall tiles of the arena building that carry a hanging banner, either side of its door.
    private static let bannerTiles = [Tile(col: 8, row: 3), Tile(col: 11, row: 3)]
    /// The columns the arena building (and so its crowd) covers.
    private static let standColumns = 8...11
    /// The four corners of the ring's fence.
    private static let torchTiles = [Tile(col: 2, row: 5), Tile(col: 17, row: 5), Tile(col: 2, row: 9), Tile(col: 17, row: 9)]
    /// The sand inside the ring, which the spotlights sweep.
    private static let ringColumns = 3...16
    private static let ringRows = 6...8

    /// Adds the crowd, banners, torches, spotlights and dust. Call once, right after creating the scene.
    func addArenaAmbience() {
        addCrowd()
        addBanners()
        addTorches()
        addSpotlights()
        addDust()
        // Now and then a section of the stands gets excited on its own.
        let wave = SKAction.sequence([
            .wait(forDuration: 7, withRange: 6),
            .run { [weak self] in self?.cheerCrowd(nearColumn: .random(in: Self.standColumns), spread: 1) },
        ])
        run(.repeatForever(wave), withKey: "arena.crowdWave")
    }

    /// Spectators within `spread` columns of `column` jump up and throw their arms in the air.
    /// Pass `nil` to make the whole crowd cheer.
    func cheerCrowd(nearColumn column: Int?, spread: Int = 3) {
        let cheering = Self.symbolTexture("figure.arms.open", color: .white)
        enumerateChildNodes(withName: Self.spectatorName) { node, _ in
            guard let seatColumn = node.userData?["col"] as? Int,
                  column.map({ abs($0 - seatColumn) <= spread }) ?? true,
                  let figure = node.children.first as? SKSpriteNode,
                  figure.action(forKey: "cheer") == nil,
                  let resting = figure.texture else { return }
            let jump = SKAction.sequence([.moveTo(y: 7, duration: 0.12), .moveTo(y: 0, duration: 0.14)])
            figure.run(.sequence([
                .wait(forDuration: .random(in: 0...0.3)),
                .setTexture(cheering),
                jump, jump,
                .setTexture(resting),
            ]), withKey: "cheer")
        }
    }

    /// Whether a tile is on the ring's sand.
    static func isInArenaRing(_ tile: Tile) -> Bool {
        ringColumns.contains(tile.col) && ringRows.contains(tile.row)
    }

    // MARK: - Pieces

    /// Two spectators on every seat tile of the stands (building tiles that aren't the front wall),
    /// leaving out any that would stand off the edge of the arena building's art.
    private func addCrowd() {
        let standing = Self.symbolTexture("person.fill", color: .white)
        let buildingFrame = childNode(withName: Self.buildingArtName)?.frame
        for row in 0..<map.height {
            for col in 0..<map.width {
                let tile = Tile(col: col, row: row)
                guard map.terrain(at: tile) == .building,
                      map.terrain(at: Tile(col: col, row: row + 1)) == .building else { continue }
                for side: CGFloat in [-1, 1] {
                    let seat = SKNode()
                    var position = point(for: tile)
                    position.x += side * Self.tileSize * 0.22
                    position.y += CGFloat.random(in: -4...4)
                    if let buildingFrame, !buildingFrame.insetBy(dx: Self.tileSize * 0.15, dy: 0).contains(position) {
                        continue
                    }
                    seat.position = position
                    seat.zPosition = 2
                    seat.name = Self.spectatorName
                    seat.userData = ["col": col]

                    let figure = SKSpriteNode(texture: standing)
                    figure.size = CGSize(width: Self.tileSize * 0.4, height: Self.tileSize * 0.4)
                    figure.color = Self.crowdColors.randomElement() ?? .systemOrange
                    figure.colorBlendFactor = 1
                    seat.addChild(figure)

                    // A gentle, out-of-step sway so the stands never look frozen.
                    let sway = SKAction.sequence([.moveBy(x: 0, y: 1.5, duration: 0.6), .moveBy(x: 0, y: -1.5, duration: 0.6)])
                    seat.run(.sequence([.wait(forDuration: .random(in: 0...1.2)), .repeatForever(sway)]))
                    addChild(seat)
                }
            }
        }
    }

    /// Host-colored banners hanging from the stand walls, swaying slightly.
    private func addBanners() {
        let colors: [UIColor] = [.systemOrange, .systemPurple]
        for (tile, color) in zip(Self.bannerTiles, colors) {
            let banner = SKSpriteNode(color: color.withAlphaComponent(0.9),
                                      size: CGSize(width: Self.tileSize * 0.42, height: Self.tileSize * 0.72))
            banner.anchorPoint = CGPoint(x: 0.5, y: 1)
            var position = point(for: tile)
            position.y += Self.tileSize * 0.42
            banner.position = position
            banner.zPosition = 2

            let emblem = SKSpriteNode(texture: Self.symbolTexture("pawprint.fill", color: .white))
            emblem.size = CGSize(width: Self.tileSize * 0.26, height: Self.tileSize * 0.26)
            emblem.position = CGPoint(x: 0, y: -Self.tileSize * 0.36)
            banner.addChild(emblem)

            let sway = SKAction.sequence([
                .rotate(toAngle: 0.07, duration: 1.4, shortestUnitArc: true),
                .rotate(toAngle: -0.07, duration: 1.4, shortestUnitArc: true),
            ])
            sway.timingMode = .easeInEaseOut
            banner.run(.sequence([.wait(forDuration: .random(in: 0...1.4)), .repeatForever(sway)]))
            addChild(banner)
        }
    }

    /// A flickering torch with a warm glow on each corner of the ring's fence.
    private func addTorches() {
        for tile in Self.torchTiles {
            let torch = SKNode()
            torch.position = point(for: tile)
            torch.zPosition = 4

            let glow = SKShapeNode(circleOfRadius: Self.tileSize * 0.9)
            glow.fillColor = UIColor.systemOrange.withAlphaComponent(0.22)
            glow.strokeColor = .clear
            glow.blendMode = .add
            glow.position = CGPoint(x: 0, y: Self.tileSize * 0.2)
            glow.zPosition = -2.4
            let flicker = SKAction.sequence((0..<6).map { _ in
                .fadeAlpha(to: .random(in: 0.55...1), duration: .random(in: 0.08...0.2))
            })
            glow.run(.repeatForever(flicker))
            torch.addChild(glow)

            let post = SKSpriteNode(color: UIColor(white: 0.18, alpha: 1),
                                    size: CGSize(width: Self.tileSize * 0.14, height: Self.tileSize * 0.5))
            post.position = CGPoint(x: 0, y: -Self.tileSize * 0.05)
            torch.addChild(post)

            let flame = Self.flameEmitter()
            flame.position = CGPoint(x: 0, y: Self.tileSize * 0.22)
            torch.addChild(flame)
            addChild(torch)
        }
    }

    /// Two soft spotlights sweeping back and forth across the ring, out of step with each other.
    private func addSpotlights() {
        let left = point(for: Tile(col: Self.ringColumns.lowerBound + 1, row: Self.ringRows.lowerBound))
        let right = point(for: Tile(col: Self.ringColumns.upperBound - 1, row: Self.ringRows.upperBound))
        for (index, start) in [left, right].enumerated() {
            let spot = SKShapeNode(ellipseOf: CGSize(width: Self.tileSize * 3, height: Self.tileSize * 1.7))
            spot.fillColor = UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 0.14)
            spot.strokeColor = .clear
            spot.blendMode = .add
            spot.position = start
            spot.zPosition = 1.5

            let end = index == 0 ? right : left
            let there = SKAction.move(to: end, duration: 4.5)
            let back = SKAction.move(to: start, duration: 4.5)
            there.timingMode = .easeInEaseOut
            back.timingMode = .easeInEaseOut
            spot.run(.repeatForever(.sequence([there, back])))
            addChild(spot)
        }
    }

    /// Dust motes drifting through the whole hall.
    private func addDust() {
        let dust = SKEmitterNode()
        dust.particleTexture = Self.softDot
        dust.particleBirthRate = 5
        dust.particleLifetime = 9
        dust.particleLifetimeRange = 3
        dust.particleSpeed = 6
        dust.particleSpeedRange = 4
        dust.emissionAngleRange = .pi * 2
        dust.particleScale = 0.18
        dust.particleScaleRange = 0.12
        dust.particleAlpha = 0
        dust.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.35, 0], times: [0, 0.5, 1])
        dust.particleColor = UIColor(red: 1, green: 0.92, blue: 0.75, alpha: 1)
        dust.particleColorBlendFactor = 1
        dust.particleBlendMode = .add
        dust.particlePositionRange = CGVector(dx: CGFloat(map.width) * Self.tileSize, dy: CGFloat(map.height) * Self.tileSize)
        dust.position = CGPoint(x: CGFloat(map.width) * Self.tileSize / 2, y: CGFloat(map.height) * Self.tileSize / 2)
        dust.zPosition = 15
        // Start with the air already full rather than motes slowly appearing.
        dust.advanceSimulationTime(9)
        addChild(dust)
    }

    private static func flameEmitter() -> SKEmitterNode {
        let flame = SKEmitterNode()
        flame.particleTexture = softDot
        flame.particleBirthRate = 36
        flame.particleLifetime = 0.45
        flame.particleLifetimeRange = 0.15
        flame.particleSpeed = 24
        flame.particleSpeedRange = 8
        flame.emissionAngle = .pi / 2
        flame.emissionAngleRange = 0.4
        flame.particlePositionRange = CGVector(dx: 6, dy: 2)
        flame.particleScale = 0.55
        flame.particleScaleSpeed = -1
        flame.particleAlphaSpeed = -1.6
        flame.particleColorBlendFactor = 1
        flame.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor.systemYellow, UIColor.systemOrange, UIColor.systemRed],
            times: [0, 0.4, 1]
        )
        flame.particleBlendMode = .add
        return flame
    }

    /// A small radial gradient dot used for flame and dust particles.
    private static let softDot: SKTexture = {
        let size = CGSize(width: 16, height: 16)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
            else { return }
            let center = CGPoint(x: 8, y: 8)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                                 endRadius: 8, options: [])
        }
        return SKTexture(image: image)
    }()
}
