class_name AIController
extends Node

enum Difficulty { EASY, NORMAL, HARD }

var difficulty: Difficulty
var tree: AINode
var card_tree: AINode

func setup(p_difficulty: Difficulty):
	difficulty = p_difficulty
	tree = _build_tree()
	card_tree = _build_card_tree()

func decide_piece(context: Dictionary) -> GamePiece:
	return tree.decide(context) as GamePiece

func decide_card(context: Dictionary) -> int:
	if difficulty == Difficulty.EASY:
		return -1
	var hand = context.card_manager.get_hand(context.player.player_id)
	if hand.is_empty():
		return -1
	var result = card_tree.decide(context)
	return result if result != null else -1

func decide_should_draw(context: Dictionary) -> bool:
	if difficulty == Difficulty.EASY:
		return false
	var hand = context.card_manager.get_hand(context.player.player_id)
	if difficulty == Difficulty.NORMAL:
		return hand.size() < 3
	if hand.size() >= 3:
		return false
	return not _is_threatened(context.player, context.board)

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
			root.children = [jail_node, advance_node]
		Difficulty.NORMAL:
			root.children = [finish_node, capture_node, jail_node, advance_node]
		Difficulty.HARD:
			root.children = [finish_node, capture_node, jail_node, barrier_node, advance_node]

	return root

func _check_finish(context: Dictionary) -> GamePiece:
	var player: Player = context.player
	var steps: int = context.steps
	for piece in player.pieces:
		if piece.is_finished or piece.in_jail or piece.is_frozen:
			continue
		if piece.in_home_path:
			var remaining = context.board.home_paths[piece.color].size() - piece.home_route - 1
			if steps == remaining:
				return piece
	return null

func _check_capture(context: Dictionary) -> GamePiece:
	var player: Player = context.player
	var steps: int = context.steps
	for piece in player.pieces:
		if piece.is_finished or piece.in_jail or piece.is_frozen or piece.in_home_path:
			continue
		if not context.movement_manager.can_move_piece(piece, steps):
			continue
		var target_pos = (piece.route + steps + piece.start_index) % context.board.main_path.size()
		if target_pos in context.board.SAFE_SQUARES:
			continue
		var enemies = context.board._get_enemies_at(target_pos, player.player_id)
		if enemies.size() == 1 and not enemies[0].is_shielded:
			return piece
	return null

func _check_jail_exit(context: Dictionary) -> GamePiece:
	var player: Player = context.player
	if context.turn_manager.current_state != TurnManager.State.MOVE_DICE_1:
		return null
	if not context.is_pair or context.has_broken_barrier:
		return null
	var pieces_at_start = player.pieces.filter(func(p): return not p.in_jail and not p.is_finished and p.current_position == player.start_index).size()
	if pieces_at_start >= 2:
		return null
	for piece in player.pieces:
		if piece.in_jail:
			return piece
	return null

func _check_form_barrier(context: Dictionary) -> GamePiece:
	var player: Player = context.player
	var steps: int = context.steps
	for piece in player.pieces:
		if piece.is_finished or piece.in_jail or piece.is_frozen or piece.in_home_path:
			continue
		if not context.movement_manager.can_move_piece(piece, steps):
			continue
		var target_pos = (piece.route + steps + piece.start_index) % context.board.main_path.size()
		for other in player.pieces:
			if other == piece or other.in_jail or other.is_finished:
				continue
			if other.current_position == target_pos:
				return piece
	return null

func _pick_most_advanced(context: Dictionary) -> GamePiece:
	var player: Player = context.player
	var steps: int = context.steps
	var best: GamePiece = null
	var best_route = -1
	for piece in player.pieces:
		if piece.is_finished or piece.in_jail or piece.is_frozen:
			continue
		if not context.movement_manager.can_move_piece(piece, steps):
			continue
		if piece.route > best_route:
			best_route = piece.route
			best = piece
	return best

func _build_card_tree() -> AINode:
	var root = AINode.new()
	root.evaluate = func(_ctx): return null

	var nodes = []
	var card_checks = [
		[CardManager.CardType.JAILBREAK, _card_jailbreak],
		[CardManager.CardType.SHIELD,    _card_shield],
		[CardManager.CardType.TURBO,     _card_turbo],
	]
	if difficulty == Difficulty.HARD:
		card_checks.append_array([
			[CardManager.CardType.FREEZE,   _card_freeze],
			[CardManager.CardType.SABOTAGE, _card_sabotage],
			[CardManager.CardType.THIEF,    _card_thief],
		])
	card_checks.append([CardManager.CardType.DOUBLE, _card_double])

	for entry in card_checks:
		var node = AINode.new()
		node.evaluate = entry[1]
		nodes.append(node)

	root.children = nodes
	return root

func _find_card(hand: Array, card_type: int) -> int:
	for i in range(hand.size()):
		if hand[i] == card_type:
			return i
	return -1

func _card_jailbreak(context: Dictionary) -> Variant:
	var hand = context.card_manager.get_hand(context.player.player_id)
	var idx = _find_card(hand, CardManager.CardType.JAILBREAK)
	if idx == -1:
		return null
	for piece in context.player.pieces:
		if piece.in_jail:
			return idx
	return null

func _card_shield(context: Dictionary) -> Variant:
	var hand = context.card_manager.get_hand(context.player.player_id)
	var idx = _find_card(hand, CardManager.CardType.SHIELD)
	if idx == -1:
		return null
	return idx if _is_threatened(context.player, context.board) else null

func _card_turbo(context: Dictionary) -> Variant:
	var hand = context.card_manager.get_hand(context.player.player_id)
	var idx = _find_card(hand, CardManager.CardType.TURBO)
	if idx == -1:
		return null
	for piece in context.player.pieces:
		if not piece.is_finished and not piece.in_jail and not piece.is_frozen:
			if context.movement_manager.can_move_piece(piece, 5):
				return idx
	return null

func _card_freeze(context: Dictionary) -> Variant:
	var hand = context.card_manager.get_hand(context.player.player_id)
	var idx = _find_card(hand, CardManager.CardType.FREEZE)
	if idx == -1:
		return null
	return idx if _should_use_offensive(context.player, context.board) else null

func _card_sabotage(context: Dictionary) -> Variant:
	var hand = context.card_manager.get_hand(context.player.player_id)
	var idx = _find_card(hand, CardManager.CardType.SABOTAGE)
	if idx == -1:
		return null
	return idx if _should_use_offensive(context.player, context.board) else null

func _should_use_offensive(player: Player, board: GameBoard) -> bool:
	for enemy_player in board.players:
		if enemy_player == player:
			continue
		for enemy in enemy_player.pieces:
			if enemy.in_jail or enemy.is_finished:
				continue
			if (enemy.in_home_path and enemy.home_route >= 3) or enemy.route >= 30:
				return true
			for piece in player.pieces:
				if piece.in_jail or piece.is_finished:
					continue
				var dist = (piece.current_position - enemy.current_position + board.main_path.size()) % board.main_path.size()
				if dist <= 6:
					return true
	return false

func _card_thief(context: Dictionary) -> Variant:
	var hand = context.card_manager.get_hand(context.player.player_id)
	var idx = _find_card(hand, CardManager.CardType.THIEF)
	if idx == -1:
		return null
	for enemy_player in context.board.players:
		if enemy_player == context.player:
			continue
		if context.card_manager.get_hand(enemy_player.player_id).size() >= 2:
			return idx
	return null

func _card_double(context: Dictionary) -> Variant:
	var hand = context.card_manager.get_hand(context.player.player_id)
	var idx = _find_card(hand, CardManager.CardType.DOUBLE)
	if idx == -1:
		return null
	for piece in context.player.pieces:
		if not piece.in_jail and not piece.is_finished:
			return idx
	return null

func _is_threatened(player: Player, board: GameBoard) -> bool:
	for piece in player.pieces:
		if piece.in_jail or piece.is_finished or piece.is_shielded:
			continue
		for enemy_player in board.players:
			if enemy_player == player:
				continue
			for enemy in enemy_player.pieces:
				if enemy.in_jail or enemy.is_finished or enemy.in_home_path:
					continue
				var dist = (piece.current_position - enemy.current_position + board.main_path.size()) % board.main_path.size()
				if dist <= 12:
					return true
	return false
