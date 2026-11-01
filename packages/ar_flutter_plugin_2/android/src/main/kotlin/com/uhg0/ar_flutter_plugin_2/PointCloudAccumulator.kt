package com.uhg0.ar_flutter_plugin_2

import java.nio.FloatBuffer

/**
 * Sliding-window world-space buffer of ARCore point-cloud samples.
 *
 * A single Frame's cloud is too sparse for a confident RANSAC fit on most
 * phones, so refinePlane fits against this accumulated ~1.8 s of surface
 * (one sample per ~3.5 cm voxel) instead of one noisy frame. Touched only
 * from the UI thread — same contract as latestFrame / livePlanes in ArView.
 */
class PointCloudAccumulator(
    private val voxelSizeM: Float = 0.035f,
    private val maxAgeMs: Long = 1800,
    private val maxVoxels: Int = 12000,
) {

    private class Voxel(
        @JvmField var x: Float,
        @JvmField var y: Float,
        @JvmField var z: Float,
        @JvmField var lastMs: Long,
    )

    private val voxels = HashMap<Long, Voxel>()
    // Sentinel below any real frame timestamp — NOT Long.MIN_VALUE, whose
    // subtraction from a positive nowMs overflows and would skip pruning
    // forever.
    private var lastPruneMs = -1000L

    /** Folds one point-cloud frame in; [nowMs] must be monotonic. */
    fun ingest(points: FloatBuffer, nowMs: Long) {
        val limit = points.limit()
        var i = 0
        // Points are x,y,z,confidence — stride 4.
        while (i + 3 < limit) {
            val x = points.get(i)
            val y = points.get(i + 1)
            val z = points.get(i + 2)
            if (x.isFinite() && y.isFinite() && z.isFinite()) {
                val k = key(x, y, z)
                val existing = voxels[k]
                if (existing == null) {
                    voxels[k] = Voxel(x, y, z, nowMs)
                } else {
                    existing.x = x
                    existing.y = y
                    existing.z = z
                    existing.lastMs = nowMs
                }
            }
            i += 4
        }
        if (nowMs - lastPruneMs >= 400) {
            lastPruneMs = nowMs
            prune(nowMs)
        }
    }

    /** World-space xyz samples within [radiusM] of the seed. */
    fun gather(seedX: Float, seedY: Float, seedZ: Float, radiusM: Float): ArrayList<FloatArray> {
        val out = ArrayList<FloatArray>(256)
        val r2 = radiusM * radiusM
        for (v in voxels.values) {
            val dx = v.x - seedX
            val dy = v.y - seedY
            val dz = v.z - seedZ
            if (dx * dx + dy * dy + dz * dz <= r2) {
                out.add(floatArrayOf(v.x, v.y, v.z))
            }
        }
        return out
    }

    fun clear() {
        voxels.clear()
        lastPruneMs = -1000L
    }

    private fun prune(nowMs: Long) {
        val it = voxels.entries.iterator()
        while (it.hasNext()) {
            if (nowMs - it.next().value.lastMs > maxAgeMs) it.remove()
        }
        if (voxels.size > maxVoxels) {
            // A long sweep can outgrow the cap even after aging out — drop
            // the oldest samples first.
            val oldestFirst = voxels.entries.sortedBy { it.value.lastMs }
            for (i in 0 until (voxels.size - maxVoxels)) {
                voxels.remove(oldestFirst[i].key)
            }
        }
    }

    private fun key(x: Float, y: Float, z: Float): Long {
        val ix = Math.floor((x / voxelSizeM).toDouble()).toLong()
        val iy = Math.floor((y / voxelSizeM).toDouble()).toLong()
        val iz = Math.floor((z / voxelSizeM).toDouble()).toLong()
        return ((ix and 0x1FFFFF) shl 42) or
            ((iy and 0x1FFFFF) shl 21) or
            (iz and 0x1FFFFF)
    }
}
