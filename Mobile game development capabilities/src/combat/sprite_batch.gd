class_name SpriteBatch
extends MultiMeshInstance2D
## Draws hundreds of copies of one texture in a single draw call.
## This is what keeps dense bullet patterns smooth on budget phones.

const FLOATS := 12

var cap := 0
var n := 0
var buf := PackedFloat32Array()

func setup(tex: Texture2D, capacity: int, mat: Material = null) -> void:
	cap = capacity
	texture = tex
	material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = cap
	mm.visible_instance_count = 0
	# A fixed bounding box saves the engine recomputing one every frame.
	mm.custom_aabb = AABB(Vector3(-4000, -4000, -1), Vector3(8000, 8000, 2))
	multimesh = mm
	buf.resize(cap * FLOATS)

func begin() -> void:
	n = 0

func add(pos: Vector2, size: float, rot: float, color: Color) -> void:
	if n >= cap:
		return
	var c := cos(rot) * size
	var s := sin(rot) * size
	var i := n * FLOATS
	# Quad meshes are y-up, so the y axis is flipped here to keep textures upright in 2D.
	buf[i] = c
	buf[i + 1] = s
	buf[i + 2] = 0.0
	buf[i + 3] = pos.x
	buf[i + 4] = s
	buf[i + 5] = -c
	buf[i + 6] = 0.0
	buf[i + 7] = pos.y
	buf[i + 8] = color.r
	buf[i + 9] = color.g
	buf[i + 10] = color.b
	buf[i + 11] = color.a
	n += 1

func commit() -> void:
	multimesh.buffer = buf
	multimesh.visible_instance_count = n
