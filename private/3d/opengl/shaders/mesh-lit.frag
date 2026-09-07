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
uniform vec3 cameraPosition;
uniform vec3 ambientLight;
uniform int directionalCount;
uniform vec3 directionalDirections[4];
uniform vec3 directionalColors[4];
uniform float directionalIntensities[4];
uniform int clipCount;
uniform vec4 clipPlanes[8];

out vec4 fragment;

vec3 srgbToLinear(vec3 color) {
  vec3 low = color / 12.92;
  vec3 high = pow((color + 0.055) / 1.055, vec3(2.4));
  return mix(high, low, lessThanEqual(color, vec3(0.04045)));
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
  for (int index = 0; index < directionalCount; ++index) {
    vec3 lightDirection = -directionalDirections[index];
    float facing = max(0.0, dot(normal, lightDirection));
    illumination += srgbToLinear(directionalColors[index])
                    * (directionalIntensities[index] * materialDiffuse * facing);
    if (materialLighting != 0 && facing > 0.0) {
      vec3 halfVector = normalize(lightDirection + viewDirection);
      float highlight = pow(max(0.0, dot(normal, halfVector)), materialSpecularExponent);
      specularIllumination += srgbToLinear(directionalColors[index])
                              * (directionalIntensities[index] * materialSpecular * highlight);
    }
  }
  float alpha = base.a * objectOpacity;
  vec3 result = base.rgb * illumination
                + srgbToLinear(materialSpecularColor) * specularIllumination
                + srgbToLinear(materialEmission) * materialEmissionStrength;
  fragment = vec4(result * alpha, alpha);
}
