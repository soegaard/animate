#version 150

in vec4 vertexColor;
in vec3 worldNormal;
in vec3 worldPosition;

uniform vec4 materialColor;
uniform float objectOpacity;
uniform int useVertexColor;
uniform float materialAmbient;
uniform float materialDiffuse;
uniform float materialSpecular;
uniform vec3 materialSpecularColor;
uniform float materialSpecularExponent;
uniform int materialLighting;
uniform vec3 materialEmission;
uniform float materialEmissionStrength;
uniform int materialReceivesShadow;
uniform vec3 cameraPosition;
uniform vec3 ambientLight;
// One packed sequence preserves the authored order of directional, point and
// spot lights.  The renderer preflights the public 4/8/4 per-kind limits;
// this total is their fixed shader storage.
const int MAX_NON_AMBIENT_LIGHTS = 16;
uniform int nonAmbientLightCount;
uniform int nonAmbientLightKinds[MAX_NON_AMBIENT_LIGHTS];
uniform vec3 nonAmbientLightDirections[MAX_NON_AMBIENT_LIGHTS];
uniform vec3 nonAmbientLightPositions[MAX_NON_AMBIENT_LIGHTS];
uniform vec3 nonAmbientLightColors[MAX_NON_AMBIENT_LIGHTS];
uniform float nonAmbientLightIntensities[MAX_NON_AMBIENT_LIGHTS];
uniform int nonAmbientLightAttenuationModes[MAX_NON_AMBIENT_LIGHTS];
uniform vec3 nonAmbientLightAttenuationABC[MAX_NON_AMBIENT_LIGHTS];
uniform float nonAmbientLightCutoffs[MAX_NON_AMBIENT_LIGHTS];
uniform float nonAmbientLightRanges[MAX_NON_AMBIENT_LIGHTS];
uniform float nonAmbientLightInnerAngles[MAX_NON_AMBIENT_LIGHTS];
uniform float nonAmbientLightOuterAngles[MAX_NON_AMBIENT_LIGHTS];

// Shadow maps retain the authored non-ambient-light index. Eight is the
// published 4-directional + 4-spot limit; point-light cube maps are deferred.
const int MAX_SHADOW_MAPS = 8;
uniform int shadowMapCount;
uniform int shadowMapLightIndices[MAX_SHADOW_MAPS];
uniform mat4 shadowViewProjections[MAX_SHADOW_MAPS];
uniform vec2 shadowTexelSizes[MAX_SHADOW_MAPS];
uniform float shadowDepthBiases[MAX_SHADOW_MAPS];
uniform float shadowNormalBiases[MAX_SHADOW_MAPS];
uniform int shadowPcfRadii[MAX_SHADOW_MAPS];
uniform sampler2DShadow shadowMap0;
uniform sampler2DShadow shadowMap1;
uniform sampler2DShadow shadowMap2;
uniform sampler2DShadow shadowMap3;
uniform sampler2DShadow shadowMap4;
uniform sampler2DShadow shadowMap5;
uniform sampler2DShadow shadowMap6;
uniform sampler2DShadow shadowMap7;
uniform int clipCount;
uniform vec4 clipPlanes[8];

out vec4 fragment;

vec3 srgbToLinear(vec3 color) {
  vec3 low = color / 12.92;
  vec3 high = pow((color + 0.055) / 1.055, vec3(2.4));
  return mix(high, low, lessThanEqual(color, vec3(0.04045)));
}

vec3 safeNormalize(vec3 value, vec3 fallback) {
  float magnitude = length(value);
  return (magnitude > 0.0) ? value / magnitude : fallback;
}

float finiteLightAttenuation(int index, float distance) {
  float range = nonAmbientLightRanges[index];
  float cutoff = nonAmbientLightCutoffs[index];
  if ((range >= 0.0 && distance > range) ||
      (cutoff >= 0.0 && distance > cutoff))
    return 0.0;
  int mode = nonAmbientLightAttenuationModes[index];
  vec3 parameters = nonAmbientLightAttenuationABC[index];
  if (mode == 0)
    return parameters.x;
  if (mode == 1) {
    float referenceDistance = parameters.z;
    float denominator = max(distance, referenceDistance);
    return pow(referenceDistance / denominator, 2.0);
  }
  return 1.0 / (parameters.x + parameters.y * distance
                + parameters.z * distance * distance);
}

float spotConeFactor(int index, vec3 incoming, float distance) {
  if (distance == 0.0)
    return 1.0;
  vec3 outgoing = -incoming;
  float cosine = clamp(dot(nonAmbientLightDirections[index], outgoing), -1.0, 1.0);
  float angle = acos(cosine);
  float innerAngle = nonAmbientLightInnerAngles[index];
  float outerAngle = nonAmbientLightOuterAngles[index];
  if (angle <= innerAngle)
    return 1.0;
  if (angle >= outerAngle)
    return 0.0;
  float progress = (outerAngle - angle) / (outerAngle - innerAngle);
  return progress * progress * (3.0 - 2.0 * progress);
}

float shadowCompareAt(int shadowIndex, vec2 uv, float referenceDepth) {
  if (shadowIndex == 0) return texture(shadowMap0, vec3(uv, referenceDepth));
  if (shadowIndex == 1) return texture(shadowMap1, vec3(uv, referenceDepth));
  if (shadowIndex == 2) return texture(shadowMap2, vec3(uv, referenceDepth));
  if (shadowIndex == 3) return texture(shadowMap3, vec3(uv, referenceDepth));
  if (shadowIndex == 4) return texture(shadowMap4, vec3(uv, referenceDepth));
  if (shadowIndex == 5) return texture(shadowMap5, vec3(uv, referenceDepth));
  if (shadowIndex == 6) return texture(shadowMap6, vec3(uv, referenceDepth));
  return texture(shadowMap7, vec3(uv, referenceDepth));
}

// The map stores the native depth produced by exactly the same light
// projection, so receiver depth is compared in clip-depth space. The public
// depth/normal controls keep their published additive schema; they apply to
// this backend's normalized depth representation. Subtracting the bias from
// the comparison reference is equivalent to testing receiver <= map + bias.
float shadowFactor(int lightIndex, vec3 normal, vec3 lightDirection) {
  if (materialReceivesShadow == 0)
    return 1.0;
  for (int shadowIndex = 0; shadowIndex < shadowMapCount; ++shadowIndex) {
    if (shadowMapLightIndices[shadowIndex] == lightIndex) {
      vec4 clip = shadowViewProjections[shadowIndex] * vec4(worldPosition, 1.0);
      if (clip.w <= 0.0)
        return 1.0;
      vec3 ndc = clip.xyz / clip.w;
      if (abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0 || ndc.z < -1.0 || ndc.z > 1.0)
        return 1.0;
      vec2 uv = ndc.xy * 0.5 + 0.5;
      float receiverDepth = ndc.z * 0.5 + 0.5;
      float bias = shadowDepthBiases[shadowIndex]
                   + shadowNormalBiases[shadowIndex]
                     * (1.0 - max(0.0, dot(normal, lightDirection)));
      int radius = shadowPcfRadii[shadowIndex];
      vec2 texel = shadowTexelSizes[shadowIndex];
      float lit = 0.0;
      float samples = 0.0;
      for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
          vec2 sampleUV = uv + vec2(float(dx), float(dy)) * texel;
          if (sampleUV.x < 0.0 || sampleUV.x > 1.0 ||
              sampleUV.y < 0.0 || sampleUV.y > 1.0) {
            lit += 1.0;
          } else {
            lit += shadowCompareAt(shadowIndex, sampleUV, receiverDepth - bias);
          }
          samples += 1.0;
        }
      }
      return lit / samples;
    }
  }
  return 1.0;
}

void main() {
  for (int index = 0; index < clipCount; ++index) {
    if (dot(clipPlanes[index].xyz, worldPosition) + clipPlanes[index].w < 0.0)
      discard;
  }
  vec4 base = (useVertexColor != 0) ? vertexColor : materialColor;
  base.rgb = srgbToLinear(base.rgb);
  vec3 illumination = ambientLight * materialAmbient;
  vec3 specularIllumination = vec3(0.0);
  vec3 normal = normalize(worldNormal);
  vec3 viewDirection = normalize(cameraPosition - worldPosition);
  for (int index = 0; index < nonAmbientLightCount; ++index) {
    int kind = nonAmbientLightKinds[index];
    vec3 lightDirection;
    float attenuation = 1.0;
    float cone = 1.0;
    if (kind == 0) {
      lightDirection = -nonAmbientLightDirections[index];
    } else {
      vec3 displacement = nonAmbientLightPositions[index] - worldPosition;
      float distance = length(displacement);
      lightDirection = safeNormalize(displacement, normal);
      attenuation = finiteLightAttenuation(index, distance);
      if (kind == 2)
        cone = spotConeFactor(index, lightDirection, distance);
    }
    float facing = max(0.0, dot(normal, lightDirection));
    float energy = nonAmbientLightIntensities[index] * attenuation * cone
                   * shadowFactor(index, normal, lightDirection);
    illumination += srgbToLinear(nonAmbientLightColors[index])
                    * (energy * materialDiffuse * facing);
    if (materialLighting != 0 && facing > 0.0) {
      vec3 halfVector = normalize(lightDirection + viewDirection);
      float highlight = pow(max(0.0, dot(normal, halfVector)), materialSpecularExponent);
      specularIllumination += srgbToLinear(nonAmbientLightColors[index])
                              * (energy * materialSpecular * highlight);
    }
  }
  float alpha = base.a * objectOpacity;
  vec3 result = base.rgb * illumination
                + srgbToLinear(materialSpecularColor) * specularIllumination
                + srgbToLinear(materialEmission) * materialEmissionStrength;
  fragment = vec4(result * alpha, alpha);
}
