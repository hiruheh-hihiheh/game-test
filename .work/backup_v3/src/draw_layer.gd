class_name DrawLayer
extends Node2D
## A canvas whose contents are painted by a callback, so each visual layer of the
## game can sit at its own depth instead of everything sharing one _draw().

var painter: Callable

func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
