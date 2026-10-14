package com.uhg0.ar_flutter_plugin_2.Serialization

import io.github.sceneview.math.Position as ScenePosition
import kotlin.math.sqrt

/** Position + rotation quaternion extracted from a column-major Matrix4. */
data class PoseParts(
    val position: ScenePosition,
    /** Quaternion in ARCore Pose order: [x, y, z, w]. */
    val quaternion: FloatArray,
)

/**
 * Splits a Flutter-sent column-major 4x4 [transform] into a translation and
 * a UNIT quaternion suitable for `com.google.ar.core.Pose`. Covers every
 * trace branch — the previous extraction dropped the quaternion's w
 * component (hard-coded to 1 downstream), which mangled any non-identity
 * rotation into a degenerate pose.
 */
fun deserializePoseParts(transform: ArrayList<Double>): PoseParts {
    val position = ScenePosition(
        x = transform[12].toFloat(),
        y = transform[13].toFloat(),
        z = transform[14].toFloat()
    )

    // Rotation matrix (row-major access from the column-major storage).
    val m00 = transform[0].toFloat()
    val m01 = transform[4].toFloat()
    val m02 = transform[8].toFloat()
    val m10 = transform[1].toFloat()
    val m11 = transform[5].toFloat()
    val m12 = transform[9].toFloat()
    val m20 = transform[2].toFloat()
    val m21 = transform[6].toFloat()
    val m22 = transform[10].toFloat()

    val trace = m00 + m11 + m22
    val quaternion = if (trace > 0f) {
        val s = 0.5f / sqrt(trace + 1.0f)
        floatArrayOf(
            (m21 - m12) * s,
            (m02 - m20) * s,
            (m10 - m01) * s,
            0.25f / s,
        )
    } else if (m00 > m11 && m00 > m22) {
        val s = 2.0f * sqrt(1.0f + m00 - m11 - m22)
        floatArrayOf(
            0.25f * s,
            (m01 + m10) / s,
            (m02 + m20) / s,
            (m21 - m12) / s,
        )
    } else if (m11 > m22) {
        val s = 2.0f * sqrt(1.0f + m11 - m00 - m22)
        floatArrayOf(
            (m01 + m10) / s,
            0.25f * s,
            (m12 + m21) / s,
            (m02 - m20) / s,
        )
    } else {
        val s = 2.0f * sqrt(1.0f + m22 - m00 - m11)
        floatArrayOf(
            (m02 + m20) / s,
            (m12 + m21) / s,
            0.25f * s,
            (m10 - m01) / s,
        )
    }

    return PoseParts(position = position, quaternion = quaternion)
}
