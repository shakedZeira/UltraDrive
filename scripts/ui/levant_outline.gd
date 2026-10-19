class_name LevantOutline
extends RefCounted

## Stylized, hand-authored Levant landmass + inland-water rings for the ISRAEL
## tier of the race-menu circuit map.
##
## Every vertex is a Vector2(LON, LAT) in degrees, in the SAME equirectangular
## frame as WorldMapProjection, so drawing them through that projection keeps
## the vector tier and the world-raster tier in exact agreement about position.
##
## These are deliberately stylized editorial shapes, NOT survey outlines.
## Israel spans only ~1.7 degrees of longitude, so at world scale it is ~7
## pixels wide on a 1440-wide raster -- a raster zoom is physically incapable
## of showing it, which is why the default region is drawn as crisp vectors
## instead of scaling the world texture up. Swap in Natural Earth (PD) GeoJSON
## later without touching the pin/projection layer.

## The Levant land silhouette: Mediterranean coast south to Sinai, Suez, the
## Gulf of Aqaba, then the eastern/northern border back up to Rosh Hanikra.
static func land_ring() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(35.10, 33.09), # Rosh Hanikra
		Vector2(35.07, 32.93), # Acre
		Vector2(34.99, 32.82), # Haifa
		Vector2(34.94, 32.70), # Atlit
		Vector2(34.85, 32.32), # Netanya
		Vector2(34.76, 32.07), # Tel Aviv
		Vector2(34.64, 31.80), # Ashdod
		Vector2(34.45, 31.50), # Gaza
		Vector2(34.25, 31.30), # Rafah
		Vector2(33.80, 31.13), # El Arish
		Vector2(32.30, 31.26), # Port Said
		Vector2(32.55, 29.97), # Suez
		Vector2(34.95, 29.55), # Aqaba / Eilat
		Vector2(35.00, 30.40), # Wadi Araba
		Vector2(35.40, 31.05), # Dead Sea south
		Vector2(35.55, 31.77), # Eastern border
		Vector2(35.55, 32.22), # Jordan river
		Vector2(35.75, 33.00), # Golan
	])

## The Sea of Galilee (drawn as water inside the land polygon).
static func sea_of_galilee_ring() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(35.57, 32.68),
		Vector2(35.61, 32.72),
		Vector2(35.65, 32.79),
		Vector2(35.63, 32.86),
		Vector2(35.58, 32.88),
		Vector2(35.53, 32.79),
	])

## The Dead Sea (elongated north/south, drawn as water inside the land polygon).
static func dead_sea_ring() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(35.40, 31.05), # south tip
		Vector2(35.45, 31.30), # west shore up
		Vector2(35.50, 31.55),
		Vector2(35.52, 31.75),
		Vector2(35.55, 31.77), # north tip
		Vector2(35.58, 31.70), # east shore down
		Vector2(35.54, 31.45),
		Vector2(35.49, 31.20),
		Vector2(35.44, 31.07),
	])

## Land polygons to fill (currently just the one landmass silhouette).
static func rings() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	out.append(land_ring())
	return out

## Water polygons to paint in the ocean tint on top of the land fill.
static func water_rings() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	out.append(sea_of_galilee_ring())
	out.append(dead_sea_ring())
	return out
