#version 150

in vec4 vertexColor;
in vec3 worldNormal;
in vec3 worldPosition;

uniform vec4 materialColor;
uniform float objectOpacity;
uniform int useVertexColor;
uniform float materialAmbient;
uniform float materialDiffuse;
uniform vec3 ambientLight;
uniform int directionalCount;
uniform vec3 directionalDirections[4];
uniform vec3 directionalColors[4];
uniform float directionalIntensities[4];
uniform int clipCount;
uniform vec4 clipPlanes[8];

out vec4 fragment;

void main() {
  for (int index = 0; index < clipCount; ++index) {
    if (dot(clipPlanes[index].xyz, worldPosition) + clipPlanes[index].w < 0.0)
      discard;
  }
  vec4 base = (useVertexColor != 0) ? vertexColor : materialColor;
  vec3 illumination = ambientLight * materialAmbient;
  vec3 normal = normalize(worldNormal);
  for (int index = 0; index < directionalCount; ++index) {
    float facing = max(0.0, dot(normal, -directionalDirections[index]));
    illumination += directionalColors[index]
                    * (directionalIntensities[index] * materialDiffuse * facing);
  }
  float alpha = base.a * objectOpacity;
  fragment = vec4(clamp(base.rgb * illumination, 0.0, 1.0) * alpha, alpha);
}
