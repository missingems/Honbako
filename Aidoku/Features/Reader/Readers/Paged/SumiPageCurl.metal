#include <metal_stdlib>
using namespace metal;
struct HonbakoPaperUniforms {
    float2 viewport;
    float2 grip;
    float progress;
    float verticalBend;
    float sign;
    float padding;
};
struct HonbakoPaperVertex { float4 position [[position]]; float2 uv; };

// Identical isometric surface to SumiPageCurlDeformation.vertex.
float3 honbakoPaperPoint(float2 point, constant HonbakoPaperUniforms &u) {
    const float p = clamp(u.progress, 0.0f, 1.0f), height = max(1.0f, u.viewport.y);
    if (p <= 0.0f) { return float3(point.x, point.y, 0.0f); }
    if (p >= 1.0f) { return float3(-point.x, point.y, 0.0f); }
    if (point.x == 0.0f) { return float3(0.0f, point.y, 0.0f); }
    const float turn = M_PI_F * p;
    const bool top = u.grip.y <= height * 0.5f;
    const float localY = top ? point.y : height - point.y;
    const float centre = 1.0f - abs(2.0f * u.grip.y / height - 1.0f);
    const float apex = height * (0.2f + 0.85f * centre * centre);
    const float inward = u.verticalBend / height * (top ? 1.0f : -1.0f);
    const float strength = 0.62f + 0.28f * tanh(inward * 3.0f);
    const float angle = M_PI_F * 0.5f - strength * sin(turn);
    const float sine = sin(angle), cosine = cos(angle);
    const float distanceY = localY + apex, radius = length(float2(point.x, distanceY));
    const float azimuth = atan2(point.x, distanceY) / sine, coneRadius = radius * sine;
    const float x = coneRadius * sin(azimuth);
    const float y = radius - coneRadius * sine * (1.0f - cos(azimuth)) - apex;
    const float z = coneRadius * cosine * (1.0f - cos(azimuth));
    return float3(x * cos(turn) - z * sin(turn), top ? y : height - y,
                  x * sin(turn) + z * cos(turn));
}
vertex HonbakoPaperVertex honbakoPaperVertex(uint id [[vertex_id]],
    const device float2 *vertices [[buffer(0)]], constant HonbakoPaperUniforms &u [[buffer(1)]]) {
    const float2 uv = vertices[id];
    const float width = max(1.0f, u.viewport.x * 0.5f), height = max(1.0f, u.viewport.y);
    const float3 point = honbakoPaperPoint(float2(uv.x * width, uv.y * height), u);
    HonbakoPaperVertex out;
    out.position = float4(u.sign * point.x / width, 1.0f - 2.0f * point.y / height,
        clamp(0.8f - point.z / (max(u.viewport.x, height) * 2.0f), 0.01f, 0.99f), 1.0f);
    out.uv = uv;
    return out;
}
fragment float4 honbakoPaperFragment(HonbakoPaperVertex in [[stage_in]], bool front [[front_facing]],
    texture2d<float> face [[texture(0)]], texture2d<float> reverse [[texture(1)]],
    sampler printSampler [[sampler(0)]]) {
    const float4 colour = front ? face.sample(printSampler, in.uv) : reverse.sample(printSampler, in.uv);
    if (colour.a < 0.005f) { discard_fragment(); }
    // Printed colour remains native; the receiving shadow supplies depth.
    return colour;
}
