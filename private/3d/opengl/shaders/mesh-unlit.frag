#version 150

in vec4 vertexColor;
in vec3 worldPosition;

uniform vec4 materialColor;
uniform float objectOpacity;
uniform int useVertexColor;
uniform vec3 materialEmission;
uniform float materialEmissionStrength;
uniform int clipCount;
uniform vec4 clipPlanes[ANIMATE_OPENGL_MAX_CLIP_PLANES];

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
  base.a *= objectOpacity;
  vec3 result = srgbToLinear(base.rgb)
                + srgbToLinear(materialEmission) * materialEmissionStrength;
  fragment = vec4(result * base.a, base.a);
}
