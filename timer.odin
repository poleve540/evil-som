package main

import "core:math"
import "core:fmt"

som_Timer :: struct
{
	start_time: f32,
	time_left: f32,
	run: bool
}

init_timer :: proc(timer: ^som_Timer, start_time: f32)
{
	assert(start_time > 0)
	timer.start_time = start_time
	timer.time_left = start_time
}

update_timer :: proc(timer: ^som_Timer, delta_time: f32) -> int
{
	if !timer.run do return 0

	timer.time_left -= delta_time

	if timer.time_left <= 0
	{
		timeout_count := math.floor(math.abs(timer.time_left) / timer.start_time) + 1
		timer.time_left += timer.start_time * timeout_count

		return int(timeout_count)
	}

	return 0
}
