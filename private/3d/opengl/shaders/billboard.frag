#version 150

in vec2 textureCoordinate;
uniform sampler2D billboardTexture;
uniform float billboardOpacity;

out vec4 fragment;

void main() {
  vec4 source = texture(billboardTexture, textureCoordinate);
  float alpha = source.a * billboardOpacity;
  fragment = vec4(source.rgb * alpha, alpha);
}
