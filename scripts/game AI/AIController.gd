class_name AIController
extends Node

enum Difficulty {
	EASY,
	NORMAL,
	HARD
}

var difficulty: Difficulty
var tree: AINode

func setup(p_difficulty: Difficulty = Difficulty.NORMAL):
	difficulty = p_difficulty
	tree = _build_tree()

func decide_piece(context: Dictionary) -> Piece:
	return tree.decide(context)

func decide_card(context: Dictionary) -> int:
	if difficulty == Difficulty.EASY:
		return -1
	# lo implementamos después
	return -1

func _build_tree() -> AINode:
	var root = AINode.new()
	root.evaluate = func(_ctx): return null

	var finish_node = AINode.new()
	finish_node.evaluate = _check_finish

	var capture_node = AINode.new()
	capture_node.evaluate = _check_capture

	var jail_node = AINode.new()
	jail_node.evaluate = _check_jail_exit

	var barrier_node = AINode.new()
	barrier_node.evaluate = _check_form_barrier

	var advance_node = AINode.new()
	advance_node.evaluate = _pick_most_advanced

	match difficulty:
		Difficulty.EASY:
			root.children = [advance_node]
		Difficulty.NORMAL:
			root.children = [finish_node, capture_node, jail_node, advance_node]
		Difficulty.HARD:
			root.children = [finish_node, capture_node, jail_node, barrier_node, advance_node]

	return root

func _check_finish(context: Dictionary) -> Piece:
	var player: Player = context.player
	var board: GameBoard = context.board
	var steps: int = context.steps
	for piece in player.pieces:
		if piece.is_finished or piece.in_jail or piece.is_frozen:
			continue
		if piece.in_home_path:
			var remaining = board.home_paths[piece.color].size() - piece.home_route - 1
			if steps == remaining:
				return piece
	return null

func _check_capture(context: Dictionary) -> Piece:
	var player: Player = context.player
	var board: GameBoard = context.board
	var steps: int = context.steps
	var movement_manager: MovementManager = context.movement_manager
	for piece in player.pieces:
		if piece.is_finished or piece.in_jail or piece.is_frozen or piece.in_home_path:
			continue
		if not movement_manager.can_move_piece(piece, steps):
			continue
		var target_pos = (piece.route + steps + piece.start_index) % board.main_path.size()
		if target_pos in board.SAFE_SQUARES:
			continue
		var enemies = board._get_enemies_at(target_pos, player.player_id)
		if enemies.size() == 1 and not enemies[0].is_shielded:
			return piece
	return null

func _check_jail_exit(context: Dictionary) -> Piece:
	var player: Player = context.player
	var is_pair: bool = context.is_pair
	var turn_manager: TurnManager = context.turn_manager
	var has_broken_barrier: bool = context.has_broken_barrier
	if turn_manager.current_state != TurnManager.State.MOVE_DICE_1:
		return null
	if not is_pair:
		return null
	if has_broken_barrier:
		return null
	var pieces_at_start = 0
	for p in player.pieces:
		if not p.in_jail and not p.is_finished and p.current_position == player.start_index:
			pieces_at_start += 1
	if pieces_at_start >= 2:
		return null
	
	for piece in player.pieces:
		if piece.in_jail:
			return piece
	return null

func _check_form_barrier(context: Dictionary) -> Piece:
	var player: Player = context.player
	var board: GameBoard = context.board
	var steps: int = context.steps
	var movement_manager: MovementManager = context.movement_manager
	for piece in player.pieces:
		if piece.is_finished or piece.in_jail or piece.is_frozen or piece.in_home_path:
			continue
		if not movement_manager.can_move_piece(piece, steps):
			continue
		var target_pos = (piece.route + steps + piece.start_index) % board.main_path.size()
		for other in player.pieces:
			if other == piece or other.in_jail or other.is_finished:
				continue
			if other.current_position == target_pos:
				return piece
	return null

func _pick_most_advanced(context: Dictionary) -> Piece:
	var player: Player = context.player
	var steps: int = context.steps
	var movement_manager: MovementManager = context.movement_manager
	var best: Piece = null
	var best_route = -1
	for piece in player.pieces:
		if piece.is_finished or piece.in_jail or piece.is_frozen:
			continue
		if not movement_manager.can_move_piece(piece, steps):
			continue
		if piece.route > best_route:
			best_route = piece.route
			best = piece
	return best
