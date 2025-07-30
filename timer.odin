package main

som_Timer :: struct
{
	start_time: f32,
	time_left: f32,
	run: bool
}

init_timer :: proc(timer: ^som_Timer, start_time: f32)
{
	timer.start_time = start_time
	timer.time_left = start_time
}

update_timer :: proc(timer: ^som_Timer, delta_time: f32) -> bool
{
	if !timer.run do return false

	timer.time_left -= delta_time
	if timer.time_left <= 0
	{
		timer.time_left = timer.start_time
		return true
	}

	return false
}
