#version 150

in vec4 vertexColor;
in vec3 worldPosition;

uniform vec4 materialColor;
uniform float objectOpacity;
uniform int useVertexColor;
uniform vec3 materialEmission;
uniform float materialEmissionStrength;
uniform int clipCount;
uniform vec4 clipPlanes[8];

out vec4 fragment;

void main() {
  for (int index = 0; index < clipCount; ++index) {
    if (dot(clipPlanes[index].xyz, worldPosition) + clipPlanes[index].w < 0.0)
      discard;
  }
  vec4 base = (useVertexColor != 0) ? vertexColor : materialColor;
  base.a *= objectOpacity;
  vec3 result = clamp(base.rgb + materialEmission * materialEmissionStrength, 0.0, 1.0);
  fragment = vec4(result * base.a, base.a);
}
