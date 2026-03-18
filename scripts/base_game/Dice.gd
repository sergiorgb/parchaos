extends Node

func roll() -> Dictionary:
	var dice1 = randi_range(1, 6)
	var dice2 = randi_range(1, 6)
	return {
		"dice1": dice1,
		"dice2": dice2,
		"total": dice1 + dice2,
		"pair": dice1 == dice2
	}
