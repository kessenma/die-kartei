//
//  SceneRig.swift
//  german-ai-flashcards
//
//  The camera and lights the app's 3D canvases share.
//
//  The preposition canvas and `PyramidView` each build this rig inline, with the same numbers
//  written out twice, so that a live scene matches the Blender `dim` renders the assets are
//  judged against. This file exists so the figure canvas doesn't become a third copy. It is
//  deliberately additive: the two existing call sites are untouched, and folding them in is a
//  separate change on files that other work is currently touching.
//
//  The one thing worth understanding is `viewingDirection`. A scene and a portrait want very
//  different framings but the *same* light and the same angle of view — change the distance,
//  never the direction, and a figure photographs like the props it stands among.
//

import RealityKit
import SwiftUI

enum SceneRig {
    /// The preposition canvas frames from `[4.0, 3.6, 10.6]` toward `[0, 0.4, 0]`. Both are
    /// spelled out rather than reduced to a unit vector so the relationship to that scene, and
    /// to `setup_camera`'s 21°/17° rake in `tools/blender/prep_render.py`, stays legible.
    private static let sceneEye = SIMD3<Float>(4.0, 3.6, 10.6)
    private static let sceneTarget = SIMD3<Float>(0, 0.4, 0)

    /// The shared angle of view. Framing is a matter of `distance`; this never changes.
    static var viewingDirection: SIMD3<Float> { normalize(sceneEye - sceneTarget) }

    /// Re-frame an existing camera. Separate from `camera(lookingAt:distance:)` so a view can
    /// change its framing without rebuilding the RealityKit surface — recreating the camera
    /// would mean a new render context, which is the thing the 3D canvases exist to avoid.
    static func aim(_ camera: PerspectiveCamera, at target: SIMD3<Float>, distance: Float) {
        camera.look(at: target, from: target + viewingDirection * distance, relativeTo: nil)
    }

    /// A camera on the house angle, pulled to whatever distance frames the subject.
    static func camera(lookingAt target: SIMD3<Float>,
                       distance: Float,
                       fieldOfView: Float = 30) -> PerspectiveCamera {
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = fieldOfView
        aim(camera, at: target, distance: distance)
        return camera
    }

    /// Key, rim and fill, mirroring `setup_lights` in the Blender rig — the ~7:1 key-to-fill
    /// ratio is where the contrast comes from, not the absolute level.
    static func lights() -> [Entity] {
        let key = DirectionalLight()
        key.light.intensity = 5200
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 24, depthBias: 1.2)
        key.look(at: .zero, from: [-4.6, 6.4, 4.2], relativeTo: nil)

        let rim = DirectionalLight()
        rim.light.intensity = 3000
        rim.look(at: .zero, from: [4.8, 2.6, -4.4], relativeTo: nil)

        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: .zero, from: [4.2, 0.6, 6.4], relativeTo: nil)

        return [key, rim, fill]
    }
}

extension Entity {
    /// Drop every camera and light in this subtree.
    ///
    /// Shipped assets are geometry-only by contract — the Blender exporters delete cameras and
    /// lights before writing — but a stale bundle can still carry an exporter's judge rig, and
    /// a scene camera fights the canvas's own, up to crashing the renderer on device (three of
    /// them inside an early story USDZ trapped RealityKit on iPhone, 2026-07-30).
    ///
    /// Named apart from the preposition canvas's file-private `stripCamerasAndLights()` on
    /// purpose: two members with one signature, one private and one internal, is exactly the
    /// kind of ambiguity that breaks a file nobody meant to touch.
    func removeCamerasAndLights() {
        var doomed: [Entity] = []
        var queue: [Entity] = [self]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next.components.has(PerspectiveCameraComponent.self)
                || next.components.has(DirectionalLightComponent.self)
                || next.components.has(PointLightComponent.self)
                || next.components.has(SpotLightComponent.self) {
                doomed.append(next)
            } else {
                queue.append(contentsOf: next.children)
            }
        }
        for entity in doomed { entity.removeFromParent() }
    }

    /// Re-tint every material on every mesh in this subtree.
    ///
    /// The preposition canvas tints one material on one mesh, which is right for an asset whose
    /// subject is a single joined prop. A figure is six separate meshes, so that helper would
    /// recolor one leg and leave the rest charcoal — hence the whole subtree, and every material
    /// on it rather than only the first.
    func tintEveryModel(_ color: Color) {
        let uiColor = UIColor(color)
        var queue: [Entity] = [self]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let model = next as? ModelEntity, var component = model.model {
                component.materials = component.materials.map { material in
                    guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                    pbr.baseColor = .init(tint: uiColor)
                    return pbr
                }
                model.model = component
            }
            queue.append(contentsOf: next.children)
        }
    }
}
