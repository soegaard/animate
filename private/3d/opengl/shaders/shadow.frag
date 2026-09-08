#version 150

in vec3 worldPosition;

uniform int clipCount;
uniform vec4 clipPlanes[ANIMATE_OPENGL_MAX_CLIP_PLANES];

void main() {
  for (int index = 0; index < clipCount; ++index) {
    if (dot(clipPlanes[index].xyz, worldPosition) + clipPlanes[index].w < 0.0)
      discard;
  }
}
