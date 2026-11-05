precision highp float;
varying vec4 vColor;
varying vec2 vTexCoord;
uniform float cTime;





  uniform vec4 cMagicColor;
  uniform vec4 cLyricsColor;
  uniform vec4 cLyricsColorDeep;
  uniform vec4 cWaveCircle1;
  uniform vec4 cWaveCircle2;
  uniform vec4 cWaveCircle3;
  uniform vec4 cWaveCircle4;
  uniform vec4 cWaveCircle5;
  uniform vec2 cCanvasSize;
  uniform float cCurveIntensity;
  uniform float cCurveSharpness;
  uniform float cLeftWaveHeight;
  uniform float cRightWaveHeight;
  uniform float cLeftWaveWidth;
  uniform float cRightWaveWidth;
  uniform float cLeftWaveSpeed;
  uniform float cRightWaveSpeed;
  uniform float cLeftWaveRadius;
  uniform float cRightWaveRadius;
  uniform float cLeftCircleR;
  uniform float cRightCircleR;
uniform sampler2D sDiffMap;
vec3 permute(vec3 x) {
 return mod(((x*34.0)+1.0)*x, 289.0);
}
float snoise(vec2 v) {
 const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                     -0.577350269189626, 0.024390243902439);
 vec2 i  = floor(v + dot(v, C.yy));
 vec2 x0 = v -   i + dot(i, C.xx);
 vec2 i1;
 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
 vec4 x12 = x0.xyxy + C.xxzz;
 x12.xy -= i1;
 i = mod(i, 289.0);
 vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
     + i.x + vec3(0.0, i1.x, 1.0));
 vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy),
     dot(x12.zw, x12.zw)), 0.0);
 m = m * m;
 m = m * m;
 vec3 x = 2.0 * fract(p * C.www) - 1.0;
 vec3 h = abs(x) - 0.5;
 vec3 ox = floor(x + 0.5);
 vec3 a0 = x - ox;
 m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
 vec3 g;
 g.x = a0.x * x0.x + h.x * x0.y;
 g.yz = a0.yz * x12.xz + h.yz * x12.yw;
 return 130.0 * dot(m, g);
}
float perlinNoise(vec2 st) {
 return snoise(st) * 0.5 + 0.5;
}
float solidCircle(vec2 pos, float r, float blur, vec2 uv) {
 float l = length(uv - pos);
 return smoothstep(r, r - blur, l);
}
float borderCircle(vec2 pos, float r1, float r2, float blur, vec2 uv) {
 float s1 = solidCircle(pos, r1, blur, uv);
 float s2 = solidCircle(pos, r2, blur, uv);
 return s1 - s2;
}
float ripple(vec2 uv, vec2 center, float radius, float width, float height, float speed) {
 float dist = length(uv - center);
 float wave = sin((dist * 3.14159 * 2.0 / width - speed * cTime) * 2.0) * 0.5 + 0.5;
 float envelope = 1.0 - smoothstep(radius - width, radius + width, dist);
 return wave * envelope * height;
}
float drawCircle(vec2 uv, vec2 center, float radius, float width, float softness, float noise, float noise_strength) {
 float dist = length(uv - center);
 float inner = radius - width / 2.0;
 float outer = radius + width / 2.0;
 float base_circle = smoothstep(inner - softness, inner, dist) *
                    (1.0 - smoothstep(outer, outer + softness, dist));
 return base_circle * (noise) * noise_strength;
}
vec3 blendMultiply(vec3 base, vec3 blend) {
   return base*blend;
}
vec3 blendMultiply(vec3 base, vec3 blend, float opacity) {
   return (blendMultiply(base, blend) * opacity + base * (1.0 - opacity));
}
float clampValue(float value, float minValue, float maxValue) {
   return min(max(value, minValue), maxValue);
}
vec4 frag () {
vec2 uv0 = vTexCoord;

 vec4 o = texture2D(sDiffMap, uv0);
 vec2 scalex_vec = vec2(cCanvasSize.x / cCanvasSize.y, 1.0);
 vec2 st = uv0 * scalex_vec;
 float left_data = cCurveIntensity * 10.0;
 float right_data = cCurveSharpness * 10.0;
 vec2 ripple1_center = vec2(1628.0/1624.0, 384.0/780.0) * scalex_vec;
 float ripple1_radius = cRightWaveRadius;
 float wave1_width = cRightWaveWidth;
 float wave1_height = clampValue(cRightWaveHeight +  pow(right_data * 0.1, 5.0), cRightWaveHeight, 1.2);
 float wave1_speed = cRightWaveSpeed;
 vec2 ripple2_center = vec2(-12.0/1624.0, 380.0/780.0) * scalex_vec;
 float ripple2_radius = cLeftWaveRadius;
 float wave2_width = cLeftWaveWidth;
 float wave2_height = clampValue(cLeftWaveHeight  + 0.5 * left_data , cLeftWaveHeight, 0.6);
 float wave2_speed = cLeftWaveSpeed;
 float ripple_effect_right = ripple(st, ripple1_center, ripple1_radius, wave1_width, wave1_height, wave1_speed);
 float ripple_effect_left = ripple(st, ripple2_center, ripple2_radius, wave2_width, wave2_height, wave2_speed);
 float waveBlur = 0.01;
 float waveR_width = 0.04;
 float waveRRight_width = 0.04;
 float wave_circle_time1 = cWaveCircle1.x;
 float wave_circle_time2 = cWaveCircle2.x;
 float wave_circle_time3 = cWaveCircle3.x;
 float wave_circle_time4 = cWaveCircle4.x;
 float wave_circle_time5 = cWaveCircle5.x;
 float r = 0.04 * 0.1 * 0.7;
 float waveR1 = wave_circle_time1 * r;
 float waveR2 = wave_circle_time2 * r;
 float waveR3 = wave_circle_time3 * r;
 float waveR4 = wave_circle_time4 * r;
 float waveR5 = wave_circle_time5 * r;
 float wave_offset1 = ripple(st, ripple2_center, ripple2_radius, wave2_width, cWaveCircle1.z, cWaveCircle1.y);
 float wave_offset2 = ripple(st, ripple2_center, ripple2_radius, wave2_width, cWaveCircle2.z, cWaveCircle2.y);
 float wave_offset3 = ripple(st, ripple2_center, ripple2_radius, wave2_width, cWaveCircle3.z, cWaveCircle3.y);
 float wave_offset4 = ripple(st, ripple2_center, ripple2_radius, wave2_width, cWaveCircle4.z, cWaveCircle4.y);
 float wave_offset5 = ripple(st, ripple2_center, ripple2_radius, wave2_width, cWaveCircle5.z, cWaveCircle5.y);
 float waveCircle1 = borderCircle(ripple2_center, waveR1, waveR1 - waveR_width, waveBlur, st);
 float waveCircle2 = borderCircle(ripple2_center, waveR2, waveR2 - waveR_width, waveBlur, st);
 float waveCircle3 = borderCircle(ripple2_center, waveR3, waveR3 - waveR_width, waveBlur, st);
 float waveCircle4 = borderCircle(ripple2_center, waveR4, waveR4 - waveR_width, waveBlur, st);
 float waveCircle5 = borderCircle(ripple2_center, waveR5, waveR5 - waveR_width, waveBlur, st);
 float wave_offset_right1 = ripple(st, ripple1_center, ripple1_radius, wave1_width, cWaveCircle1.z, cWaveCircle1.y);
 float wave_offset_right2 = ripple(st, ripple1_center, ripple1_radius, wave1_width, cWaveCircle2.z, cWaveCircle2.y);
 float wave_offset_right3 = ripple(st, ripple1_center, ripple1_radius, wave1_width, cWaveCircle3.z, cWaveCircle3.y);
 float wave_offset_right4 = ripple(st, ripple1_center, ripple1_radius, wave1_width, cWaveCircle4.z, cWaveCircle4.y);
 float wave_offset_right5 = ripple(st, ripple1_center, ripple1_radius, wave1_width, cWaveCircle5.z, cWaveCircle5.y);
 float waveCircleRight1 = borderCircle(ripple1_center, waveR1, waveR1 - waveRRight_width, waveBlur, st);
 float waveCircleRight2 = borderCircle(ripple1_center, waveR2, waveR2 - waveRRight_width, waveBlur, st);
 float waveCircleRight3 = borderCircle(ripple1_center, waveR3, waveR3 - waveRRight_width, waveBlur, st);
 float waveCircleRight4 = borderCircle(ripple1_center, waveR4, waveR4 - waveRRight_width, waveBlur, st);
 float waveCircleRight5 = borderCircle(ripple1_center, waveR5, waveR5 - waveRRight_width, waveBlur, st);
 float wave_offset_scale = 0.7;
 float wave_offset_right_scale = 0.3;
 ripple_effect_left = ripple_effect_left +
 waveCircle1 * wave_offset_scale * wave_offset1 +
 waveCircle2 * wave_offset_scale * wave_offset2 +
 waveCircle3 * wave_offset_scale * wave_offset3 +
 waveCircle4 * wave_offset_scale * wave_offset4 +
 waveCircle5 * wave_offset_scale * wave_offset5;
 ripple_effect_right = ripple_effect_right +
 waveCircleRight1 * wave_offset_right_scale * wave_offset_right1 +
 waveCircleRight2 * wave_offset_right_scale * wave_offset_right2 +
 waveCircleRight3 * wave_offset_right_scale * wave_offset_right3 +
 waveCircleRight4 * wave_offset_right_scale * wave_offset_right4 +
 waveCircleRight5 * wave_offset_right_scale * wave_offset_right5;
 vec2 combined_ripple = ripple_effect_right * (st - ripple1_center) + ripple_effect_left * (st - ripple2_center);
 float noise_scale = 1.0;
 float noise_strength = 0.15;
 vec2 distorted_uv = uv0 + ripple_effect_right  * (st - ripple1_center) ;
 float noise = perlinNoise(distorted_uv * noise_scale);
 distorted_uv = uv0 + combined_ripple;
 vec2 left_uv = st + ripple_effect_left * (st - ripple2_center);
 vec2 right_uv = st + ripple_effect_right * (st - ripple1_center);
 vec2 left_clear_uv = st  + ripple_effect_left * (st - ripple2_center);
 vec2 right_clear_uv = st + ripple_effect_right * (st - ripple1_center);
 o = texture2D(sDiffMap, distorted_uv);
 vec2 circle_position = vec2(-0.018, 0.5);
 float circle_radius = 0.5128;
 float circle_width = 10./780.;
 float circle_softness = 0.05;
 vec4 circle_color = vec4(1.0 * 0.94);
 vec2 scaled_center = circle_position * scalex_vec;
 float circle = drawCircle(left_uv, scaled_center, circle_radius, circle_width, circle_softness, noise, noise_strength);
 o = mix(o, circle_color, circle * circle_color.a);
 vec2 circle2_position = vec2(-0.069, 0.5);
 vec2 scaled_center2 = circle2_position * scalex_vec;
 float circle2 = drawCircle(left_uv, scaled_center2, circle_radius, circle_width, circle_softness, noise, noise_strength);
 vec4 circle2_color = vec4(1.0 * 1.0);
 o = mix(o, circle2_color, circle2 * circle2_color.a);
 vec2 circle3_position = vec2(-0.04, 0.5);
 float circle3_radius = circle_radius * 1.38;
 float circle3_width = 6.0/cCanvasSize.x;
 vec2 scaled_center3 = circle3_position * scalex_vec;
 float circle3 = drawCircle(left_uv, scaled_center3, circle3_radius, circle3_width, circle_softness, noise, noise_strength);
 vec4 circle3_color = vec4(1.0 * 0.94);
 o = mix(o, circle3_color, circle3 * circle3_color.a);
 vec2 circle4_position = ripple2_center;
 float circle4_radius = cLeftCircleR;
 float circle4_width = 16.0/cCanvasSize.y;
 vec2 scaled_center4 = circle4_position * scalex_vec;
 float circle4 = drawCircle(left_clear_uv, scaled_center4, circle4_radius, circle4_width, 0.0, 1.0, 0.3);
 vec4 circle4_color = vec4(1.0 * 0.50);
 vec2 circle5_position = vec2(0.95, 0.5) * scalex_vec;
 float circle5_radius = 0.5128;
 float circle5_width = 0.01;
 vec2 scaled_center5 = circle5_position;
 float circle5 = drawCircle(right_uv, scaled_center5, circle5_radius, circle_width, circle_softness, noise, noise_strength);
 vec4 circle5_color = vec4(1.0 * 0.94);
 o = mix(o, circle5_color, circle5 * circle5_color.a);
 vec2 circle6_position = vec2(0.98, 0.5);
 float circle6_radius = cRightCircleR;
 float circle6_width = 10.0/cCanvasSize.y;
 vec2 scaled_center6 = circle6_position * scalex_vec;
 float circle6 = drawCircle(right_clear_uv, scaled_center6, circle6_radius, circle6_width, 0.0, 1.0, 0.3);
 vec4 circle6_color = vec4(1.0 * 1.0);
   o.rgb = blendMultiply(o.rgb, cMagicColor.rgb, o.a);
   o = mix(o, cLyricsColor, circle6 * circle6_color.a);
   o = mix(o, cLyricsColor, circle4 * circle4_color.a);
   o.a = 1.0;
 return o;
}
void main() { gl_FragColor = frag(); }
