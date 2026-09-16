extends Checkpoint

## Test double: lets tests control which bodies the checkpoint "sees"
## without needing real physics overlaps.

var overlaps: Array = []

func _overlapping_bodies() -> Array:
	return overlaps