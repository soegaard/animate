#version 150

in vec3 position;
in vec3 normal;
in vec4 color;

uniform mat4 model;
uniform mat4 viewProjection;
uniform mat3 normalMatrix;

out vec4 vertexColor;
out vec3 worldNormal;
out vec3 worldPosition;

void main() {
  vec4 world = model * vec4(position, 1.0);
  worldPosition = world.xyz;
  worldNormal = normalize(normalMatrix * normal);
  vertexColor = color;
  gl_Position = viewProjection * world;
}
