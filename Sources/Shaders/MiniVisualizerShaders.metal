#include <metal_stdlib>
using namespace metal;

// Byte-for-byte counterpart of AmpXMiniVisualizerRenderer.Uniforms.
struct MiniUniforms {
    float4 dimensions;
    uint4 mode;
    float4 meters;
    float4 background;
    float4 low;
    float4 middle;
    float4 high;
    float4 trace;
    float4 peak;
    float4 dimCell;
    float4 historyLow;
    float4 historyHigh;
    float4 ramp;
};

struct MiniVertex {
    float4 position [[position]];
};

vertex MiniVertex miniVisualizerVertex(uint id [[vertex_id]]) {
    const float2 positions[3] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    return {float4(positions[id], 0, 1)};
}

static float miniScale(constant MiniUniforms &u) {
    return max(1.0f, min(u.dimensions.x / 137.5f, u.dimensions.y / 41.0f));
}

static float3 miniRamp(float level, constant MiniUniforms &u) {
    // Stops belong to the palette; Classic spans green → yellow → red with yellow at 50%.
    float3 lower = mix(u.low.rgb, u.middle.rgb, smoothstep(u.ramp.x, u.ramp.y, level));
    return mix(lower, u.high.rgb, smoothstep(u.ramp.y, u.ramp.z, level));
}

static float3 miniPeakColor(float peak, constant MiniUniforms &u) {
    return u.ramp.w > 0.5f ? miniRamp(peak, u) : u.peak.rgb;
}

static float miniBand(device const float *data, int index) {
    return data[clamp(index, 0, 31)];
}

static float miniCurve(device const float *data, float x) {
    float location = clamp(x, 0.0f, 1.0f) * 31;
    int index = int(floor(location));
    float t = fract(location);
    float a = miniBand(data, index - 1), b = miniBand(data, index);
    float c = miniBand(data, index + 1), d = miniBand(data, index + 2);
    // Bounded Catmull-Rom interpolation smooths appearance, without claiming extra FFT resolution.
    return clamp(0.5f * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                        + (-a + 3 * b - 3 * c + d) * t * t * t), 0.0f, 1.0f);
}

static float miniWave(device const float *data, uint count, float x) {
    if (count == 0) return 0;
    float location = clamp(x, 0.0f, 1.0f) * float(count - 1);
    uint index = uint(location);
    return mix(data[96 + index], data[96 + min(index + 1, count - 1)], fract(location));
}

static float miniSegmentDistance(float2 point, float2 a, float2 b) {
    float2 edge = b - a;
    float projection = clamp(dot(point - a, edge) / max(dot(edge, edge), 0.0001f), 0.0f, 1.0f);
    return length(point - a - edge * projection);
}

static float3 miniSpectrum(float2 p, constant MiniUniforms &u, device const float *data) {
    float2 size = u.dimensions.xy;
    float scale = miniScale(u);
    uint style = u.mode.x;
    uint columns = 32;
    uint column = min(uint(p.x * float(columns) / size.x), columns - 1);
    uint band = column;
    float level = data[band];
    float peak = data[32 + band];
    float left = floor(float(column) * size.x / float(columns));
    float right = style == 2 ? left + floor(size.x / float(columns)) : floor(float(column + 1) * size.x / float(columns));
    float gap = max(1.0f, round(scale));
    if (p.x < left || p.x >= right - gap) return u.background.rgb;

    if (style == 3) {
        // Pixel centers share the same distance on each side, including odd drawable
        // heights. Both halves therefore have identical extents and segment placement.
        float center = size.y * 0.5f;
        bool reflection = p.y >= center;
        float distance = abs(p.y - center);
        float extent = center;
        float height = floor(level * max(0.0f, extent - scale));
        if (level <= 0 || distance < scale || distance >= height) return u.background.rgb;
        float pitch = max(2.0f, round(3 * scale));
        if (fmod(distance, pitch) >= pitch - gap) return u.background.rgb;
        float3 color = miniRamp(distance / max(extent, 1.0f), u);
        // Keep the reflection legible in a 41-point-high well; a 35%-to-black fade
        // made most of the lower half disappear on the dark Player background.
        return reflection ? mix(u.background.rgb, color, 0.85f - 0.15f * distance / extent) : color;
    }

    float height = max(1.0f, size.y - 2 * scale);
    float fromBottom = size.y - p.y - scale;
    if (fromBottom < 0 || fromBottom >= height) return u.background.rgb;
    float normalized = fromBottom / height;
    if (style == 0) {
        if (peak > 0 && abs(fromBottom - floor(peak * height)) < max(1.0f, scale))
            return miniPeakColor(peak, u);
        if (level > 0 && fromBottom < floor(level * height))
            return miniRamp(normalized, u);
        return u.background.rgb;
    }

    // Fine square cells snapped in physical pixels.
    float pitch = max(2.0f, floor(size.x / float(columns)));
    float cellBottom = floor(fromBottom / pitch) * pitch;
    if (fromBottom - cellBottom >= pitch - gap) return u.background.rgb;
    float threshold = (cellBottom + 0.5f * (pitch - gap)) / height;
    if (level > 0 && threshold <= level) return miniRamp(normalized, u);
    return u.dimCell.rgb;
}

static float3 miniSmooth(float2 p, constant MiniUniforms &u, device const float *data) {
    float2 size = u.dimensions.xy;
    float scale = miniScale(u);
    float height = max(1.0f, size.y - 2 * scale);
    float level = miniCurve(data, p.x / size.x);
    if (level <= 0.0001f) return u.background.rgb;
    float curveY = size.y - scale - level * height;
    float derivative = (miniCurve(data, (p.x + 0.5f) / size.x) - miniCurve(data, (p.x - 0.5f) / size.x)) * height;
    float distance = abs(p.y - curveY) / sqrt(1 + derivative * derivative);
    float outline = 1 - smoothstep(0.42f * scale, 0.42f * scale + 1, distance);
    float glow = exp(-distance * distance / (8 * scale * scale)) * 0.18f;
    float vertical = clamp((size.y - p.y - scale) / height, 0.0f, 1.0f);
    float fill = smoothstep(-0.5f, 0.5f, p.y - curveY) * (0.12f + 0.68f * vertical);
    float3 color = mix(u.background.rgb, miniRamp(vertical, u), fill);
    color = mix(color, u.trace.rgb, glow);
    return mix(color, u.trace.rgb, outline);
}

static float3 miniLine(float2 p, constant MiniUniforms &u, device const float *data) {
    uint count = u.mode.y;
    float2 size = u.dimensions.xy;
    float scale = miniScale(u);
    float amplitude = max(1.0f, size.y * 0.44f);
    if (count < 2) {
        float baseline = 1 - smoothstep(0.25f * scale, 0.25f * scale + 1, abs(p.y - size.y * 0.5f));
        return mix(u.background.rgb, u.dimCell.rgb, baseline);
    }
    float spacing = size.x / float(count - 1);
    int middle = int(p.x / spacing);
    float distance = size.y;
    float activity = 0;
    // Only neighboring polyline segments: constant bounded cost, never a per-pixel particle loop.
    for (int offset = -4; offset <= 4; ++offset) {
        int index = clamp(middle + offset, 0, int(count) - 2);
        float a = data[96 + index], b = data[96 + index + 1];
        float2 start = float2(float(index) * spacing, size.y * 0.5f - a * amplitude);
        float2 end = float2(float(index + 1) * spacing, size.y * 0.5f - b * amplitude);
        distance = min(distance, miniSegmentDistance(p, start, end));
        activity = max(activity, max(abs(a), abs(b)));
    }
    float line = 1 - smoothstep(0.4f * scale, 0.4f * scale + 1, distance);
    float glow = exp(-distance * distance / (7 * scale * scale)) * 0.16f;
    float3 trace = activity > 0.0001f ? u.trace.rgb : u.dimCell.rgb;
    return mix(u.background.rgb, trace, max(line, glow));
}

static float3 miniMeters(float2 p, constant MiniUniforms &u) {
    float2 size = u.dimensions.xy;
    float scale = miniScale(u);
    uint row = p.y < size.y * 0.5f ? 0 : 1;
    float center = size.y * (row == 0 ? 0.27f : 0.73f);
    float halfHeight = max(1.0f, floor(size.y * 0.105f));
    if (abs(p.y - center) > halfHeight) return u.background.rgb;
    float level = row == 0 ? u.meters.x : u.meters.y;
    float peak = row == 0 ? u.meters.z : u.meters.w;
    float x = p.x / size.x;
    if (peak > 0 && abs(p.x - floor(peak * (size.x - 1))) < max(1.0f, scale))
        return miniPeakColor(peak, u);
    float pitch = max(3.0f, round(3 * scale));
    if (fmod(p.x, pitch) >= pitch - max(1.0f, round(scale))) return u.background.rgb;
    if (abs(p.y - center) < 0.5f * scale) return u.background.rgb;
    return level > 0 && x < level ? miniRamp(x, u) : u.dimCell.rgb;
}

fragment float4 miniVisualizerFragment(
    MiniVertex in [[stage_in]], constant MiniUniforms &u [[buffer(0)]],
    device const float *data [[buffer(1)]], texture2d<float> history [[texture(0)]]
) {
    float2 p = in.position.xy;
    float3 color = u.background.rgb;
    switch (u.mode.x) {
        case 0: case 2: case 3: color = miniSpectrum(p, u, data); break;
        case 1: color = miniSmooth(p, u, data); break;
        case 4: color = miniLine(p, u, data); break;
        case 5: {
            // The supplied frame is already chronological; drawing never advances history.
            uint2 location = min(uint2(p / u.dimensions.xy * float2(32, 128)), uint2(31, 127));
            float energy = history.read(location).r;
            // Expand contrast between the dense mid-level bed and stronger frequency
            // events. A bright square-root wash hid that detail in the small Player well.
            float3 heat = mix(u.historyLow.rgb, u.historyHigh.rgb, energy);
            color = mix(u.background.rgb, heat, smoothstep(0.0f, 1.0f, energy));
            break;
        }
        case 8: color = miniMeters(p, u); break;
        default: break; // Particle background is followed by a bounded instanced quad draw.
    }
    return float4(color, 1);
}

struct MiniParticleVertex {
    float4 position [[position]];
    float2 local;
    float opacity;
    float heat;
};

static float miniRandom(uint seed) {
    seed ^= seed >> 16;
    seed *= 0x7feb352du;
    seed ^= seed >> 15;
    seed *= 0x846ca68bu;
    seed ^= seed >> 16;
    return float(seed & 0x00ffffffu) / 16777216.0f;
}

vertex MiniParticleVertex miniParticleVertex(
    uint vertexID [[vertex_id]], uint instance [[instance_id]],
    constant MiniUniforms &u [[buffer(0)]], device const float *data [[buffer(1)]]
) {
    const float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1),
                              float2(-1, 1), float2(1, -1), float2(1, 1)};
    // 128 deterministic seeds × four fading ages = exactly 512 particle quads, no heap/state growth.
    uint seed = instance / 4;
    float age = float(instance % 4);
    float random = miniRandom(seed + 1);
    float scale = miniScale(u);
    float time = fmod(u.dimensions.z, 4096.0f) - age * 0.045f;
    float x = fract((float(seed) + 0.5f) / 128 + time * (0.012f + random * 0.009f));
    float wave = miniWave(data, u.mode.y, x);
    float spread = sin(time * (2 + random * 3) + random * 39) * (1.5f + 3.5f * random) * scale;
    float2 center = float2(x * u.dimensions.x, u.dimensions.y * 0.5f - wave * u.dimensions.y * 0.44f + spread);
    float radius = (0.65f + miniRandom(seed + 513) * 0.55f) * scale;
    float2 local = corners[vertexID];
    float2 position = center + local * radius;
    float2 clip = position / u.dimensions.xy * 2 - 1;
    clip.y = -clip.y;
    float activity = min(1.0f, abs(wave) * 8);
    // Position still follows PCM directly. Perceptual opacity keeps quiet music readable
    // without multiplying its small amplitude twice; exact silence remains transparent.
    float opacity = sqrt(u.dimensions.w) * sqrt(activity) * exp(-age * 0.6f);
    return {float4(clip, 0, 1), local, opacity, random};
}

fragment float4 miniParticleFragment(MiniParticleVertex in [[stage_in]], constant MiniUniforms &u [[buffer(0)]]) {
    float distance = length(in.local);
    float alpha = (1 - smoothstep(0.25f, 1.0f, distance)) * in.opacity;
    float3 color = mix(u.low.rgb, u.trace.rgb, 0.4f + 0.6f * in.heat);
    return float4(color * alpha, alpha);
}
