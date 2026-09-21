class_name WetSurface
extends RefCounted

## Weather VFX (S12): wet-road feel driven by the SAME number VehiclePhysics
## already reads -- WeatherManager.get_road_grip_factor(). Pure static helpers
## (grip -> intensity -> overlay alpha/tint) so the layer is deterministic and
## headless-safe; the overlay itself is a full-rect ColorRect that only appears
## when the wet tint rule fires (night or storm).

## Grip values: 1.0 dry road; 0.45 is SNOW (the wettest/slickest the table
## ships). Everything at or below that reads fully wet, everything at 1.0 dry.
const GRIP_DRY := 1.0
const GRIP_MAX_WET := 0.45

## Slick asphalt tint at full wetness.
const WET_TINT := Color(0.14, 0.15, 0.17, 1.0)
## Max overlay opacity at the wettest grip (snow/storm night).
const OVERLAY_ALPHA_MAX := 0.35
## Not applied through a separate shader rim yet; kept as the explicit target
## so the darker/dimmer rim lands here when a post material is added.
const RIM_DIM := 0.6

## Monotonic map from road grip factor to wet-visual intensity: 0 dry, 1 fully
## wet. Lower grip (wetter/slicker) -> higher intensity.
static func wet_intensity(grip: float) -> float:
	if grip >= GRIP_DRY:
		return 0.0
	if grip <= GRIP_MAX_WET:
		return 1.0
	return clampf((GRIP_DRY - grip) / (GRIP_DRY - GRIP_MAX_WET), 0.0, 1.0)

## The tint shows only when there is actually wetness AND it would read at
## night or under storm darkening -- a dry summer day stays clean.
static func tint_active(intensity: float, is_night: bool, is_storm: bool) -> bool:
	return intensity > 0.0 and (is_night or is_storm)

## Overlay opacity is intensity-scaled, gated by the tint rule.
static func overlay_alpha(intensity: float, active: bool) -> float:
	if not active:
		return 0.0
	return OVERLAY_ALPHA_MAX * clampf(intensity, 0.0, 1.0)

## Builds the full-rect wet overlay (input-ignoring). Starts invisible.
static func build_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.name = "WetSurfaceOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color(WET_TINT.r, WET_TINT.g, WET_TINT.b, 0.0)
	overlay.visible = false
	return overlay

## Applies a computed (grip, night, storm) state onto an overlay built by
## build_overlay(). Pure function of the same state the gate asserts.
static func apply_intensity(overlay: ColorRect, intensity: float, is_night: bool, is_storm: bool) -> void:
	var active := tint_active(intensity, is_night, is_storm)
	overlay.visible = active
	overlay.color = Color(WET_TINT.r, WET_TINT.g, WET_TINT.b, overlay_alpha(intensity, active))