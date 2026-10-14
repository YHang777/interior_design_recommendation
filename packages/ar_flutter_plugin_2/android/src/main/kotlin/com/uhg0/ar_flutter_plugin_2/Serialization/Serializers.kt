package com.uhg0.ar_flutter_plugin_2.Serialization

import com.google.ar.core.Pose

/**
 * Serializes one plane hit from the Android tap handler.
 *
 * Expected input keys (see ArView's onSingleTapConfirmed):
 *  * type: Int (1 = plane)
 *  * distance: Double (meters from the camera)
 *  * position: Map with x/y/z Doubles (hit translation)
 *  * rotation: OPTIONAL Map with x/y/z/w Doubles — the REAL hit-pose
 *    quaternion. Without it the serializer falls back to an identity
 *    rotation (legacy payloads only — that fallback made every surface
 *    look horizontal and broke wall placement).
 *  * planeType: OPTIONAL Int — 1 = horizontal (upward-facing),
 *    2 = vertical, 0 = downward-facing / unknown.
 *  * planeExtent: OPTIONAL Map with x/z Doubles — the plane's polygon
 *    extent in meters (gates placement on still-tiny newborn planes).
 */
fun serializeHitResult(hit: Map<String, Any>): HashMap<String, Any> {
    val serializedHit = HashMap<String, Any>()

    serializedHit["type"] = hit["type"] as Int
    serializedHit["distance"] = hit["distance"] as Double

    val position = hit["position"] as Map<String, Double>
    val rotation = hit["rotation"] as? Map<String, Double>
    val quaternion = if (rotation != null) {
        floatArrayOf(
            rotation["x"]?.toFloat() ?: 0f,
            rotation["y"]?.toFloat() ?: 0f,
            rotation["z"]?.toFloat() ?: 0f,
            rotation["w"]?.toFloat() ?: 1f,
        )
    } else {
        floatArrayOf(0f, 0f, 0f, 1f)
    }
    val pose = Pose(
        floatArrayOf(
            position["x"]?.toFloat() ?: 0f,
            position["y"]?.toFloat() ?: 0f,
            position["z"]?.toFloat() ?: 0f
        ),
        quaternion
    )

    serializedHit["worldTransform"] = serializePose(pose)

    (hit["planeType"] as? Int)?.let { serializedHit["planeType"] = it }
    (hit["planeExtent"] as? Map<*, *>)
        ?.let { serializedHit["planeExtent"] = HashMap(it) }
    return serializedHit
}

fun serializePose(pose: Pose): DoubleArray {
    val serializedPose = FloatArray(16)
    pose.toMatrix(serializedPose, 0)
    return DoubleArray(16) { serializedPose[it].toDouble() }
}
