#version 430

#extension GL_ARB_explicit_attrib_location : enable
#extension GL_ARB_gpu_shader5 : enable
#extension GL_GOOGLE_include_directive : enable

/**
 * COG INVASION ONLINE
 * Copyright (c) CIO Team. All rights reserved.
 *
 * @file vertexLitGeneric_PBR.frag.glsl
 * @author Brian Lach
 * @date March 09, 2019
 *
 * This is our big boy shader -- used for most models,
 * in particular ones that should be dynamically lit by light sources.
 *
 * Supports a plethora of material effects:
 * - $basetexture
 * - $bumpmap
 * - $envmap
 * - $phong
 * - $rimlight
 * - $halflambert
 * - $lightwarp
 * - $alpha/$translucent
 * - $selfillum
 *
 * And these render effects:
 * - Clip planes
 * - Flat colors
 * - Vertex colors
 * - Color scale
 * - Fog
 * - Lighting
 * - Cascaded shadow maps for directional lights
 * - Alpha testing
 * - Output normals/glow to auxiliary buffer
 *
 * Will eventually support:
 * - $detail (finer detail at close distance)
 *
 */

#pragma optionNV(unroll all)

#include "shaders/common_lighting_frag.inc.glsl"
#include "shaders/common_fog_frag.inc.glsl"
#include "shaders/common_frag.inc.glsl"
#include "shaders/common_sequences.inc.glsl"

#ifdef STATIC_PROP_LIGHTING
    in vec3 l_staticVertexLighting;
#endif

#ifdef NEED_WORLD_POSITION
    in vec4 l_worldPosition;
#endif

#ifdef NEED_WORLD_NORMAL
    in vec4 l_worldNormal;
    in mat3 l_tangentSpaceTranspose;
#endif

#ifdef NEED_EYE_POSITION
    in vec4 l_eyePosition;
#endif

#ifdef NEED_EYE_NORMAL
    in vec4 l_eyeNormal;
#endif

in vec4 l_texcoord;

#ifdef BASETEXTURE
    uniform sampler2D baseTextureSampler;
#elif defined(BASECOLOR)
    uniform vec4 baseColor;
#endif

#ifdef ENVMAP
    uniform samplerCube envmapSampler;
    uniform vec3 envmapTint;
#endif

#ifdef ARME
    // =========================
    // AO/Roughness/Metallic/Emissive texture
    // =========================
    uniform sampler2D armeSampler;
#else
    uniform vec4 armeParams;
#endif

#ifdef SELFILLUM
    uniform vec3 selfillumTint;
#endif

#ifdef NEED_WORLD_VEC
    in vec4 l_worldEyeToVert;
#endif

#ifdef RIMLIGHT
    uniform vec2 rimlightParams;
#endif

#ifdef BUMPMAP
    uniform sampler2D bumpSampler;
#endif

#ifdef NEED_TBN
    in vec4 l_tangent;
    in vec4 l_binormal;
#endif

in vec4 l_vertexColor;

#if defined(NUM_CLIP_PLANES) && NUM_CLIP_PLANES > 0
uniform vec4 p3d_WorldClipPlane[NUM_CLIP_PLANES];
#endif

uniform vec4 p3d_ColorScale;

#ifdef LIGHTING

    #ifdef BSP_LIGHTING

        uniform int lightTypes[NUM_LIGHTS];
        uniform int lightCount[1];
        uniform mat4 lightData[NUM_LIGHTS];
        uniform mat4 lightData2[NUM_LIGHTS];
        uniform vec3 ambientCube[6];

    #else // BSP_LIGHTING

        uniform struct p3d_LightSourceParameters {
            vec4 color;
            vec4 position;
            vec4 direction;
            vec4 spotParams;
            vec3 attenuation;
            #ifdef HAS_SHADOWED_LIGHT
                mat4 shadowViewMatrix;
                float hasShadows;
                #ifdef HAS_SHADOWED_POINT_LIGHT
                    samplerCube shadowMapCube;
                #endif
                #ifdef HAS_SHADOWED_SPOTLIGHT
                    sampler2D shadowMap2D;
                #endif
            #endif
        } p3d_LightSource[NUM_LIGHTS];

    #endif // BSP_LIGHTING

    #ifdef HAS_SHADOW_SUNLIGHT
        uniform sampler2DArray p3d_CascadeShadowMap;
        uniform mat4 p3d_CascadeMVPs[PSSM_SPLITS];
        in vec4 l_pssmCoords[PSSM_SPLITS];
        uniform vec4 wspos_view;
    #endif

    #ifdef HAS_SHADOWED_LIGHT
        in vec4 l_shadowCoords;
    #endif

#endif // LIGHTING

#ifdef AMBIENT_LIGHT
    uniform struct {
      vec4 ambient;
    } p3d_LightModel;
#endif // AMBIENT_LIGHT

#ifdef PLANAR_REFLECTION
    in vec4 l_texcoordReflection;
    uniform sampler2D reflectionSampler;
#endif

uniform vec4 p3d_TexAlphaOnly;

layout(location = COLOR_LOCATION) out vec4 outputColor;

// Auxilliary bitplanes for deferred passes
#ifdef NEED_AUX_NORMAL
    layout(location = AUX_NORMAL_LOCATION) out vec4 o_aux_normal;
#endif
#ifdef NEED_AUX_ARME
    layout(location = AUX_ARME_LOCATION) out vec4 o_aux_arme;
#endif
#ifdef NEED_AUX_BLOOM
    layout(location = AUX_BLOOM_LOCATION) out vec4 o_aux_bloom;
#endif

void main()
{
    // Clipping first!
    #if defined(NUM_CLIP_PLANES) && NUM_CLIP_PLANES > 0
        for (int i = 0; i < NUM_CLIP_PLANES; i++)
        {
            if (!ClipPlaneTest(l_worldPosition, p3d_WorldClipPlane[i]))
            {
                // pixel outside of clip plane interiors
                discard;
            }
        }
    #endif

    #ifdef BASETEXTURE
        vec4 albedo = SampleAlbedo(baseTextureSampler, l_texcoord.xy);
        albedo.a = clamp(albedo.a, 0, 1);
    #elif defined(BASECOLOR)
        vec4 albedo = baseColor;
    #else
        vec4 albedo = vec4(1, 1, 1, 1);
    #endif
    albedo += p3d_TexAlphaOnly;
    // Modulate albedo with vertex/flat colors
    albedo *= l_vertexColor;
    // Explicit alpha value from material.
    #ifdef ALPHA
        albedo.a *= ALPHA;
    #endif

    #ifdef ALPHA_TEST
        if (!AlphaTest(albedo.a))
        {
            discard;
        }
    #endif

    #ifdef NEED_EYE_NORMAL
        vec4 finalEyeNormal = normalize(l_eyeNormal);
    #else
        vec4 finalEyeNormal = vec4(0.0);
    #endif

    #ifdef NEED_WORLD_NORMAL
        vec4 finalWorldNormal = normalize(l_worldNormal);
        mat3 tangentSpaceTranspose = l_tangentSpaceTranspose;
        tangentSpaceTranspose[2] = finalWorldNormal.xyz;
    #else
        vec4 finalWorldNormal = vec4(0.0);
    #endif

    #ifdef BUMPMAP
        vec3 tangentSpaceNormal = GetTangentSpaceNormal(bumpSampler, l_texcoord.xy);
        #if defined(NEED_EYE_NORMAL)
            TangentToEye(finalEyeNormal.xyz, l_tangent.xyz,
                         l_binormal.xyz, tangentSpaceNormal);
        #endif
        #if defined(NEED_WORLD_NORMAL)
            TangentToWorld(finalWorldNormal.xyz, tangentSpaceTranspose, tangentSpaceNormal);
        #endif
    #else
        vec3 tangentSpaceNormal = vec3(0);
    #endif

    #ifdef NEED_WORLD_NORMAL
        float NdotV = clamp(abs(dot(finalWorldNormal.xyz, normalize(l_worldEyeToVert.xyz))), 0, 1);
    #else
        float NdotV = 1.0;
    #endif

    // AO/Roughness/Metallic/Emissive properties
    #ifdef ARME
        vec4 armeParams = texture(armeSampler, l_texcoord.xy);
    #endif
    // If we didn't get an ARME texture, armeParams is a shader input.

    /////////////////////////////////////////////////////
    // Aux bitplane outputs
    #ifdef NEED_AUX_NORMAL
        //#ifdef ENVMAP
        //    int hasEnvmap = 1;
        //#else
        //    int hasEnvmap = 0;
        //#endif
        o_aux_normal = vec4((finalWorldNormal.xyz * 0.5) + 0.5, 1);
    #endif
    #ifdef NEED_AUX_ARME
        o_aux_arme = armeParams;
    #endif
    /////////////////////////////////////////////////////

    vec3 specularColor = mix(vec3(0.04), albedo.rgb, armeParams.z);

    #ifdef LIGHTING

        // Initialize our lighting parameters
        LightingParams_t params = newLightingParams_t(
            l_worldPosition,
            normalize(l_worldEyeToVert.xyz),
            normalize(finalWorldNormal.xyz),
            NdotV,
            armeParams.y,
            armeParams.z,
            specularColor,
            albedo.rgb
            );

        vec3 ambientDiffuse = vec3(0, 0, 0);
        #ifdef BSP_LIGHTING
            ambientDiffuse += AmbientCubeLight(finalWorldNormal.xyz, ambientCube);
        #elif defined(AMBIENT_LIGHT)
            ambientDiffuse += p3d_LightModel.ambient.rgb;
        #endif

        // Multiply the ambient level by the exposure scale.  I don't know if
        // this makes much sense physically, but it works to only apply
        // exposure scaling onto materials that use lighting.
        //#ifdef HDR
        //    ambientDiffuse *= p3d_ExposureScale;
        //#endif

        #ifdef RIMLIGHT
            // Dedicated rim lighting for this pixel,
            // adds onto final lighting, uses ambient light as basis
            DedicatedRimTerm(params.totalRadiance, l_worldNormal.xyz,
                             l_worldEyeToVert.xyz, ambientDiffuse,
                             rimlightParams.x, rimlightParams.y);
        #endif

        // Now factor in local light sources
        #ifdef BSP_LIGHTING
            int lightType;
            for (int i = 0; i < lightCount[0]; i++)
        #else
            for (int i = 0; i < NUM_LIGHTS; i++)
        #endif
        {
            #ifdef BSP_LIGHTING
                params.lPos = lightData[i][0];
                params.lDir = lightData[i][1];
                params.lAtten = lightData[i][2];
                params.lColor = lightData[i][3];
                //params.falloff2 = lightData2[i][0];
                //params.falloff3 = lightData2[i][1];
                lightType = lightTypes[i];
            #else
                params.lColor = p3d_LightSource[i].color;
                bool isDirectional = p3d_LightSource[i].color.w == 1.0;
                bool isSpot = p3d_LightSource[i].direction.w == 1.0;
                bool isPoint = (!isDirectional && !isSpot);
                params.lPos = p3d_LightSource[i].position;
                params.lDir = normalize(p3d_LightSource[i].direction);
                params.lAtten = vec4(p3d_LightSource[i].attenuation, 0.0);
                params.lSpotParams = p3d_LightSource[i].spotParams;
                #if HAS_SHADOWED_LIGHT
                    bool hasShadows = int(p3d_LightSource[i].hasShadows) == 1;
                #endif
            #endif // BSP_LIGHTING

            #ifdef BSP_LIGHTING
                if (lightType == LIGHTTYPE_DIRECTIONAL)
            #else
                if (isDirectional)
            #endif
            {
                GetDirectionalLight(params
                                    #ifdef HAS_SHADOW_SUNLIGHT
                                        , p3d_CascadeShadowMap, l_pssmCoords,
                                        p3d_CascadeMVPs, wspos_view.xyz,
                                        l_worldPosition.xyz
                                    #endif // HAS_SHADOW_SUNLIGHT
                );
            }
            #ifdef BSP_LIGHTING
                else if (lightType == LIGHTTYPE_POINT)
            #else
                else if (isPoint)
            #endif
            {
                GetPointLight(params
                #ifdef HAS_SHADOWED_POINT_LIGHT
                    , hasShadows, p3d_LightSource[i].shadowMapCube, l_shadowCoords
                #endif
                );
            }
            #ifdef BSP_LIGHTING
                else if (lightType == LIGHTTYPE_SPOT)
            #else
                else if (isSpot)
            #endif
            {

                #ifdef HAS_SHADOWED_SPOTLIGHT
                    vec4 coords = p3d_LightSource[i].shadowViewMatrix * vec4(l_eyePosition.xyz, 1.0);
                    coords.xyz = coords.xyz / coords.w;
                #endif

                GetSpotlight(params
                #ifdef HAS_SHADOWED_SPOTLIGHT
                    , hasShadows, p3d_LightSource[i].shadowMap2D, coords
                #endif
                );
            }
        }

        vec3 totalRadiance = max(vec3(0), params.totalRadiance);

    #else // LIGHTING

        // No direct lighting.  Just give it the ambient if we have it.
        #ifdef AMBIENT_LIGHT
            vec3 ambientDiffuse = p3d_LightModel.ambient.rgb;
        #else
            // No direct or ambient lighting.  Make it fullbright.
            vec3 ambientDiffuse = vec3(1.0);
        #endif
        vec3 totalRadiance = vec3(0);

    #endif // LIGHTING

    // Modulate with albedo
    ambientDiffuse.rgb *= albedo.rgb;
    ambientDiffuse.rgb *= armeParams.x;

	//#ifndef LIGHTING
	//	vec3 kD = vec3(1.0);
	//#else
		vec3 F = Fresnel_Schlick(specularColor, NdotV);
	//#endif

    vec3 specularLighting = vec3(0);

    //#ifdef LIGHTING
        #if defined(ENVMAP) || defined(PLANAR_REFLECTION)

            #ifdef ENVMAP
                vec3 spec = SampleCubeMapLod(l_worldEyeToVert.xyz,
                                            finalWorldNormal,
                                            envmapSampler, armeParams.y).rgb;
            #elif defined(PLANAR_REFLECTION)
                vec2 reflCoords = l_texcoordReflection.xy / l_texcoordReflection.w;
                vec3 spec = texture(reflectionSampler, reflCoords).rgb;
            #endif

            // TODO: use a BRDF lookup texture in SHADERQUALITY_MEDIUM
            #if SHADER_QUALITY > SHADERQUALITY_LOW
                vec3 iblspec = spec * EnvironmentBRDF(armeParams.y, NdotV, F);
            #else
                vec3 iblspec = spec * F * specularColor;
            #endif

            specularLighting += iblspec;

        #endif
    //#endif

	vec3 totalAmbient = ambientDiffuse;
    vec3 totalLight = totalAmbient + totalRadiance;
    #ifdef STATIC_PROP_LIGHTING
        totalLight *= l_staticVertexLighting;
    #endif

    vec3 color = totalLight + specularLighting;

    #ifdef SELFILLUM
        float selfillumMask = armeParams.w;
        color = mix(color, selfillumTint * albedo.rgb, selfillumMask);
    #endif

    outputColor = vec4(color, albedo.a);

    #ifdef FOG
		ApplyFog(outputColor, l_eyePosition);
    #endif

    // Done!
	FinalOutput(outputColor);

    #ifdef NEED_AUX_BLOOM
        #ifndef NO_BLOOM
            o_aux_bloom = outputColor;
        #else
            o_aux_bloom = vec4(0, 0, 0, outputColor.a);
        #endif
    #endif
}
