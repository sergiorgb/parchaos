class_name AINode
extends RefCounted

var evaluate: Callable
var children: Array = []

func decide(context: Dictionary) -> Variant:
	var result = evaluate.call(context)
	if result != null:
		return result
	for child in children:
		var r = child.decide(context)
		if r != null:
			return r
	return null
