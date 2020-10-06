//
//  default.metal
//  MetalExample
//
//  Created by cookie on 2018/10/17.
//  Copyright © 2018 zhubingyi. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;


struct VertexOut
{
    float4 position [[position]];
    float4 texCoords;
};

struct VertexIn
{
    float4 position          [[attribute(0)]];
    float4 texCoords         [[attribute(1)]];
};

vertex VertexOut passThroughVertex(VertexIn vertexIn [[stage_in]])
{
    VertexOut out;
    out.position  = vertexIn.position;
    out.texCoords = vertexIn.texCoords;
    return out;
}

fragment float4 passThroughFragment(VertexOut in                [[stage_in]],
                                    texture2d<float> texture    [[texture(0)]])
{
    constexpr sampler colorSampler;
    float2 position = float2(in.texCoords.x, in.texCoords.y);
    return texture.sample(colorSampler, position);
}
