"""Parameter specs for 12 GT7 franchise cars, for tools/car_builder.py.

Each entry is a keyword-argument dict for CarSpec (tools/car_builder.py).
Every dict carries a "comment" describing the GT7 roster source; comments
are ignored by CarSpec.__init__ (extra kwargs are dropped).

Semantics (from car_builder.py CarSpec + _sections):
  - nose = +Y; real dims in metres.
  - "track" is centre-to-centre across the axle.
  - cabin_f / cabin_r are DIRECT Y coordinates of the roof front/rear edge and
    MUST satisfy:  -wheelbase/2 < cabin_r < cabin_f < length/2 - hood_len.
    cabin_r is therefore NEGATIVE (behind centre), cabin_f positive.
  - body_style: coupe | sedan | hatch | suv (swaps a loft section or two).
  - body_color is RGBA; metallic/roughness/clearcoat left to defaults.

Roster references = docs/research/fh6_gt7_car_lists.md, GT7 section
(lines 1151-2160). All 12 targets are "closest roster entry" picks; where a
name is not byte-exact in the roster the comment says so. Whole project
pollutes nothing at import (no bpy at top level) -> spec_for() lazy-imports.
"""

SPECS = {
	# --- Nissan 1768 ---
	"Nissan_GT-R_NISMO_2017": {
		"name": "Nissan GT-R NISMO '17",
		"comment": "roster line ~1804: 'Nissan GT-R NISMO '17' (exact). "
			"Dims per R35 GT-R NISMO; tyres 285/35ZR20 -> wheel_radius 0.355; "
			"track est. 1.60.",
		"body_style": "coupe",
		"length": 4.70,
		"width": 1.90,
		"height": 1.37,
		"wheelbase": 2.78,
		"wheel_radius": 0.355,
		"track": 1.60,
		"overhang_f": 0.24,
		"hood_len": 1.05,
		"cabin_f": 0.25,
		"cabin_r": -0.70,
		"roof_drop": 0.05,
		"roof_rake": 0.45,
		"waist": 0.60,
		"sill": 0.16,
		"tumble": 0.78,
		"haunch": 1.05,
		"tail_short": 0.04,
		"body_color": (0.07, 0.24, 0.55, 1.0),  # Bayside Blue
		"spokes": 5,
	},

	"Nissan_Skyline_GT-R_V-spec_II_Nur_2002": {  # key kept ASCII (console-safe); name keeps "Nür"
		"name": "Nissan Skyline GT-R V-spec II Nür 2002",
		"comment": "roster line ~1807: 'V.spec II Nür (R34) '02'. Same "
			"generation + trim as 2002 (roster label later model yr); tyres "
			"245/40ZR18 -> wheel_radius 0.33; track est. 1.48.",
		"body_style": "coupe",
		"length": 4.60,
		"width": 1.78,
		"height": 1.36,
		"wheelbase": 2.665,
		"wheel_radius": 0.33,
		"track": 1.48,
		"overhang_f": 0.24,
		"hood_len": 1.00,
		"cabin_f": 0.30,
		"cabin_r": -0.65,
		"roof_drop": 0.04,
		"roof_rake": 0.38,
		"waist": 0.58,
		"sill": 0.18,
		"tumble": 0.80,
		"haunch": 1.03,
		"tail_short": 0.05,
		"body_color": (0.38, 0.44, 0.34, 1.0),  # Millennium Jade
		"spokes": 5,
	},

	# --- Honda 1529 ---
	"Honda_NSX_Type_R_2002": {
		"name": "Honda NSX Type R 2002",
		"comment": "roster line ~1551: 'NSX Type R '02' (exact, roster "
			"spelling). Tyre 245/40R17 rear -> wheel_radius ~0.31; track est. "
			"1.49.",
		"body_style": "coupe",
		"length": 4.43,
		"width": 1.81,
		"height": 1.17,
		"wheelbase": 2.37,
		"wheel_radius": 0.31,
		"track": 1.49,
		"overhang_f": 0.24,
		"hood_len": 0.80,
		"cabin_f": 0.40,
		"cabin_r": -0.50,
		"roof_drop": 0.04,
		"roof_rake": 0.52,
		"waist": 0.55,
		"sill": 0.15,
		"tumble": 0.74,
		"haunch": 1.03,
		"tail_short": 0.04,
		"body_color": (0.64, 0.05, 0.05, 1.0),  # Imola Red
		"spokes": 5,
	},

	"Honda_Civic_Type_R_Limited_Edition_2020": {
		"name": "Honda Civic Type R Limited Edition 2020",
		"comment": "roster line ~1558: 'Civic Type R (FK8) '20'. FK8 2020 is "
			"the Limited Edition (Championship White), same gen/body as FK8; "
			"tyre 245/30ZR20 -> wheel_radius 0.33; track est. 1.59.",
		"body_style": "hatch",
		"length": 4.56,
		"width": 1.88,
		"height": 1.43,
		"wheelbase": 2.70,
		"wheel_radius": 0.33,
		"track": 1.59,
		"overhang_f": 0.24,
		"hood_len": 0.82,
		"cabin_f": 0.51,
		"cabin_r": -1.05,
		"roof_drop": 0.03,
		"roof_rake": 0.40,
		"waist": 0.58,
		"sill": 0.17,
		"tumble": 0.82,
		"haunch": 1.03,
		"tail_short": 0.02,
		"body_color": (0.94, 0.94, 0.91, 1.0),  # Championship White
		"spokes": 5,
	},

	# --- Mazda 1669 ---
	"Mazda_RX-7_Spirit_R_Type_A_2002": {
		"name": "Mazda RX-7 Spirit R Type A 2002",
		"comment": "roster line ~1684: 'RX-7 Spirit R Type A (FD) '02'. Tyre "
			"235/45R17 -> wheel_radius 0.32; track est. 1.46.",
		"body_style": "coupe",
		"length": 4.30,
		"width": 1.76,
		"height": 1.23,
		"wheelbase": 2.43,
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

	# --- Mitsubishi 1742 ---
	"Mitsubishi_GTO_Twin_Turbo_1991": {
		"name": "Mitsubishi GTO Twin Turbo 1991",
		"comment": "roster line ~1751: 'GTO Twin Turbo '91' (exact). Dims per "
			"Wikipedia (L4600 W1840 H1285 wb2470); gen-1 TT tyre 245/45R17 -> "
			"wheel_radius 0.325; track est. 1.51.",
		"body_style": "coupe",
		"length": 4.60,
		"width": 1.84,
		"height": 1.285,
		"wheelbase": 2.47,
		"wheel_radius": 0.325,
		"track": 1.51,
		"overhang_f": 0.24,
		"hood_len": 1.00,
		"cabin_f": 0.30,
		"cabin_r": -0.75,
		"roof_drop": 0.05,
		"roof_rake": 0.42,
		"waist": 0.58,
		"sill": 0.17,
		"tumble": 0.80,
		"haunch": 1.04,
		"tail_short": 0.04,
		"body_color": (0.34, 0.05, 0.08, 1.0),  # Morocco Red
		"spokes": 5,
	},

	# --- Subaru 1956 ---
	"Subaru_Impreza_Rally_Car_1998": {
		"name": "Subaru Impreza Rally Car 1998",
		"comment": "roster line ~1966: 'Impreza Rally Car '98' (Gr.B rally "
			"identity match). Sedan silhouette per GC8; track est. 1.55.",
		"body_style": "sedan",
		"length": 4.34,
		"width": 1.77,
		"height": 1.40,
		"wheelbase": 2.52,
		"wheel_radius": 0.34,
		"track": 1.55,
		"overhang_f": 0.24,
		"hood_len": 0.95,
		"cabin_f": 0.37,
		"cabin_r": -0.85,
		"roof_drop": 0.03,
		"roof_rake": 0.35,
		"waist": 0.57,
		"sill": 0.20,
		"tumble": 0.84,
		"haunch": 1.06,
		"tail_short": 0.06,
		"body_color": (0.09, 0.25, 0.60, 1.0),  # WRC Blue
		"spokes": 5,
	},

	# --- Suzuki 1986 ---
	"Suzuki_Jimny_Sierra_JC_2018": {
		"name": "Suzuki Jimny Sierra JC 2018",
		"comment": "roster line ~1989: 'Jimny Sierra JC '18' (only Suzuki "
			"Suv in roster; no Vitara). Dims verified: L3645 W1645 H1725 "
			"wb2250, tracks 1395/1405 -> 1.40; tyre 205/70R15 -> wheel_radius "
			"0.33.",
		"body_style": "suv",
		"length": 3.645,
		"width": 1.645,
		"height": 1.725,
		"wheelbase": 2.25,
		"wheel_radius": 0.33,
		"track": 1.40,
		"overhang_f": 0.24,
		"hood_len": 0.70,
		"cabin_f": 0.55,
		"cabin_r": -0.85,
		"roof_drop": 0.02,
		"roof_rake": 0.30,
		"waist": 0.62,
		"sill": 0.26,
		"tumble": 0.88,
		"haunch": 1.00,
		"tail_short": 0.03,
		"body_color": (0.78, 0.82, 0.20, 1.0),  # Kinetic Yellow
		"spokes": 5,
	},

	# --- Porsche 1863 ---
	"Porsche_911_GT3_2009": {
		"name": "Porsche 911 GT3 2009",
		"comment": "roster line ~1876: '911 GT3 (997) '09'. Same 911 "
			"generation as the 2011 Carrera GTS, so dims transfer there is "
			"valid; chosen over the 904 (different car entirely). Verified "
			"dims (stuttcars): L4460 W1808 H1280 wb2355, tracks 1497/1524 -> "
			"1.51; rear tyre 305/30R19 -> wheel_radius 0.33.",
		"body_style": "coupe",
		"length": 4.46,
		"width": 1.808,
		"height": 1.28,
		"wheelbase": 2.355,
		"wheel_radius": 0.33,
		"track": 1.51,
		"overhang_f": 0.24,
		"hood_len": 0.95,
		"cabin_f": 0.33,
		"cabin_r": -0.80,
		"roof_drop": 0.05,
		"roof_rake": 0.42,
		"waist": 0.57,
		"sill": 0.17,
		"tumble": 0.78,
		"haunch": 1.04,
		"tail_short": 0.03,
		"body_color": (0.64, 0.66, 0.68, 1.0),  # GT Silver
		"spokes": 5,
	},

	# --- Toyota 2008 ---
	"Toyota_Supra_RZ_1997": {
		"name": "Toyota Supra RZ 1997",
		"comment": "roster line ~2038: 'Supra RZ '97' (exact). Tyre "
			"235/40R17 -> wheel_radius 0.32; track est. 1.50.",
		"body_style": "coupe",
		"length": 4.51,
		"width": 1.77,
		"height": 1.26,
		"wheelbase": 2.55,
		"wheel_radius": 0.32,
		"track": 1.50,
		"overhang_f": 0.24,
		"hood_len": 1.05,
		"cabin_f": 0.20,
		"cabin_r": -0.65,
		"roof_drop": 0.05,
		"roof_rake": 0.48,
		"waist": 0.58,
		"sill": 0.17,
		"tumble": 0.76,
		"haunch": 1.04,
		"tail_short": 0.05,
		"body_color": (0.10, 0.13, 0.36, 1.0),  # Royal Sapphire
		"spokes": 5,
	},

	"Toyota_GR_Yaris_1st_Edition_RZ_High_Performance_2020": {
		"name": "Toyota GR Yaris 1st Edition RZ High Performance 2020",
		"comment": "wiki-only entry (~line 2136: GR Yaris 1st Edition RZ "
			"'High Performance', 2020; not in the main table). Dims from "
			"Toyota official: L3995 W1805 H1455 wb2560, tread 1535/1565 -> "
			"track 1.55; tyre 225/40ZR18 -> wheel_radius 0.319.",
		"body_style": "hatch",
		"length": 3.995,
		"width": 1.805,
		"height": 1.455,
		"wheelbase": 2.560,
		"wheel_radius": 0.319,
		"track": 1.55,
		"overhang_f": 0.24,
		"hood_len": 0.75,
		"cabin_f": 0.40,
		"cabin_r": -1.05,
		"roof_drop": 0.04,
		"roof_rake": 0.38,
		"waist": 0.58,
		"sill": 0.18,
		"tumble": 0.82,
		"haunch": 1.03,
		"tail_short": 0.03,
		"body_color": (0.90, 0.90, 0.91, 1.0),  # Platinum Pearl White
		"spokes": 5,
	},

	# --- Ferrari 1421 ---
	"Ferrari_F40_1992": {
		"name": "Ferrari F40 1992",
		"comment": "roster line ~1436: 'F40 '92' (only F40 in roster; 5-yr "
			"label gap, same car). Rear tyre 335/30R17 -> wheel_radius 0.31; "
			"track est. 1.60.",
		"body_style": "coupe",
		"length": 4.36,
		"width": 1.97,
		"height": 1.13,
		"wheelbase": 2.41,
		"wheel_radius": 0.31,
		"track": 1.60,
		"overhang_f": 0.24,
		"hood_len": 1.00,
		"cabin_f": 0.25,
		"cabin_r": -0.60,
		"roof_drop": 0.04,
		"roof_rake": 0.55,
		"waist": 0.56,
		"sill": 0.14,
		"tumble": 0.72,
		"haunch": 1.06,
		"tail_short": 0.03,
		"body_color": (0.75, 0.04, 0.04, 1.0),  # Rosso Corsa
		"spokes": 5,
	},
}


def spec_for(name: str):
	"""Return a CarSpec built from SPECS[name].

	car_builder imports bpy at module level, so it is imported lazily inside
	this function - importing this spec module must never touch Blender.
	"""
	from car_builder import CarSpec
	return CarSpec(**SPECS[name])