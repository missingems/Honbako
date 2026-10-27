#include <metal_stdlib>
using namespace metal;

// A printed, laminated cover. The artwork stays upright and undistorted; its
// shallow binding, edge relief, and broad reflection come from one light field.
kernel void honbako_cover_material(texture2d<float, access::read> original [[texture(0)]],
                                  texture2d<float, access::write> finished [[texture(1)]],
                                  uint2 pixel [[thread_position_in_grid]]) {
    uint2 size(original.get_width(), original.get_height());
    if (pixel.x >= size.x || pixel.y >= size.y) return;
    float4 print = original.read(pixel);
    if (print.a < 0.0001f) { finished.write(float4(0), pixel); return; }
    float2 uv = (float2(pixel) + 0.5f) / float2(size);
    float binding = exp(-uv.x / 0.028f);
    float ridge = exp(-pow((uv.x - 0.022f) / 0.009f, 2.0f));
    float joint = exp(-pow((uv.x - 0.052f) / 0.009f, 2.0f));
    float outer = exp(-(1.0f - uv.x) / 0.004f);
    float top = exp(-uv.y / 0.005f);
    float bottom = exp(-(1.0f - uv.y) / 0.006f);
    float diagonal = exp(-pow((uv.x + uv.y * 0.38f - 0.62f) / 0.22f, 2.0f));
    float light = 1.0f - 0.19f * binding - 0.035f * joint - 0.025f * bottom;
    float reflection = 0.055f * ridge + 0.022f * outer + 0.014f * top + 0.027f * diagonal;
    float luminance = dot(print.rgb / print.a, float3(0.2126f, 0.7152f, 0.0722f));
    float3 color = print.rgb * light + reflection * (0.28f + 0.72f * luminance) * print.a;
    finished.write(float4(clamp(color, 0.0f, print.a), print.a), pixel);
}
