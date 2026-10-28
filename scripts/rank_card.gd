class_name RankCard
extends RefCounted
## The rank card on the home screen (tap for every rank) and the ladder.


## Your rank: badge, name, points and progress. Tap for the full ladder.
static func build(parent: Control, ui: CanvasLayer, save: Node) -> void:
	var rp := int(save.data.get("rank_points", 0))
	var card := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.82), false, Ranks.tier_color(rp), 6)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.custom_minimum_size = Vector2(400, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			show_ladder(ui, save))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)
	parent.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	var badge := RankBadge.new()
	badge.custom_minimum_size = Vector2(56, 62)
	badge.rp = rp
	h.add_child(badge)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(UIStyle.label(Ranks.tier_name(rp), 26, Ranks.tier_color(rp), "extrabold", true))
	var pr := Ranks.progress(rp)
	v.add_child(UIStyle.label("%d RP  ·  %d to %s" % [rp, pr.y - pr.x, Ranks.next_name(rp)], 17, UIStyle.FOG, "semibold", true))
	var back := ColorRect.new()
	back.color = Color(UIStyle.PAPER, 0.12)
	back.custom_minimum_size = Vector2(0, 8)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(back)
	var fill := ColorRect.new()
	fill.color = Ranks.tier_color(rp)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	back.resized.connect(func(): fill.size = Vector2(back.size.x * float(pr.x) / maxf(pr.y, 1), 8))


## Every rank and the points it needs; yours highlighted.
static func show_ladder(ui: CanvasLayer, save: Node) -> void:
	var rp := int(save.data.get("rank_points", 0))
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(shade)
	shade.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			shade.queue_free())
	var panel := PanelContainer.new()
	var sb := UIStyle.panel(Color(UIStyle.TARMAC, 0.97), false, UIStyle.APEX, 8)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UIStyle.label("Driver ranks", 36, UIStyle.PAPER, "extrabold", true))
	v.add_child(UIStyle.label("Earn rank points in every race: finish higher, beat harder bots, race longer. Points never go down. Tap to close.", 18, UIStyle.FOG, "medium"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var mine := Ranks.tier_index(rp)
	# Column-major: Rookie..Silver, Gold..Diamond II, Diamond I..Legend.
	var n: int = Ranks.TIERS.size()
	var per := int(ceil(n / 3.0))
	for r in per:
		for c in 3:
			var k := c * per + r
			if k >= n:
				grid.add_child(Control.new())
				continue
			var t: Array = Ranks.TIERS[k]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.custom_minimum_size = Vector2(250, 0)
			var b := RankBadge.new()
			b.custom_minimum_size = Vector2(30, 34)
			b.rp = int(t[1])
			b.modulate.a = 1.0 if k <= mine else 0.35
			row.add_child(b)
			var nm := UIStyle.label(String(t[0]), 21, t[2] if k <= mine else UIStyle.FOG, "extrabold" if k == mine else "bold", true)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			row.add_child(UIStyle.label("%d" % int(t[1]), 19, UIStyle.PAPER if k == mine else UIStyle.FOG, "semibold", true))
			grid.add_child(row)
	v.add_child(UIStyle.label("Past Legend: a star for every %d RP.  You: %s, %d RP" % [Ranks.LEGEND_STAR, Ranks.tier_name(rp), rp], 19, UIStyle.APEX, "bold", true))
