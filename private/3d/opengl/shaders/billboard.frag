#version 150

in vec2 textureCoordinate;
uniform sampler2D billboardTexture;
uniform float billboardOpacity;

out vec4 fragment;

vec3 srgbToLinear(vec3 color) {
  vec3 low = color / 12.92;
  vec3 high = pow((color + 0.055) / 1.055, vec3(2.4));
  return mix(high, low, lessThanEqual(color, vec3(0.04045)));
}

void main() {
  vec4 source = texture(billboardTexture, textureCoordinate);
  float alpha = source.a * billboardOpacity;
  fragment = vec4(srgbToLinear(source.rgb) * alpha, alpha);
}
