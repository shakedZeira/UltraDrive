# scripts/music/music_covers.gd
class_name MusicCovers
extends RefCounted

## Cover art for the now-playing toast. Chain: embedded picture -> sidecar image
## ("<stem>.jpg", folder cover.jpg, set by the scanner as cover_path) ->
## procedurally generated tile. Never empty, never throws. Decoding + resize
## happen here (call from a worker); the main thread only wraps the Image in an
## ImageTexture. Oversized inputs (> 8 MB or > 4096 px a side) are rejected
## BEFORE decoding.

const MAX_BYTES := 8 * 1024 * 1024
const MAX_SIDE := 4096
const OUT_SIDE := 256
const TILE_SIDE := 128

## -> { image: Image, generated: bool, accent: Color }
static func load_cover(track: Dictionary, fallback_name: String = "") -> Dictionary:
	var img: Image = null
	if bool(track.get("has_cover", false)):
		var emb := TagReader.read_cover(String(track.get("path", "")))
		if not emb.is_empty():
			img = decode(emb["data"], String(emb.get("mime", "")))
	if img == null:
		var side := String(track.get("cover_path", ""))
		if not side.is_empty() and FileAccess.file_exists(side):
			var f := FileAccess.open(side, FileAccess.READ)
			if f != null:
				var n := f.get_length()
				if n > 0 and n <= MAX_BYTES:
					img = decode(f.get_buffer(n), "")
				f.close()
	if img != null:
		return {"image": img, "generated": false, "accent": average_color(img)}
	var label := fallback_name if not fallback_name.is_empty() else String(track.get("artist", ""))
	var tile := make_tile(label)
	return {"image": tile, "generated": true, "accent": MusicStation.color_for(label)}

## Decode + downscale to <= OUT_SIDE. null when undecodable / oversized.
static func decode(bytes: PackedByteArray, mime: String) -> Image:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return null
	var m := MusicFormats.normalize_mime(mime, bytes)
	var dims := image_dimensions(bytes, m)
	if dims.x > MAX_SIDE or dims.y > MAX_SIDE:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match m:
		"image/jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"image/png":
			err = img.load_png_from_buffer(bytes)
		"image/webp":
			err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	if img.get_width() > MAX_SIDE or img.get_height() > MAX_SIDE:
		return null
	var longest := maxi(img.get_width(), img.get_height())
	if longest > OUT_SIDE:
		var s := float(OUT_SIDE) / float(longest)
		img.resize(maxi(1, int(round(img.get_width() * s))), maxi(1, int(round(img.get_height() * s))), Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGBA8)
	return img

## Pixel size read from the header (PNG IHDR / JPEG SOF); (0,0) if unknown.
static func image_dimensions(bytes: PackedByteArray, mime: String) -> Vector2i:
	if mime == "image/png" and bytes.size() >= 24:
		return Vector2i(_be32(bytes, 16), _be32(bytes, 20))
	if mime == "image/jpeg":
		var i := 2
		var n := bytes.size()
		while i + 9 < n:
			if bytes[i] != 0xFF:
				i += 1
				continue
			var marker: int = bytes[i + 1]
			if marker == 0xFF:
				i += 1
				continue
			if marker >= 0xC0 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8 and marker != 0xCC:
				var h := (int(bytes[i + 5]) << 8) | int(bytes[i + 6])
				var w := (int(bytes[i + 7]) << 8) | int(bytes[i + 8])
				return Vector2i(w, h)
			if marker == 0xD8 or (marker >= 0xD0 and marker <= 0xD7) or marker == 0x01:
				i += 2
				continue
			var seg := (int(bytes[i + 2]) << 8) | int(bytes[i + 3])
			i += 2 + maxi(seg, 2)
	return Vector2i.ZERO

static func average_color(img: Image) -> Color:
	if img == null or img.is_empty():
		return Color(0.3, 0.3, 0.3)
	var c := img.duplicate() as Image
	if c.is_compressed():
		return Color(0.3, 0.3, 0.3)
	c.resize(1, 1, Image.INTERPOLATE_LANCZOS)
	return c.get_pixel(0, 0)

## Generated tile: diagonal gradient in the name's accent colour.
static func make_tile(label: String) -> Image:
	var base := MusicStation.color_for(label if not label.is_empty() else "UltraDrive")
	var dark := base.darkened(0.55)
	var img := Image.create(TILE_SIDE, TILE_SIDE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIDE):
		for x in range(TILE_SIDE):
			var t := float(x + y) / float(TILE_SIDE * 2 - 2)
			img.set_pixel(x, y, base.lerp(dark, t))
	return img

static func _be32(b: PackedByteArray, at: int) -> int:
	if at + 4 > b.size():
		return 0
	return (int(b[at]) << 24) | (int(b[at + 1]) << 16) | (int(b[at + 2]) << 8) | int(b[at + 3])
