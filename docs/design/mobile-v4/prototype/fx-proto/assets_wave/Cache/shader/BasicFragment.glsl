//#version 410 core

precision highp float;
varying vec2 vTexCoord;
varying vec4 vColor;

uniform sampler2D sDiffMap2;
uniform vec2 cCanvasSize;
uniform vec2 cTextSize;
uniform vec2 cPosition;
uniform float cAspectRatio;
uniform float cWordCount1;     // 第一句歌词字的个数
uniform vec2 cWordPos1[20];  // 第一句歌词每个字的位置信息

vec2 translate (vec2 uv, vec2 xy) {
    return uv + xy;
}

mat2 scale(vec2 scale) {
    return mat2(scale.x, 0.0, 0.0, scale.y);
}

vec2 getScaleUV(vec2 uv, vec2 center, float scaleFactor) {
    vec2 st = uv - center;
    st = scale(vec2(1. / scaleFactor)) * st;
    st = st + center;
    return st;
}

vec2 getPicUv(vec2 uv, vec2 canvas_size, vec2 pic_size, vec2 canvas_scaley_vec, vec2 canvas_scalex_vec, float set_y_position) {
    vec2 scalex_pic = vec2(pic_size.x / pic_size.y, 1.0);
    vec2 scaley_pic = vec2(1.0, pic_size.y / pic_size.x);
    vec2 origin_uv = uv / scaley_pic * canvas_scaley_vec;
    vec2 origin_pic_uv = getScaleUV(origin_uv, vec2(0.5, 0.0), pic_size.x / canvas_size.x);
    origin_pic_uv = translate(origin_pic_uv, vec2(0.0, 0.5));
    vec2 translate_uv = translate(origin_pic_uv, vec2(0.0, -set_y_position * canvas_size.y / pic_size.y ) );
    return translate_uv;
}

void main()
{
    float x = 0.0;
    int wordCount1 = int(cWordCount1);
    if (wordCount1 > 0) {
        x = cWordPos1[wordCount1 - 1].x;
    }
    vec2 scalex_vec = vec2(cAspectRatio, 1.0);
    vec2 scaley_vec = vec2(1.0, cCanvasSize.y / cCanvasSize.x);
    vec2 text_uv = getPicUv(vTexCoord, cCanvasSize, cTextSize, scaley_vec, scalex_vec, 0.5);
    vec4 diffInput = texture2D(sDiffMap2, text_uv);
    gl_FragColor = diffInput * x;
}



