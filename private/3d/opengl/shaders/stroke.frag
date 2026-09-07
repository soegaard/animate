#version 150

in vec4 vertexColor;
out vec4 fragment;

vec3 srgbToLinear(vec3 color) {
  vec3 low = color / 12.92;
  vec3 high = pow((color + 0.055) / 1.055, vec3(2.4));
  return mix(high, low, lessThanEqual(color, vec3(0.04045)));
}

void main() {
  fragment = vec4(srgbToLinear(vertexColor.rgb) * vertexColor.a, vertexColor.a);
}
