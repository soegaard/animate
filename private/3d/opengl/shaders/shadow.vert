#version 150

in vec3 position;

uniform mat4 model;
uniform mat4 viewProjection;

out vec3 worldPosition;

void main() {
  vec4 world = model * vec4(position, 1.0);
  worldPosition = world.xyz;
  gl_Position = viewProjection * world;
}
