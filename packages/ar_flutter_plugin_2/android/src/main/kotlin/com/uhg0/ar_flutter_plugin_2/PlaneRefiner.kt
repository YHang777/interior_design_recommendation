package com.uhg0.ar_flutter_plugin_2

import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Fits a plane to ARCore's raw point cloud with RANSAC, so placement can use a
 * freshly-fitted surface instead of ARCore's (often jittery / floating) plane
 * polygon. Works on every ARCore device — only needs Frame.acquirePointCloud().
 */
object PlaneRefiner {

    data class Fit(
        val centerX: Float,
        val centerY: Float,
        val centerZ: Float,
        val normalX: Float,
        val normalY: Float,
        val normalZ: Float,
        val inlierCount: Int,
        val pointCount: Int,
        val rmsError: Float,
        val confidence: Float,
    )

    // Points closer than this to the fitted plane count as inliers. ~1.5 cm is
    // tight enough to reject furniture legs / clutter but loose enough for the
    // sub-centimetre noise ARCore's sparse point cloud carries.
    private const val INLIER_THRESHOLD_M = 0.015f
    private const val MIN_POINTS = 24
    private const val RANSAC_ITERATIONS = 90
    // How far a sampled normal may tilt from the expected axis and still be
    // accepted. Floors should be near-upright; walls near-vertical.
    private const val HORIZONTAL_MIN_NORMAL_Y = 0.85f
    private const val WALL_MAX_NORMAL_Y = 0.35f
    // RMS above this caps confidence — a loose fit is not trustworthy.
    private const val MAX_RMS_FOR_CONFIDENCE_M = 0.04f

    /**
     * @param points interleaved x,y,z world-coord FloatBuffer from PointCloud.getPoints()
     *               (4 floats per point — x,y,z,confidence; confidence is ignored here
     *               because ARCore reports it as 1.0 on most devices).
     * @param seedX/Y/Z the hit-test point to refine around.
     * @param radiusM gather points within this 3D radius of the seed.
     * @param wantHorizontal true → fit a floor (normal near +Y); false → a wall.
     */
    fun refine(
        points: FloatBuffer,
        seedX: Float,
        seedY: Float,
        seedZ: Float,
        radiusM: Float,
        wantHorizontal: Boolean,
    ): Fit? {
        val gathered = ArrayList<FloatArray>(512)
        val limit = points.limit()
        var i = 0
        // PointCloud points are x,y,z,confidence — stride 4.
        while (i + 3 < limit) {
            val x = points.get(i)
            val y = points.get(i + 1)
            val z = points.get(i + 2)
            val dx = x - seedX
            val dy = y - seedY
            val dz = z - seedZ
            if (dx * dx + dy * dy + dz * dz <= radiusM * radiusM) {
                gathered.add(floatArrayOf(x, y, z))
            }
            i += 4
        }

        if (gathered.size < MIN_POINTS) return null
        val pts = gathered.toTypedArray()
        val rng = Random(seedX.toBits() xor seedZ.toBits() xor seedY.toBits())

        var bestNormal: FloatArray? = null
        var bestPoint: FloatArray? = null
        var bestInliers = IntArray(0)

        repeat(RANSAC_ITERATIONS) {
            val p1 = pts[rng.nextInt(pts.size)]
            val p2 = pts[rng.nextInt(pts.size)]
            val p3 = pts[rng.nextInt(pts.size)]
            if (p1 === p2 || p1 === p3 || p2 === p3) return@repeat

            val normal = cross(
                p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2],
                p3[0] - p1[0], p3[1] - p1[1], p3[2] - p1[2],
            ) ?: return@repeat
            if (!normalOk(normal, wantHorizontal)) return@repeat

            val inliers = IntArray(pts.size)
            var count = 0
            for (idx in pts.indices) {
                val d = abs(
                    normal[0] * (pts[idx][0] - p1[0]) +
                        normal[1] * (pts[idx][1] - p1[1]) +
                        normal[2] * (pts[idx][2] - p1[2])
                )
                if (d < INLIER_THRESHOLD_M) {
                    inliers[count++] = idx
                }
            }
            if (count > bestInliers.size) {
                bestNormal = normal
                bestPoint = p1
                bestInliers = inliers.copyOf(count)
            }
        }

        val seedNormal = bestNormal ?: return null
        if (bestInliers.size < MIN_POINTS) return null

        // Least-squares refit: centroid + smallest-eigenvector of the inlier
        // scatter matrix (Jacobi rotations — robust for a 3x3 symmetric matrix).
        val inlierPts = Array(bestInliers.size) { pts[bestInliers[it]] }
        val centroid = centroidOf(inlierPts)
        val normal = smallestEigenvector(scatterMatrix(inlierPts, centroid))
            ?: seedNormal
        val unit = normalize(normal) ?: seedNormal

        val locked = if (wantHorizontal) {
            // Floor must face up. Flip a downward normal rather than reject.
            if (unit[1] < 0) floatArrayOf(-unit[0], -unit[1], -unit[2]) else unit
        } else {
            // Wall normal should point toward the camera side; align its Y ~0.
            unit
        }
        if (!normalOk(locked, wantHorizontal)) return null

        // Recount inliers + RMS against the refined plane.
        var sumSq = 0f
        var count = 0
        for (p in inlierPts) {
            val d = abs(
                locked[0] * (p[0] - centroid[0]) +
                    locked[1] * (p[1] - centroid[1]) +
                    locked[2] * (p[2] - centroid[2])
            )
            if (d < INLIER_THRESHOLD_M) {
                sumSq += d * d
                count++
            }
        }
        if (count < MIN_POINTS) return null
        val rms = sqrt(sumSq / count)

        // Confidence blends how much of the neighbourhood is planar (inlier
        // ratio) with how tight the fit is (RMS). Low on clutter, high on a
        // clean floor.
        val ratio = count.toFloat() / pts.size
        val tightness = (1f - rms / MAX_RMS_FOR_CONFIDENCE_M).coerceIn(0f, 1f)
        val confidence = (ratio * tightness).coerceIn(0f, 1f)

        return Fit(
            centerX = centroid[0],
            centerY = centroid[1],
            centerZ = centroid[2],
            normalX = locked[0],
            normalY = locked[1],
            normalZ = locked[2],
            inlierCount = count,
            pointCount = pts.size,
            rmsError = rms,
            confidence = confidence,
        )
    }

    private fun normalOk(n: FloatArray, wantHorizontal: Boolean): Boolean {
        return if (wantHorizontal) n[1] >= HORIZONTAL_MIN_NORMAL_Y
        else abs(n[1]) <= WALL_MAX_NORMAL_Y
    }

    private fun cross(
        ax: Float, ay: Float, az: Float,
        bx: Float, by: Float, bz: Float,
    ): FloatArray? {
        val x = ay * bz - az * by
        val y = az * bx - ax * bz
        val z = ax * by - ay * bx
        val len = sqrt(x * x + y * y + z * z)
        if (len < 1e-6f) return null
        return floatArrayOf(x / len, y / len, z / len)
    }

    private fun normalize(n: FloatArray): FloatArray? {
        val len = sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        if (len < 1e-6f) return null
        return floatArrayOf(n[0] / len, n[1] / len, n[2] / len)
    }

    private fun centroidOf(pts: Array<FloatArray>): FloatArray {
        var sx = 0f; var sy = 0f; var sz = 0f
        for (p in pts) { sx += p[0]; sy += p[1]; sz += p[2] }
        val n = pts.size.toFloat()
        return floatArrayOf(sx / n, sy / n, sz / n)
    }

    private fun scatterMatrix(pts: Array<FloatArray>, c: FloatArray): FloatArray {
        // Row-major 3x3 symmetric scatter (covariance * n).
        val m = FloatArray(9)
        for (p in pts) {
            val dx = p[0] - c[0]
            val dy = p[1] - c[1]
            val dz = p[2] - c[2]
            m[0] += dx * dx; m[1] += dx * dy; m[2] += dx * dz
            m[4] += dy * dy; m[5] += dy * dz
            m[8] += dz * dz
        }
        m[3] = m[1]; m[6] = m[2]; m[7] = m[5]
        return m
    }

    // Jacobi eigen-decomposition for a symmetric 3x3; returns the eigenvector
    // for the smallest eigenvalue (the plane normal).
    private fun smallestEigenvector(m: FloatArray): FloatArray? {
        val a = m.copyOf()
        var v = floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f)
        repeat(24) {
            // Find the largest off-diagonal element to rotate away.
            var p = 0; var q = 1
            var max = abs(a[1])
            if (abs(a[2]) > max) { max = abs(a[2]); p = 0; q = 2 }
            if (abs(a[5]) > max) { max = abs(a[5]); p = 1; q = 2 }
            if (max < 1e-9f) return@repeat

            val app = a[p * 3 + p]
            val aqq = a[q * 3 + q]
            val apq = a[p * 3 + q]
            val theta = 0.5f * atan2f(2f * apq, aqq - app)
            val c = cosf(theta)
            val s = sinf(theta)

            // Rotate A: A = J^T A J.
            for (r in 0 until 3) {
                if (r == p || r == q) continue
                val arp = a[r * 3 + p]
                val arq = a[r * 3 + q]
                a[r * 3 + p] = c * arp - s * arq
                a[p * 3 + r] = a[r * 3 + p]
                a[r * 3 + q] = s * arp + c * arq
                a[q * 3 + r] = a[r * 3 + q]
            }
            a[p * 3 + p] = c * c * app - 2f * s * c * apq + s * s * aqq
            a[q * 3 + q] = s * s * app + 2f * s * c * apq + c * c * aqq
            a[p * 3 + q] = 0f
            a[q * 3 + p] = 0f

            // Accumulate the rotation into V.
            for (r in 0 until 3) {
                val vrp = v[r * 3 + p]
                val vrq = v[r * 3 + q]
                v[r * 3 + p] = c * vrp - s * vrq
                v[r * 3 + q] = s * vrp + c * vrq
            }
        }

        var smallest = 0
        var minValue = a[0]
        for (d in 1 until 3) {
            if (a[d * 3 + d] < minValue) { minValue = a[d * 3 + d]; smallest = d }
        }
        return floatArrayOf(v[smallest], v[3 + smallest], v[6 + smallest])
    }

    // Float-buffer-free trig (java.lang.Math) to avoid allocation in the loop.
    private fun atan2f(y: Float, x: Float) = Math.atan2(y.toDouble(), x.toDouble()).toFloat()
    private fun cosf(a: Float) = Math.cos(a.toDouble()).toFloat()
    private fun sinf(a: Float) = Math.sin(a.toDouble()).toFloat()
}
