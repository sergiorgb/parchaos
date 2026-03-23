extends Node

class_name Dice

func roll():
	var d1 = randi_range(1, 6)
	var d2 = randi_range(1, 6)
	return {"dice1": d1, "dice2": d2, "pair": d1 == d2}
