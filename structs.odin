package main

som_Camera :: struct
{
	pos: [2]f32,
	offset: [2]f32,
	zoom: f32
}

som_Rect :: struct
{
	pos: [2]f32,
	size: [2]f32
}

som_Timer :: struct
{
	start_time: f32,
	time_left: f32,
	run: bool
}
