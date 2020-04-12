extends Control

onready var startTimer: Timer = get_tree().get_nodes_in_group(Groups.START_TIMER)[0]
onready var headstartTimer: Timer = get_tree().get_nodes_in_group(Groups.HEADSTART_TIMER)[0]


func _ready():
	if OS.has_feature("vr"):
		$NotReadyLabel.text = "Press TRIGGER to ready up"
	else:
		$NotReadyLabel.text = "Press JUMP to ready up"
	
	$NotReadyLabel.show()
	$ReadyLabel.hide()
	$StartTimerLabel.hide()
	$HeadstartTimerLabel.hide()


func show_ready():
	$NotReadyLabel.hide()
	$ReadyLabel.show()
	$StartTimerLabel.hide()
	$HeadstartTimerLabel.hide()


func show_start_timer():
	$NotReadyLabel.hide()
	$ReadyLabel.hide()
	$StartTimerLabel.show()
	$HeadstartTimerLabel.hide()


func show_headstart_timer():
	$NotReadyLabel.hide()
	$ReadyLabel.hide()
	$StartTimerLabel.hide()
	$HeadstartTimerLabel.show()


func _process(delta):
	$StartTimerLabel.text = str(startTimer.time_left)
	$HeadstartTimerLabel.text = str(headstartTimer.time_left)