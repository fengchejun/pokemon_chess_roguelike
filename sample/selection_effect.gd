extends RefCounted

const Art = preload("res://sample/pixel_art.gd")
const GOLD := Color("f9e2af")
static var silhouettes: Dictionary = {}

static func silhouette(index: int) -> Dictionary:
	if silhouettes.has(index): return silhouettes[index]
	var part := Art.tile(index)
	var image := part.atlas.get_image().get_region(Rect2i(part.region))
	var mask := BitMap.new()
	mask.create_from_image_alpha(image,0.5)
	var contours: Array[PackedVector2Array] = []
	var scale_factor := 96.0/image.get_width()
	var top := 96.0
	for polygon in mask.opaque_to_polygons(Rect2i(Vector2i.ZERO,image.get_size()),0.0):
		if polygon.size() < 8: continue
		var path := PackedVector2Array()
		for point in polygon:
			var pixel := (point*scale_factor).round()
			path.append(pixel)
			top = minf(top,pixel.y)
		path.append(path[0])
		contours.append(path)
	silhouettes[index] = {"contours":contours,"top":top}
	return silhouettes[index]

static func draw_outline(canvas: CanvasItem, index: int, origin: Vector2) -> void:
	for path in silhouette(index)["contours"]:
		var translated := PackedVector2Array()
		for p in path: translated.append(p+origin)
		canvas.draw_polyline(translated,Color("362c26"),5,false)
		canvas.draw_polyline(translated,GOLD,3,false)

static func draw_arrow(canvas: CanvasItem, tip: Vector2) -> void:
	var shape := PackedVector2Array([Vector2(-4,-16),Vector2(4,-16),Vector2(4,-10),Vector2(9,-10),Vector2(9,-7),Vector2(2,0),Vector2(-2,0),Vector2(-9,-7),Vector2(-9,-10),Vector2(-4,-10)])
	for i in shape.size(): shape[i] += tip.round()
	canvas.draw_colored_polygon(shape,GOLD)
	canvas.draw_polyline(shape+PackedVector2Array([shape[0]]),Color("352d29"),2,false)
	canvas.draw_line(tip+Vector2(-2,-14),tip+Vector2(2,-14),Color("fff5d9"),2)
