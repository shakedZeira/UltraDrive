class_name WorldMapProjection
extends RefCounted

## Equirectangular (lat/lon) -> screen math for the race-menu circuit map.
##
## The map plane puts longitude on +x and NEGATED latitude on +z, so north ends
## up at the top:
##
##     map_point(lat, lon) -> Vector3(lon, 0.0, -lat)
##     lonlat_of(p)        -> Vector2(p.x, -p.z)        # (lon, lat)
##
## That inversion is the single most likely bug in the whole feature, so it
## lives here and nowhere else, and its own test locks it (north-up, west-left).
## Reusing MapRoads.compute_fit()/world_to_screen()/screen_to_world() -- which
## are a plain contain-fit over a Vector3 x/z plane -- then gives a north-up,
## west-left, letterboxed map for free, with no zoom/pan state machine.
##
## lonlat_to_uv()/uv_to_lonlat() are the exact equirectangular pair that matches
## the CC0 360x180-unit world SVG (1 map unit = 1 degree, y down):
##
##     u = (lon + 180) / 360      v = (90 - lat) / 180
##
## Callers never touch `-lat` directly -- they go through this class, so the
## vector tier (LevantOutline) and the world-raster tier can never disagree
## about where a pin lands.
##
## Dateline: no pin sits near +/-180, so no wrap is handled. A future Pacific
## pin would need the framing box (not just the pin) to wrap.

## Screen inset (px) kept clear of the panel edge when framing a region.
const INSET: float = 24.0

static func lonlat_to_map_point(lat: float, lon: float) -> Vector3:
	return Vector3(lon, 0.0, -lat)

static func lonlat_of(map_point: Vector3) -> Vector2:
	return Vector2(map_point.x, -map_point.z)

static func lonlat_to_uv(lat: float, lon: float) -> Vector2:
	return Vector2((lon + 180.0) / 360.0, (90.0 - lat) / 180.0)

## Returns (lon, lat) -- the same order the pin tables use, NOT (lat, lon).
static func uv_to_lonlat(uv: Vector2) -> Vector2:
	return Vector2(uv.x * 360.0 - 180.0, 90.0 - uv.y * 180.0)

## The four map-space corners of a region framing box, as Vector3 map points.
static func region_corners(region_id: String) -> Array:
	var bounds := TrackRegistry.region_bounds(region_id)
	if bounds.is_empty():
		return []
	var min_lon := float(bounds.get("min_lon", -180.0))
	var min_lat := float(bounds.get("min_lat", -90.0))
	var max_lon := float(bounds.get("max_lon", 180.0))
	var max_lat := float(bounds.get("max_lat", 90.0))
	return [
		lonlat_to_map_point(min_lat, min_lon),
		lonlat_to_map_point(min_lat, max_lon),
		lonlat_to_map_point(max_lat, min_lon),
		lonlat_to_map_point(max_lat, max_lon),
	]

## The equirectangular UV rect (image space 0..1, y down) of a lon/lat framing
## box {min_lon, min_lat, max_lon, max_lat}: the slice of a 360x180 world raster
## that DEPICTS that box (north edge = top). The world-raster backdrop is cropped
## with this and stretched over the fitted content rect -- which is the SAME box
## in screen space -- so the drawn landmasses follow the exact lon/lat -> screen
## map the pins, graticule and vector tier use, for every region.
## Drawing the whole raster over the frame instead (the original bug) shows an
## unzoomed, aspect-squashed globe while the pins project at region-relative
## positions: the continent never zooms and every pin sits off its landmass.
## Empty box -> the whole image (0,0,1,1). Assumes the box lies inside
## +/-180 / +/-90 (no dateline wrap) -- the same assumption region_corners() makes.
static func uv_rect_of_bounds(bounds: Dictionary) -> Rect2:
	if bounds.is_empty():
		return Rect2(0.0, 0.0, 1.0, 1.0)
	var min_lon := float(bounds.get("min_lon", -180.0))
	var min_lat := float(bounds.get("min_lat", -90.0))
	var max_lon := float(bounds.get("max_lon", 180.0))
	var max_lat := float(bounds.get("max_lat", 90.0))
	var top_left := lonlat_to_uv(max_lat, min_lon)
	var bottom_right := lonlat_to_uv(min_lat, max_lon)
	return Rect2(top_left, bottom_right - top_left)

## Contain-fit of a region's corners into draw_size (north-up, centred,
## letterboxed). `fallback_pin` is a pin Dictionary {lat, lon} used as the fit
## anchor when the region has no corners (so an empty/unknown region degrades to
## a sane 1-unit box instead of dividing by zero).
static func build_fit(region_id: String, draw_size: Vector2, fallback_pin: Dictionary) -> Dictionary:
	var corners := region_corners(region_id)
	var fallback := _fallback_point(region_id, fallback_pin)
	return MapRoads.compute_fit(corners, fallback, draw_size, INSET)

static func project_pin(pin: Dictionary, fit: Dictionary) -> Vector2:
	return MapRoads.world_to_screen(
		lonlat_to_map_point(float(pin.get("lat", 0.0)), float(pin.get("lon", 0.0))), fit)

static func lonlat_to_screen(lat: float, lon: float, fit: Dictionary) -> Vector2:
	return MapRoads.world_to_screen(lonlat_to_map_point(lat, lon), fit)

## Inverse of project_pin()/lonlat_to_screen(): a screen position back to
## (lon, lat). Map clicks come back through here, so a future pan/zoom state
## machine is free to reuse it unchanged.
static func screen_to_lonlat(screen_pos: Vector2, fit: Dictionary) -> Vector2:
	return lonlat_of(MapRoads.screen_to_world(screen_pos, fit))

static func _fallback_point(region_id: String, fallback_pin: Dictionary) -> Vector3:
	if fallback_pin.has("lat") and fallback_pin.has("lon"):
		return lonlat_to_map_point(float(fallback_pin["lat"]), float(fallback_pin["lon"]))
	var bounds := TrackRegistry.region_bounds(region_id)
	if bounds.is_empty():
		return Vector3.ZERO
	var lon := (float(bounds.get("min_lon", -180.0)) + float(bounds.get("max_lon", 180.0))) * 0.5
	var lat := (float(bounds.get("min_lat", -90.0)) + float(bounds.get("max_lat", 90.0))) * 0.5
	return lonlat_to_map_point(lat, lon)
