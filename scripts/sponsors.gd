class_name Sponsors
extends RefCounted
## The (made-up) sponsors on the cars and round the tracks: the brand list
## (data/sponsors.json), where each one's art sits in the textures that
## tools/make_sponsors.py draws, and which brands back which team.

const LOGO_CELL := Vector2(512, 128)
const LOGO_SIZE := Vector2(2048, 1792)
const LOGO_ROWS := 7
const BOARD_ROWS := 16                 # boards: two 1024 x 128 to a row of a 2048 square
const REVERSED := ["apex", "falco", "aurum", "orbis", "northwind", "trident"]
## The series' own partners, on every car and all round every track.
const SERIES := ["apex", "falco", "aurum"]

static var _brands: Array = []
static var _ids: Array = []
static var _logos: Texture2D
static var _boards: Texture2D
static var _decal_mat: StandardMaterial3D


static func brands() -> Array:
	if _brands.is_empty():
		var f := FileAccess.open("res://data/sponsors.json", FileAccess.READ)
		var d: Dictionary = JSON.parse_string(f.get_as_text())
		_brands = d["brands"]
		for b in _brands:
			_ids.append(String(b["id"]))
	return _brands


static func index(id: String) -> int:
	brands()
	return maxi(0, _ids.find(id))


static func brand(id: String) -> Dictionary:
	return brands()[index(id)]


static func color(id: String, key := "bg") -> Color:
	return Color.html(String(brand(id)[key]))


static func logos() -> Texture2D:
	if _logos == null:
		_logos = load("res://textures/sponsor_logos.png")
	return _logos


static func boards() -> Texture2D:
	if _boards == null:
		_boards = load("res://textures/sponsor_boards.png")
	return _boards


static func tyre_strip() -> Texture2D:
	return load("res://textures/tyre_strip.png")


## UV rectangle of a brand's logo: white on clear (to tint), or as a sticker
## on its own colours.
static func logo_uv(id: String, sticker := false) -> Rect2:
	var i := index(id)
	var per_row := int(LOGO_SIZE.x / LOGO_CELL.x)
	var cell := Vector2(i % per_row, i / per_row + (LOGO_ROWS if sticker else 0))
	var px := cell * LOGO_CELL
	return Rect2(px / LOGO_SIZE, LOGO_CELL / LOGO_SIZE)


## A brand's sticker (its logo on its own colours) as a texture for the UI.
static func sticker(id: String) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = logos()
	var r := logo_uv(id, true)
	t.region = Rect2(r.position * LOGO_SIZE, r.size * LOGO_SIZE)
	return t


## Number of boards in the board texture.
static func board_count() -> int:
	return brands().size() + REVERSED.size()


## UV rectangle of advertising board k (the brands in order, then the
## reversed-colour ones).
static func board_uv(k: int) -> Rect2:
	k = posmod(k, board_count())
	return Rect2(Vector2((k % 2) * 0.5, float(k / 2) / BOARD_ROWS), Vector2(0.5, 1.0 / BOARD_ROWS))


static func board_of(id: String, reversed := false) -> int:
	if reversed and REVERSED.has(id):
		return brands().size() + REVERSED.find(id)
	return index(id)


## Lettering and stickers on the cars: one shared material.
static func decal_material() -> StandardMaterial3D:
	if _decal_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = logos()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.32
		m.metallic = 0.1
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.cull_mode = BaseMaterial3D.CULL_BACK
		_decal_mat = m
	return _decal_mat


# ------------------------------------------------------------ teams

## Each Grand Prix team's title sponsor and main partner, matched to its
## colours the way real teams' are.
const GP_DEALS := {
	"apex": ["zentrix", "corvane"],
	"rosso": ["bravik", "kestrel"],
	"argento": ["halcyon", "argent"],
	"navy": ["voltra", "okavo"],
	"emerald": ["korvex", "pellara"],
	"bleu": ["solace", "bluepeak"],
	"eagle": ["quella", "strata"],
	"atlas": ["northwind", "caldera"],
	"nero": ["cargova", "tessela"],
	"azur": ["mareo", "sonara"],
}


## A team's sponsors: title, second, then smaller partners (as many as the
## car has places for). Teams of the junior series (and custom liveries)
## get theirs dealt from the commercial brands.
static func team_deal(team_id: String, team_index: int, series: String) -> Array:
	var pool: Array = []
	for b in brands():
		if not SERIES.has(String(b["id"])):
			pool.append(String(b["id"]))
	var deal: Array = []
	if series == "gp26" and GP_DEALS.has(team_id):
		deal.append_array(GP_DEALS[team_id])
	else:
		var off: int = {"f2": 3, "f3": 7, "f4": 11, "kart": 15}.get(series, 0)
		deal.append(pool[posmod(team_index * 2 + off, pool.size())])
		deal.append(pool[posmod(team_index * 2 + off + 9, pool.size())])
	# Partners: walk the pool from a team-specific start, skipping the
	# brands that are already on the car.
	var k := posmod(team_index * 5 + 2, pool.size())
	while deal.size() < 9:
		var id: String = pool[k % pool.size()]
		if not deal.has(id):
			deal.append(id)
		k += 3
	return deal
