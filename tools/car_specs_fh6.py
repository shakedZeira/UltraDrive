"""Parameter specs for 12 Forza Horizon 6 cars, for tools/car_builder.py.

Each entry is a keyword-argument dict for CarSpec (tools/car_builder.py).
Every dict carries a "comment" giving the roster line + a proportion
rationale; comments are ignored by CarSpec.__init__ (extra kwargs are
dropped).

KEY/NAME RULE: the dict key equals its "name" value and is the roster Image
filename stem (docs/research/fh6_gt7_car_lists.md) with the "FH6_" prefix and
".png" removed, URL-decoded, plus "_<year>" when the stem does not already
end in that year. Example: FH6_Nissan_GT-R_R35.png + 2017 -> Nissan_GT-R_R35_2017.

Semantics (from car_builder.py CarSpec + _sections):
  - nose = +Y; real dims in metres, verified against factory/press data.
  - "track" is centre-to-centre across the axle (mean of F/R treads).
  - cabin_f / cabin_r are DIRECT Y coordinates of the roof front/rear edge and
    MUST satisfy:  -wheelbase/2 < cabin_r < cabin_f < length/2 - hood_len.
    cabin_r is therefore NEGATIVE (behind centre), cabin_f positive.
  - body_style: coupe | sedan | hatch | suv (swaps a loft section or two).
  - body_color is RGBA; metallic/roughness/clearcoat left to defaults.

Roster references = docs/research/fh6_gt7_car_lists.md, FH6 section
(lines 23-1150). All 12 targets are roster entries; where the requested car
has no exact FH6 entry (Golf R32, 1990 NSX-R, 1967 Mustang, 1974 Countach)
the comment names the nearest pick. Whole project pollutes nothing at import
(no bpy at top level) -> spec_for() lazy-imports.
"""

SPECS = {
	# --- BMW ---
	"BMW_M3_1988": {
		"name": "BMW_M3_1988",
		"comment": "roster L159: '1988 BMW M3' (exact; nearest E30 to the "
			"requested 1990 M3). E30 dims verified L4345 W1680 H1365 wb2565, "
			"tracks 1412/1424 -> 1.42; boxy upright greenhouse -> low rake "
			"0.28 and roof_drop 0.03, flat waist 0.60, 205/55R15 -> r 0.30.",
		"body_style": "coupe",
		"length": 4.345,
		"width": 1.68,
		"height": 1.365,
		"wheelbase": 2.565,
		"wheel_radius": 0.30,
		"track": 1.42,
		"overhang_f": 0.24,
		"hood_len": 0.95,
		"cabin_f": 0.30,
		"cabin_r": -0.85,
		"roof_drop": 0.03,
		"roof_rake": 0.28,
		"waist": 0.60,
		"sill": 0.19,
		"tumble": 0.84,
		"haunch": 1.02,
		"tail_short": 0.05,
		"body_color": (0.93, 0.94, 0.95, 1.0),  # Alpine White
		"spokes": 5,
	},

	# --- Chevrolet ---
	"Chevrolet_Corvette_Stingray_427_1967": {
		"name": "Chevrolet_Corvette_Stingray_427_1967",
		"comment": "roster L223: '1967 Chevrolet Corvette Stingray 427' "
			"(exact, exact year). C2 coupe dims L4453 W1768 H1265 wb2489, "
			"treads 1463/1481 -> 1.47; long-hood/short-deck Sting Ray -> "
			"hood_len 1.10, short cabin_r -0.60 and rake 0.45, F70-15 -> r 0.33.",
		"body_style": "coupe",
		"length": 4.45,
		"width": 1.77,
		"height": 1.265,
		"wheelbase": 2.49,
		"wheel_radius": 0.33,
		"track": 1.47,
		"overhang_f": 0.24,
		"hood_len": 1.10,
		"cabin_f": 0.05,
		"cabin_r": -0.60,
		"roof_drop": 0.04,
		"roof_rake": 0.45,
		"waist": 0.56,
		"sill": 0.16,
		"tumble": 0.74,
		"haunch": 1.05,
		"tail_short": 0.04,
		"body_color": (0.66, 0.04, 0.04, 1.0),  # Rally Red
		"spokes": 5,
	},

	# --- Ford ---
	"Ford_Mustang_GT_2+2_Fastback_1968": {
		"name": "Ford_Mustang_GT_2+2_Fastback_1968",
		"comment": "roster L353: '1968 Ford Mustang GT 2+2 Fastback' (exact; "
			"key decodes the roster's %2B to '+'). 1968 fastback dims "
			"L4663 W1801 H1310 wb2743, treads 1486 -> 1.49; long-bonnet "
			"fastback roofline -> hood_len 1.15, cabin_r -0.85, rake 0.45; "
			"F70-15 -> r 0.33.",
		"body_style": "coupe",
		"length": 4.66,
		"width": 1.80,
		"height": 1.31,
		"wheelbase": 2.74,
		"wheel_radius": 0.33,
		"track": 1.49,
		"overhang_f": 0.24,
		"hood_len": 1.15,
		"cabin_f": 0.10,
		"cabin_r": -0.85,
		"roof_drop": 0.05,
		"roof_rake": 0.45,
		"waist": 0.57,
		"sill": 0.18,
		"tumble": 0.78,
		"haunch": 1.03,
		"tail_short": 0.05,
		"body_color": (0.06, 0.17, 0.10, 1.0),  # Highland Green
		"spokes": 5,
	},

	# --- Honda ---
	"Honda_NSX-R_1992": {
		"name": "Honda_NSX-R_1992",
		"comment": "roster L477: '1992 Honda NSX-R' (exact; nearest to the "
			"requested 1990 NSX-R). NA1 Type R dims L4430 W1810 H1170 "
			"wb2530, treads 1510/1530 -> 1.52; mid-engine cab-forward shape "
			"-> short hood_len 0.72 and cabin_r -0.55, steep rake 0.52; "
			"15/16in run-flats -> r 0.30.",
		"body_style": "coupe",
		"length": 4.43,
		"width": 1.81,
		"height": 1.17,
		"wheelbase": 2.53,
		"wheel_radius": 0.30,
		"track": 1.52,
		"overhang_f": 0.24,
		"hood_len": 0.72,
		"cabin_f": 0.45,
		"cabin_r": -0.55,
		"roof_drop": 0.04,
		"roof_rake": 0.52,
		"waist": 0.55,
		"sill": 0.15,
		"tumble": 0.74,
		"haunch": 1.03,
		"tail_short": 0.05,
		"body_color": (0.94, 0.94, 0.91, 1.0),  # Championship White
		"spokes": 5,
	},

	# --- Lamborghini ---
	"Lamborghini_Countach_LP5000_QV_1988": {
		"name": "Lamborghini_Countach_LP5000_QV_1988",
		"comment": "roster L563: '1988 Lamborghini Countach LP5000 QV' "
			"(exact; only Countach in the FH6 roster, so it stands in for the "
			"requested 1974 Countach). QV dims L4140 W2000 H1070 wb2500, "
			"treads 1536/1606 -> 1.57; extreme wedge -> tiny forward cabin "
			"(cabin_f 0.35, cabin_r -0.35), rake 0.50, sill 0.14, 345/35R15 "
			"-> r 0.31.",
		"body_style": "coupe",
		"length": 4.14,
		"width": 2.00,
		"height": 1.07,
		"wheelbase": 2.50,
		"wheel_radius": 0.31,
		"track": 1.57,
		"overhang_f": 0.24,
		"hood_len": 0.85,
		"cabin_f": 0.35,
		"cabin_r": -0.35,
		"roof_drop": 0.03,
		"roof_rake": 0.50,
		"waist": 0.52,
		"sill": 0.14,
		"tumble": 0.72,
		"haunch": 1.04,
		"tail_short": 0.06,
		"body_color": (0.90, 0.90, 0.88, 1.0),  # Bianco White
		"spokes": 5,
	},

	# --- Mazda ---
	"Mazda_RX-7_Type_R_1992": {
		"name": "Mazda_RX-7_Type_R_1992",
		"comment": "roster L655: '1992 Mazda RX-7 Type R' (exact; only FD in "
			"the roster). FD3S dims L4295 W1760 H1230 wb2425, treads "
			"1460/1460; low curvaceous coupe -> rake 0.50, roof_drop 0.06, "
			"slim sill 0.16; R16 tyres -> r 0.32.",
		"body_style": "coupe",
		"length": 4.29,
		"width": 1.76,
		"height": 1.23,
		"wheelbase": 2.425,
		"wheel_radius": 0.32,
		"track": 1.46,
		"overhang_f": 0.24,
		"hood_len": 0.95,
		"cabin_f": 0.20,
		"cabin_r": -0.60,
		"roof_drop": 0.06,
		"roof_rake": 0.50,
		"waist": 0.57,
		"sill": 0.16,
		"tumble": 0.76,
		"haunch": 1.04,
		"tail_short": 0.06,
		"body_color": (0.03, 0.20, 0.12, 1.0),  # Montego Green Mica
		"spokes": 5,
	},

	# --- Mitsubishi ---
	"Mitsubishi_Lancer_Evolution_VI_GSR_TM_Edition_2001": {
		"name": "Mitsubishi_Lancer_Evolution_VI_GSR_TM_Edition_2001",
		"comment": "roster L750: '2001 Mitsubishi Lancer Evolution VI GSR TM "
			"Edition' (exact, exact year). CP9A dims L4350 W1770 H1415 wb2510, "
			"treads 1510/1505 -> 1.51; rally arches and boxy saloon -> haunch "
			"1.06, tumble 0.84, upright rake 0.35; 225/45R17 -> r 0.32.",
		"body_style": "sedan",
		"length": 4.35,
		"width": 1.77,
		"height": 1.41,
		"wheelbase": 2.51,
		"wheel_radius": 0.32,
		"track": 1.51,
		"overhang_f": 0.24,
		"hood_len": 0.95,
		"cabin_f": 0.37,
		"cabin_r": -0.85,
		"roof_drop": 0.03,
		"roof_rake": 0.35,
		"waist": 0.58,
		"sill": 0.19,
		"tumble": 0.84,
		"haunch": 1.06,
		"tail_short": 0.05,
		"body_color": (0.66, 0.05, 0.06, 1.0),  # Tommi Makinen Red
		"spokes": 5,
	},

	# --- Nissan ---
	"Nissan_GT-R_R35_2017": {
		"name": "Nissan_GT-R_R35_2017",
		"comment": "roster L790: '2017 Nissan GT-R (R35)' (exact; key = "
			"FH6_Nissan_GT-R_R35 stem + year, the given example). 2017 press "
			"kit dims L4710 W1895 H1370 wb2780, tracks 1590/1600 -> 1.60; "
			"long bonnet and fast roofline -> hood_len 1.00, rake 0.42, "
			"haunch 1.05; 255/40R20 -> r 0.355.",
		"body_style": "coupe",
		"length": 4.71,
		"width": 1.895,
		"height": 1.37,
		"wheelbase": 2.78,
		"wheel_radius": 0.355,
		"track": 1.60,
		"overhang_f": 0.24,
		"hood_len": 1.00,
		"cabin_f": 0.35,
		"cabin_r": -0.75,
		"roof_drop": 0.05,
		"roof_rake": 0.42,
		"waist": 0.60,
		"sill": 0.16,
		"tumble": 0.78,
		"haunch": 1.05,
		"tail_short": 0.05,
		"body_color": (0.07, 0.24, 0.55, 1.0),  # Bayside Blue
		"spokes": 5,
		# GT-R style kit (car_builder opt-in flags) — the R35 signature cues:
		# swept headlight blades, big lower intake + slim upper slot, twin hood
		# extractors, fender vent, shoulder crease, fastback rear screen, high
		# decklid, rear wing, quad round taillights, quad exhaust, splitter.
		"deck_raise": 0.10,
		"headlight_style": "swept",
		"grille_style": "gtr",
		"quad_taillights": True,
		"rear_wing": True,
		"quad_exhaust": True,
		"hood_vents": True,
		"side_vents": True,
		"front_splitter": True,
		"shoulder_line": True,
		"fastback_glass": True,
	},

	# --- Porsche ---
	"Porsche_911_Carrera_RS_1973": {
		"name": "Porsche_911_Carrera_RS_1973",
		"comment": "roster L865: '1973 Porsche 911 Carrera RS' (exact). "
			"Carrera RS 2.7 Touring dims L4147 W1652 H1320 wb2271, treads "
			"1372/1394 -> 1.38; rear-engine fastback -> long rear deck "
			"(tail_short 0.04), upright cabin (rake 0.40), wide haunch 1.06; "
			"215/60R15 -> r 0.32, period Signal Orange.",
		"body_style": "coupe",
		"length": 4.15,
		"width": 1.65,
		"height": 1.32,
		"wheelbase": 2.27,
		"wheel_radius": 0.32,
		"track": 1.38,
		"overhang_f": 0.24,
		"hood_len": 0.85,
		"cabin_f": 0.20,
		"cabin_r": -0.80,
		"roof_drop": 0.06,
		"roof_rake": 0.40,
		"waist": 0.56,
		"sill": 0.17,
		"tumble": 0.75,
		"haunch": 1.06,
		"tail_short": 0.04,
		"body_color": (0.86, 0.33, 0.03, 1.0),  # Signal Orange
		"spokes": 5,
	},

	# --- Subaru ---
	"Subaru_Impreza_22B_STi-Version_1998": {
		"name": "Subaru_Impreza_22B_STi-Version_1998",
		"comment": "roster L986: '1998 Subaru Impreza 22B-STi Version' "
			"(exact; key mirrors the roster image stem "
			"FH6_Subaru_Impreza_22B_STi-Version, which hyphenates "
			"differently from the display name). STI dims L4365 W1770 H1390 "
			"wb2520, treads 1480/1500 -> 1.49; widebody rally saloon -> "
			"haunch 1.07, tumble 0.84; 235/40R17 (620mm dia) -> r 0.31.",
		"body_style": "sedan",
		"length": 4.365,
		"width": 1.77,
		"height": 1.39,
		"wheelbase": 2.52,
		"wheel_radius": 0.31,
		"track": 1.49,
		"overhang_f": 0.24,
		"hood_len": 0.95,
		"cabin_f": 0.37,
		"cabin_r": -0.85,
		"roof_drop": 0.03,
		"roof_rake": 0.35,
		"waist": 0.57,
		"sill": 0.19,
		"tumble": 0.84,
		"haunch": 1.07,
		"tail_short": 0.06,
		"body_color": (0.09, 0.25, 0.60, 1.0),  # WR Blue Mica
		"spokes": 5,
	},

	# --- Toyota ---
	"Toyota_Supra_RZ_1998": {
		"name": "Toyota_Supra_RZ_1998",
		"comment": "roster L1022: '1998 Toyota Supra RZ' (exact, exact year). "
			"JZA80 dims (Toyota official) L4520 W1810 H1275 wb2550, treads "
			"1520/1525 -> 1.52; long nose and tall rear haunch -> hood_len "
			"1.05, haunch 1.05, rake 0.48; 255/40R17 -> r 0.32.",
		"body_style": "coupe",
		"length": 4.52,
		"width": 1.81,
		"height": 1.275,
		"wheelbase": 2.55,
		"wheel_radius": 0.32,
		"track": 1.52,
		"overhang_f": 0.24,
		"hood_len": 1.05,
		"cabin_f": 0.20,
		"cabin_r": -0.70,
		"roof_drop": 0.05,
		"roof_rake": 0.48,
		"waist": 0.58,
		"sill": 0.17,
		"tumble": 0.76,
		"haunch": 1.05,
		"tail_short": 0.05,
		"body_color": (0.62, 0.05, 0.06, 1.0),  # Renaissance Red
		"spokes": 5,
	},

	# --- Volkswagen ---
	"Volkswagen_Golf_R_2010": {
		"name": "Volkswagen_Golf_R_2010",
		"comment": "roster L1070: '2010 Volkswagen Golf R' (nearest entry - "
			"the FH6 roster has no R32; 2010 Mk6 Golf R matches the request's "
			"era and badge). VW official Mk6 3dr dims L4212 W1779 H1461 "
			"wb2578, tracks 1532/1515 -> 1.52; short hot-hatch body -> "
			"hood_len 0.75, cabin_r -1.00, tail_short 0.03; 225/40R18 -> "
			"r 0.31, 10-spoke wheels.",
		"body_style": "hatch",
		"length": 4.21,
		"width": 1.78,
		"height": 1.46,
		"wheelbase": 2.58,
		"wheel_radius": 0.31,
		"track": 1.52,
		"overhang_f": 0.24,
		"hood_len": 0.75,
		"cabin_f": 0.50,
		"cabin_r": -1.00,
		"roof_drop": 0.03,
		"roof_rake": 0.36,
		"waist": 0.58,
		"sill": 0.18,
		"tumble": 0.82,
		"haunch": 1.03,
		"tail_short": 0.03,
		"body_color": (0.04, 0.04, 0.05, 1.0),  # Deep Black Pearl
		"spokes": 10,
	},
}


def spec_for(name: str):
	"""Return a CarSpec built from SPECS[name].

	car_builder imports bpy at module level, so it is imported lazily inside
	this function - importing this spec module must never touch Blender.
	"""
	from car_builder import CarSpec
	return CarSpec(**SPECS[name])
