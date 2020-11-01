/**
 * COG INVASION ONLINE
 * Copyright (c) CIO Team. All rights reserved.
 *
 * @file common_vert.inc.glsl
 * @author Brian Lach
 * @date November 02, 2018
 */

#ifndef COMMON_VERT_INC_GLSL
#define COMMON_VERT_INC_GLSL

vec2 GetNormalizedScreenCoords(vec4 vpos)
{
    vec3 ndc = vpos.xyz / vpos.w;
    return ndc.xy * 0.5 + 0.5;
}

#endif // COMMON_VERT_INC_GLSL
