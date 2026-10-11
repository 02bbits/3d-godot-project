shader_type canvas_item;

// Menu backdrop: a slowly scrolling blueprint sheet. Minor/major grid lines,
// twinkling construction marks on major crossings, outlined mascot robots
// drifting upward and a soft scan sweep. Units are grid cells, so the look
// scales with the screen instead of the pixel count.

uniform vec4 base_top : source_color = vec4(0.118, 0.161, 0.247, 1.0);
uniform vec4 base_bottom : source_color = vec4(0.086, 0.106, 0.157, 1.0);
uniform vec4 line_color : source_color = vec4(0.302, 0.635, 0.996, 1.0);
uniform vec4 accent_color : source_color = vec4(1.0, 0.788, 0.2, 1.0);
uniform float cells = 26.0; // minor cells per screen height
uniform float major_every = 5.0;
uniform vec2 scroll = vec2(0.30, 0.18); // cells per second
uniform float minor_alpha = 0.07;
uniform float major_alpha = 0.17;
uniform float robot_alpha = 0.22;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// anti-aliased grid lines `width` pixels wide every `period` cells
float grid(vec2 p, float period, float width) {
	vec2 q = p / period;
	vec2 d = abs(fract(q - 0.5) - 0.5) / fwidth(q);
	return 1.0 - clamp(min(d.x, d.y) - width * 0.5 + 0.5, 0.0, 1.0);
}

float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// outline of the menu mascot (rounded square, two eyes), `size` cells wide
float robot_outline(vec2 p, float size, float px) {
	float body = abs(sd_round_box(p, vec2(size * 0.5), size * 0.16));
	vec2 eye = vec2(size * 0.2, -size * 0.12);
	float eyes = min(length(p - eye), length(p - vec2(-eye.x, eye.y))) - size * 0.075;
	float d = min(body, abs(eyes));
	return 1.0 - smoothstep(px * 0.75, px * 1.75, d);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 screen = UV * vec2(aspect, 1.0) * cells; // in cells, unscrolled
	vec2 p = screen + TIME * scroll;
	float px = fwidth(screen.y); // one pixel in cells

	vec3 col = mix(base_top.rgb, base_bottom.rgb, UV.y);
	// soft blue glow behind the menu content
	col += line_color.rgb * 0.07 * (1.0 - smoothstep(0.0, 0.75, distance(UV, vec2(0.5, 0.45))));

	col = mix(col, line_color.rgb, grid(p, 1.0, 1.0) * minor_alpha);
	col = mix(col, line_color.rgb, grid(p, major_every, 2.0) * major_alpha);

	// twinkling "+" marks on some major crossings
	vec2 cell = floor(p / major_every + 0.5);
	vec2 to_cross = p - cell * major_every;
	float h = hash(cell);
	if (h > 0.82) {
		float arm = 0.55;
		float plus = max(
			(1.0 - smoothstep(px, px * 2.0, abs(to_cross.y))) * step(abs(to_cross.x), arm),
			(1.0 - smoothstep(px, px * 2.0, abs(to_cross.x))) * step(abs(to_cross.y), arm));
		float twinkle = 0.5 + 0.5 * sin(TIME * 1.7 + h * 40.0);
		col = mix(col, accent_color.rgb, plus * twinkle * 0.55);
	}

	// outlined robots drifting upward, each wrapping around the screen
	float height = cells;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float size = 2.2 + 2.6 * hash(vec2(fi, 3.1));
		float speed = 0.35 + 0.45 * hash(vec2(fi, 7.7));
		float x = (0.06 + 0.88 * hash(vec2(fi, 1.3))) * aspect * cells;
		float span = height + size * 2.0;
		float y = height + size - mod(hash(vec2(fi, 5.9)) * span + TIME * speed, span);
		vec2 local = screen - vec2(x + sin(TIME * 0.4 + fi) * 0.8, y);
		float a = sin(TIME * 0.3 + fi * 1.7) * 0.25;
		local = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * local;
		col = mix(col, line_color.rgb, robot_outline(local, size, px) * robot_alpha);
	}

	// slow scan sweep
	float sweep = 1.0 - smoothstep(0.0, 0.06, abs(UV.y - fract(TIME * 0.045)));
	col += line_color.rgb * sweep * 0.035;

	// vignette
	float vignette = smoothstep(1.15, 0.35, length((UV - 0.5) * vec2(1.0, 1.25)));
	col *= mix(0.7, 1.0, vignette);

	COLOR = vec4(col, 1.0);
}
