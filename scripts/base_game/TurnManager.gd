extends Node
class_name TurnManager

signal turn_started(player_index: int)
signal turn_ended(player_index: int)
signal bonus_move_available(steps: int)
signal penalty_select_piece()
signal break_barrier_requested()
signal barrier_broken_continue()

enum State {
	IDLE,
	ROLLING,
	BREAK_BARRIER_FIRST,  # ✅ Nuevo: romper barrera obligatoria al sacar par
	MOVE_DICE_1,
	MOVE_DICE_2,
	BONUS_MOVE,
	PENALTY_JAIL
}

var current_state: State = State.IDLE
var current_player_index: int = 0
var consecutive_pairs: int = 0
var captured_this_turn: bool = false
var current_roll: Dictionary = {}
var has_exited_jail_this_turn: bool = false
var has_broken_barrier_this_turn: bool = false  # ✅ Nueva
var players: Array = []
var pending_move_piece: Piece = null
var pending_move_steps: int = 0
var bonus_came_from_dice: int = 0  # 1 o 2

func setup(p_players: Array):
	players = p_players

func start_turn(player_index: int):
	current_player_index = player_index
	current_state = State.IDLE
	bonus_came_from_dice = 0
	has_exited_jail_this_turn = false
	has_broken_barrier_this_turn = false
	captured_this_turn = false
	current_roll = {}
	turn_started.emit(player_index)

func process_roll(dice_results: Array) -> bool:
	var d1 = dice_results[0]
	var d2 = dice_results[1]
	var is_pair = d1 == d2
	current_roll = {"dice1": d1, "dice2": d2, "pair": is_pair}
	
	var player = players[current_player_index]
	
	var can_move_anyway = player._can_move(current_roll)
	var can_exit_jail = player._has_pieces_in_jail() and is_pair
	
	if not can_move_anyway and not can_exit_jail:
		return false
	
	# Manejo de pares consecutivos (3 pares = penalización)
	if is_pair:
		consecutive_pairs += 1
		if consecutive_pairs >= 3:
			consecutive_pairs = 0
			current_state = State.PENALTY_JAIL
			penalty_select_piece.emit()
			return true
	else:
		consecutive_pairs = 0
	
	if is_pair and player._has_own_barrier() and not has_broken_barrier_this_turn:
		current_state = State.BREAK_BARRIER_FIRST
		break_barrier_requested.emit()
		return true
	
	current_state = State.MOVE_DICE_1
	return true

func on_piece_moved(success: bool, captured: bool = false):
	if not success:
		return
	
	if captured:
		captured_this_turn = true
	
	match current_state:
		State.MOVE_DICE_1:
			if captured_this_turn:
				bonus_came_from_dice = 1
				current_state = State.BONUS_MOVE
				bonus_move_available.emit(10)
				captured_this_turn = false
			else:
				current_state = State.MOVE_DICE_2

		State.MOVE_DICE_2:
			if captured_this_turn:
				bonus_came_from_dice = 2
				current_state = State.BONUS_MOVE
				bonus_move_available.emit(10)
				captured_this_turn = false
			else:
				end_turn()

		State.BONUS_MOVE:
			captured_this_turn = false
			if bonus_came_from_dice == 1:
				current_state = State.MOVE_DICE_2  # aún queda dado 2
			else:
				end_turn()

func on_jail_exit():
	has_exited_jail_this_turn = true

func end_turn():
	turn_ended.emit(current_player_index)
	
	var has_pair = current_roll.get("pair", false)
	
	var used_both_dice = current_state in [State.MOVE_DICE_2, State.BONUS_MOVE, State.IDLE] or has_broken_barrier_this_turn

	if has_pair and used_both_dice and not has_exited_jail_this_turn and current_state != State.PENALTY_JAIL:
		has_exited_jail_this_turn = false
		has_broken_barrier_this_turn = false
		captured_this_turn = false
		current_roll = {}
		start_turn(current_player_index)
		return
	
	if has_exited_jail_this_turn:
		consecutive_pairs = 0 
	
	consecutive_pairs = 0
	current_player_index = (current_player_index + 1) % players.size()
	start_turn(current_player_index)

func get_current_steps() -> int:
	match current_state:
		State.MOVE_DICE_1:
			return current_roll.get("dice1", 0)
		State.MOVE_DICE_2:
			return current_roll.get("dice2", 0)
		State.BONUS_MOVE:
			return current_roll.get("bonus", 0)
	return 0

func request_break_barrier():
	break_barrier_requested.emit()

func can_click_piece() -> bool:
	return current_state in [State.MOVE_DICE_1, State.MOVE_DICE_2, State.BONUS_MOVE, State.PENALTY_JAIL, State.BREAK_BARRIER_FIRST]
