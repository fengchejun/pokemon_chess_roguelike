extends RefCounted
## Code-native pixel fire: four vertical flame faces around one isometric tile.
## Frame geometry is cached and shared by every burning cell.
const FRAMES := 8
const FRAME_SECONDS := 0.1
static var cache: Dictionary = {}

static func mesh(frame: int, blue: bool, front: bool) -> ArrayMesh:
	var key := "%d:%s:%s" % [posmod(frame,FRAMES),blue,front]
	if cache.has(key): return cache[key]
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var corners := [Vector2(0,-34),Vector2(50,0),Vector2(0,34),Vector2(-50,0)]
	var palette := [Color("e94c23"),Color("ff8e32"),Color("ffcc58"),Color("fff0ad")]
	if blue: palette = [Color("176aa8"),Color("2baed3"),Color("72e5ed"),Color("dcffff")]
	for edge in ([1,2] if front else [3,0,4,5]):
		var a: Vector2 = corners[edge] if edge < 4 else Vector2(-40,-8) if edge == 4 else Vector2(-27,18)
		var b: Vector2 = corners[(edge+1)%4] if edge < 4 else Vector2(40,8) if edge == 4 else Vector2(27,-18)
		for column in 12:
			var phase := float(column)*0.85-float(posmod(frame,FRAMES))*TAU/FRAMES
			var height := clampi(int(14+7*sin(phase)+5*sin(phase*2.0+edge*1.7)),5,25)
			for row in height:
				if row < 3 and posmod(column*3+frame+edge,5) < 2: continue
				# Air holes and detached sparks make each face read as flame, not a wall.
				if row > 6 and posmod(column*7+row*3+frame*5+edge,23) < 2: continue
				var shade := 0 if row > height-4 else 1 if row > height/2 else 2
				if row < 7 and posmod(column+frame+edge,5) == 0: shade = 3
				var color: Color = palette[shade]
				color.a = (0.42 if front else 0.68) if row < 8 else (0.68 if front else 0.86)
				var left := a.lerp(b,float(column)/12)
				var right := a.lerp(b,float(column+1)/12)
				var p := [left+Vector2(0,-row*2),right+Vector2(0,-row*2),right+Vector2(0,-(row+1)*2),left+Vector2(0,-(row+1)*2)]
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
