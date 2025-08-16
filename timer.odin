package main

import "core:math"
import "core:fmt"

Timer :: struct
{
	start_time: f32,
	time_left: f32,
	run: bool
}

timer_init :: proc(timer: ^Timer, start_time: f32)
{
	assert(start_time > 0)
	timer.start_time = start_time
	timer.time_left = start_time
}

timer_update :: proc(timer: ^Timer, delta_time: f32) -> int
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
 
timer_start_and_reset :: proc(timer: ^Timer)
{
	timer.run = true
	timer.time_left = timer.start_time
}

timer_stop_and_reset :: proc(timer: ^Timer)
{
	timer.run = false
	timer.time_left = timer.start_time
}

