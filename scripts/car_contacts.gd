class_name CarContacts
extends RefCounted
## Car-to-car contact, done by hand instead of by the rigid-body solver.
##
## The solver treated cars as hard boxes: hits swapped momentum like a real
## crash, front wings wedged under rear wings (lifting wheels), and contact
## friction and off-centre impulses spun cars. Racing games soften this.
## Here each car is a capsule in plan view (rounded ends, no height): when two
## overlap, a firm, heavily damped spring pushes them apart horizontally
## only. The car doing the hitting takes 60% of the speed change, the car hit
## 40% (so a tap doesn't fire the car ahead up the road), body friction is
## low, and only a fraction of the turning effect is applied (no spins from
## nudges). Cars still never drive through each other.

const STIFF_HZ := 6.0         # contact spring (Hz, on the pair's reduced mass)
const DAMPING := 1.1          # >1: no bounce at all
const HITTER_SHARE := 0.6
const FRICTION := 0.12
const SPIN := 0.35            # share of the contact torque applied
## Multiplayer: the other car's position is a prediction (good to a few tens
## of centimetres), so the contact point is less certain: less turning.
const NET_SPIN := 0.1



## Plan-view capsule: [centre of one end, centre of the other end, radius].
static func capsule(c: RaceCar) -> Array:
	var b := c.global_basis
	var fwd := Vector3(b.z.x, 0.0, b.z.z).normalized()
	var p := c.global_position
	p.y = 0.0
	var r := float(c.spec.get("track_front", 0.8)) + 0.22
	var front := float(c.spec["wheel_front_z"]) + 0.75 - r
	var rear := float(c.spec["wheel_rear_z"]) - 0.5 + r
	return [p + fwd * front, p + fwd * rear, r]


## Closest points between segments p1-q1 and p2-q2 (on the xz plane).
static func _closest(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	var c := d1.dot(r)
	var b := d1.dot(d2)
	var denom := a * e - b * b
	if denom > 1e-6:
		s = clampf((b * f - c * e) / denom, 0.0, 1.0)
	t = (b * s + f) / e if e > 1e-6 else 0.0
	if t < 0.0:
		t = 0.0
		s = clampf(-c / a, 0.0, 1.0) if a > 1e-6 else 0.0
	elif t > 1.0:
		t = 1.0
		s = clampf((b - c) / a, 0.0, 1.0) if a > 1e-6 else 0.0
	return [p1 + d1 * s, p2 + d2 * t]


## One physics step for every pair of cars that both simulate here.
## `touching` is the caller's record of pairs in contact (kept between
## steps); returns the contacts that began this step as [car_a, car_b,
## closing speed m/s].
static func step(cars: Array, delta: float, touching: Dictionary) -> Array:
	var began: Array = []
	var caps: Array = []
	for c in cars:
		caps.append(capsule(c))
	var now := {}
	for i in cars.size():
		var a: RaceCar = cars[i]
		for j in range(i + 1, cars.size()):
			var b: RaceCar = cars[j]
			if a.global_position.distance_squared_to(b.global_position) > 64.0:
				continue
			var hit := _pair(a, b, caps[i], caps[j], b.linear_velocity, b.angular_velocity, true, delta)
			if hit.is_empty():
				continue
			var key := "%d:%d" % [a.get_instance_id(), b.get_instance_id()]
			now[key] = true
			if not touching.has(key):
				began.append([a, b, float(hit[0])])
	touching.clear()
	touching.merge(now)
	return began


## Multiplayer: cars simulated here against cars driven by other phones.
## Only this phone's car is pushed, by exactly its share of what the
## two-car contact would give it; the other phone pushes its own car by its
## share, so between them it's the same contact as two cars in one game.
## The other car's share is added to `kicks` (car -> velocity change): its
## state here is ~0.1 s old, so until news of that push arrives, its copy
## here is moved as if it had been pushed (or this car would keep being
## pushed by a copy that isn't getting out of the way).
static func step_against(locals: Array, others: Array, delta: float, touching: Dictionary, kicks: Dictionary = {}) -> Array:
	var began: Array = []
	var now := {}
	var ocaps: Array = []
	for o in others:
		ocaps.append(capsule(o))
	for a in locals:
		var ca := capsule(a)
		for j in others.size():
			var b: RaceCar = others[j]
			if (a as RaceCar).global_position.distance_squared_to(b.global_position) > 64.0:
				continue
			var hit := _pair(a, b, ca, ocaps[j], b.remote_vel, Vector3.ZERO, false, delta, NET_SPIN)
			if hit.is_empty():
				continue
			kicks[b] = kicks.get(b, Vector3.ZERO) + (hit[1] as Vector3) / b.mass
			var key := "%d:%d" % [a.get_instance_id(), b.get_instance_id()]
			now[key] = true
			if not touching.has(key):
				began.append([a, b, float(hit[0])])
	touching.clear()
	touching.merge(now)
	return began


## The contact between a and b (capsules ca, cb; b moving at vel_b / ang_b).
## Pushes a, and b too if push_b. Returns [closing speed, b's impulse] or []
## if apart.
static func _pair(a: RaceCar, b: RaceCar, ca: Array, cb: Array, vel_b: Vector3, ang_b: Vector3, push_b: bool, delta: float, spin := SPIN) -> Array:
	var pts := _closest(ca[0], ca[1], cb[0], cb[1])
	var pa: Vector3 = pts[0]
	var pb: Vector3 = pts[1]
	var d := pb - pa
	var dist := d.length()
	var overlap: float = float(ca[2]) + float(cb[2]) - dist
	if overlap <= 0.0:
		return []
	var n := d / dist if dist > 1e-4 else Vector3(a.global_basis.x.x, 0, a.global_basis.x.z).normalized()
	var point := (pa + pb) * 0.5
	point.y = (a.global_position.y + b.global_position.y) * 0.5
	var va := a.linear_velocity + a.angular_velocity.cross(point - a.global_position)
	var vb := vel_b + ang_b.cross(point - b.global_position)
	var rel := vb - va
	var vn := rel.dot(n)                       # < 0: closing
	var mu := a.mass * b.mass / (a.mass + b.mass)
	var w := TAU * STIFF_HZ
	var force := mu * (w * w * overlap - 2.0 * DAMPING * w * vn)
	if force <= 0.0:
		return []
	# Who's doing the hitting: the one moving harder into the other.
	var a_in := a.linear_velocity.dot(n)
	var b_in := -vel_b.dot(n)
	var share_a := 0.5
	if absf(a_in - b_in) > 0.5:
		share_a = HITTER_SHARE if a_in > b_in else 1.0 - HITTER_SHARE
	# Impulses sized so the relative change is what the spring asks
	# for, split by share (not by mass, so it can be uneven).
	var j_rel := force * delta / mu
	var ja := n * (-j_rel * share_a * a.mass)
	var jb := n * (j_rel * (1.0 - share_a) * b.mass)
	# Low body friction along the contact.
	var tang := rel - n * vn
	var tl := tang.length()
	if tl > 0.01:
		var tf := tang / tl * minf(FRICTION * force * delta, mu * tl * 0.3)
		ja += tf
		jb -= tf
	a.apply_central_impulse(ja)
	a.apply_torque_impulse((point - a.global_position).cross(ja) * spin)
	if push_b:
		b.apply_central_impulse(jb)
		b.apply_torque_impulse((point - b.global_position).cross(jb) * spin)
	return [maxf(-vn, 0.0), jb]


## Slipstream: close behind another car on a straight, its wake cuts your
## drag (RaceCar.SLIPSTREAM at most, strongest closest, gone by 40 m).
## Sets `tow` on each car in `cars`, looking at every car in `others`.
const TOW_RANGE := 40.0

static func slipstream(cars: Array, others: Array) -> void:
	for car in cars:
		var c: RaceCar = car
		var best := 0.0
		var v := c.forward_speed()
		if v > 25.0:
			var fwd := c.global_basis.z
			var right := c.global_basis.x
			for other in others:
				var o: RaceCar = other
				if o == c:
					continue
				var d := o.global_position - c.global_position
				var along := d.dot(fwd)
				if along < 4.0 or along > TOW_RANGE:
					continue
				if absf(d.dot(right)) > 1.6 + along * 0.02:
					continue
				# Only a car going the same way, not much slower.
				if o.global_basis.z.dot(fwd) < 0.97 or o.forward_speed() < v * 0.75:
					continue
				best = maxf(best, 1.0 - (along - 4.0) / (TOW_RANGE - 4.0))
			best *= clampf((v - 25.0) / 15.0, 0.0, 1.0)
		c.tow = move_toward(c.tow, best, 0.08)
