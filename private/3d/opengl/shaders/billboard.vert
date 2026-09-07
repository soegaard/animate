#version 150

in vec4 position;
in vec2 uv;

out vec2 textureCoordinate;

void main() {
  textureCoordinate = uv;
  gl_Position = position;
}
