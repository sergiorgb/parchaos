class_name AINode
extends RefCounted

var evaluate: Callable
var children: Array = []

func decide(context: Dictionary) -> Piece:
	var result = evaluate.call(context)
	if result:
		return result
	for child in children:
		var r = child.decide(context)
		if r:
			return r
	return null
