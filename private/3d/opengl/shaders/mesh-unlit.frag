#version 150

in vec4 vertexColor;
in vec3 worldPosition;

uniform vec4 materialColor;
uniform float objectOpacity;
uniform int useVertexColor;
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
  fragment = base;
}
