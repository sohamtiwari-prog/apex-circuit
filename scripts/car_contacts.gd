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
			var ca: Array = caps[i]
			var cb: Array = caps[j]
			var pts := _closest(ca[0], ca[1], cb[0], cb[1])
			var pa: Vector3 = pts[0]
			var pb: Vector3 = pts[1]
			var d := pb - pa
			var dist := d.length()
			var overlap: float = float(ca[2]) + float(cb[2]) - dist
			if overlap <= 0.0:
				continue
			var n := d / dist if dist > 1e-4 else Vector3(a.global_basis.x.x, 0, a.global_basis.x.z).normalized()
			var point := (pa + pb) * 0.5
			point.y = (a.global_position.y + b.global_position.y) * 0.5
			var va := a.linear_velocity + a.angular_velocity.cross(point - a.global_position)
			var vb := b.linear_velocity + b.angular_velocity.cross(point - b.global_position)
			var rel := vb - va
			var vn := rel.dot(n)                       # < 0: closing
			var mu := a.mass * b.mass / (a.mass + b.mass)
			var w := TAU * STIFF_HZ
			var force := mu * (w * w * overlap - 2.0 * DAMPING * w * vn)
			if force <= 0.0:
				continue
			var key := "%d:%d" % [a.get_instance_id(), b.get_instance_id()]
			now[key] = true
			if not touching.has(key):
				began.append([a, b, maxf(-vn, 0.0)])
			# Who's doing the hitting: the one moving harder into the other.
			var a_in := a.linear_velocity.dot(n)
			var b_in := -b.linear_velocity.dot(n)
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
			b.apply_central_impulse(jb)
			a.apply_torque_impulse((point - a.global_position).cross(ja) * SPIN)
			b.apply_torque_impulse((point - b.global_position).cross(jb) * SPIN)
	touching.clear()
	touching.merge(now)
	return began
