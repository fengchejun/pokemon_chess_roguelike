extends RefCounted
## Code-native pixel fire: four vertical flame faces around one isometric tile.
## Frame geometry is cached and shared by every burning cell.
const FRAMES := 8
const FRAME_SECONDS := 0.1
const COLUMNS := 28
const MAX_HEIGHT := 34
static var cache: Dictionary = {}

static func mesh(frame: int, blue: bool, front: bool) -> ArrayMesh:
	var key := "%d:%s:%s" % [posmod(frame,FRAMES),blue,front]
	if cache.has(key): return cache[key]
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var corners := [Vector2(0,-34),Vector2(50,0),Vector2(0,34),Vector2(-50,0)]
	var palette := [Color("c75032"),Color("e98b43"),Color("f5c568"),Color("f8e4a0")]
	if blue: palette = [Color("22668d"),Color("389fb9"),Color("80d0d8"),Color("c1e9e5")]
	for edge in ([1,2] if front else [3,0,4,5]):
		var a: Vector2 = corners[edge] if edge < 4 else Vector2(-40,-8) if edge == 4 else Vector2(-27,18)
		var b: Vector2 = corners[(edge+1)%4] if edge < 4 else Vector2(40,8) if edge == 4 else Vector2(27,-18)
		for column in COLUMNS:
			var phase := float(column)*10.2/COLUMNS-float(posmod(frame,FRAMES))*TAU/FRAMES
			var height := clampi(int(19+9*sin(phase)+6*sin(phase*2.0+edge*1.7)),6,MAX_HEIGHT)
			for row in height:
				if row < 3 and posmod(column/2+frame+edge,5) < 2: continue
				# Air holes and detached sparks make each face read as flame, not a wall.
				if row > 12 and posmod(column/2*7+row/2*3+frame*5+edge,31) < 2: continue
				var shade := 0 if row > height-5 else 1 if row > height/2 else 2
				if row < 6 and posmod(column/3+frame+edge,7) == 0: shade = 3
				var color: Color = palette[shade]
				color.a = (0.38 if front else 0.62) if row < 10 else (0.58 if front else 0.78)
				var left := a.lerp(b,float(column)/COLUMNS)
				var right := a.lerp(b,float(column+1)/COLUMNS)
				var p := [left+Vector2(0,-row),right+Vector2(0,-row),right+Vector2(0,-row-1),left+Vector2(0,-row-1)]
				for corner in [0,1,2,0,2,3]:
					vertices.append(Vector3(p[corner].x,p[corner].y,0))
					colors.append(color)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	cache[key] = result
	return result

static func paint(canvas: CanvasItem, center: Vector2, cell: Vector2i, frame: int, blue: bool, front: bool) -> void:
	var phase := posmod(frame+cell.x*3+cell.y*5,FRAMES)
	canvas.draw_mesh(mesh(phase,blue,front),null,Transform2D(0,center))
