local M = {}

local end_command_str = "End"
local SNOWPILE_MAX = 8
local ns_id = vim.api.nvim_create_namespace("snow")
local stop = true

local function clear_snow(buf)
	local marks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})
	for _, mark in ipairs(marks) do
		vim.api.nvim_buf_del_extmark(buf, ns_id, mark[1])
	end
end

local function end_hygge(buf)
	vim.api.nvim_buf_del_user_command(buf, end_command_str)

	stop = true
end

local function make_grid(height, width)
	local grid = {}

	for i = 0, height do
		grid[i] = {}
		for j = 0, width do
			grid[i][j] = 0
		end
	end

	return grid
end

local function inside_grid(row, col, grid)
	return row >= 0 and row < #grid and col >= 0 and col < #grid[row]
end

local function obstructed(row, col, lines, grid)
	-- `lines` is 1-based, so check char in lines at row + 1 (uppermost line)
	local char_obstructed = (col < #lines[row + 1] and lines[row + 1]:sub(col + 1, col + 1) ~= " ")
	local snowpile_obstructed = grid[row][col] == SNOWPILE_MAX
	return char_obstructed or snowpile_obstructed
end

local function is_floating(row, col, grid, lines)
	if row >= #lines - 1 then
		return false
	end
	return not obstructed(row + 1, col, lines, grid)
end

local function show_snowflake(buf, row, col)
	vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
		virt_text = { { "❄" } },
		virt_text_win_col = col,
	})
end

local size_to_snowpile = {
	[1] = "\u{2581}",
	[2] = "\u{2582}",
	[3] = "\u{2583}",
	[4] = "\u{2584}",
	[5] = "\u{2585}",
	[6] = "\u{2586}",
	[7] = "\u{2587}",
	[8] = "\u{2588}",
}

local function show_snowpile(buf, row, col, size)
	assert(
		size <= SNOWPILE_MAX,
		string.format("Exceeded max snowpile size (%d) at in buf %s: %d, %d", size, buf, row, col)
	)
	local icon = size_to_snowpile[size]

	vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
		virt_text = { { icon } },
		virt_text_win_col = col,
	})
end

local function show_snow(buf, row, col, grid, lines)
	local size = grid[row][col]

	if size == 1 and is_floating(row, col, grid, lines) then
		show_snowflake(buf, row, col)
	else
		show_snowpile(buf, row, col, size)
	end
end

local function show_snow_debug(buf, row, col, grid)
	vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
		virt_text = { { tostring(grid[row][col]) } },
		virt_text_win_col = col,
	})
end

local function show_debug_obstructed(buf, grid, lines)
	for row = 0, #grid - 1 do
		for col = 0, #grid[row] do
			if obstructed(row, col, lines, grid) then
				vim.api.nvim_buf_set_extmark(buf, ns_id, row, 0, {
					virt_text = { { "\u{2588}" } },
					virt_text_win_col = col,
				})
			end
		end
	end
end

local function show_grid(buf, grid, lines)
	for row = 0, #grid do
		for col = 0, #grid[row] do
			if grid[row][col] == 0 then
				goto continue
			end
			show_snow(buf, row, col, grid, lines)
			::continue::
		end
	end
end

local function spawn_snowflake(grid, lines)
	local x = nil
	-- WARN: This could run forever if top line is fully blocked
	while x == nil or obstructed(0, x, lines, grid) do
		x = math.random(0, #grid[0] - 1)
	end
	grid[0][x] = grid[0][x] + 1
end

local function update_snowflake(row, col, old_grid, new_grid, lines)
	-- OPTIMIZE: Can snowflake fall sideways?
	local below = nil
	local below_a = nil
	local below_b = nil
	local below_c = nil
	local below_d = nil

	-- Check straight down
	if inside_grid(row + 1, col, new_grid) and not obstructed(row + 1, col, lines, new_grid) then
		below = old_grid[row + 1][col]
	end

	local d = 1
	if math.random() < 0.5 then
		d = -1
	end

	-- TODO: Merge this with if's below due to redundancy

	-- Check 1 down 1 sideways
	if
		inside_grid(row + 1, col + d, new_grid)
		and not obstructed(row + 1, col, lines, new_grid)
		and not obstructed(row + 1, col + d, lines, new_grid)
	then
		below_a = old_grid[row + 1][col + d]
	end
	if
		inside_grid(row + 1, col - d, new_grid)
		and not obstructed(row + 1, col, lines, new_grid)
		and not obstructed(row + 1, col - d, lines, new_grid)
	then
		below_b = old_grid[row + 1][col - d]
	end

	-- Check 1 down 2 sideways
	if
		inside_grid(row + 1, col + 2 * d, new_grid)
		and not obstructed(row + 1, col, lines, new_grid)
		and not obstructed(row + 1, col + 2 * d, lines, new_grid)
	then
		below_c = old_grid[row + 1][col + 2 * d]
	end
	if
		inside_grid(row + 1, col - 2 * d, new_grid)
		and not obstructed(row + 1, col, lines, new_grid)
		and not obstructed(row + 1, col - 2 * d, lines, new_grid)
	then
		below_d = old_grid[row + 1][col - 2 * d]
	end

	-- TODO: Merge this with if's above

	-- Actually move snow (if possible)
	local moved = false
	-- Straight down
	if below ~= nil and below < SNOWPILE_MAX then
		new_grid[row + 1][col] = new_grid[row + 1][col] + 1
		moved = true
	elseif below_a ~= nil and below_a < SNOWPILE_MAX then
		new_grid[row + 1][col + d] = new_grid[row + 1][col + d] + 1
		moved = true
	elseif below_b ~= nil and below_b < SNOWPILE_MAX then
		new_grid[row + 1][col - d] = new_grid[row + 1][col - d] + 1
		moved = true
	elseif below_c ~= nil and below_c < SNOWPILE_MAX then
		new_grid[row + 1][col + 2 * d] = new_grid[row + 1][col + 2 * d] + 1
		moved = true
	elseif below_d ~= nil and below_d < SNOWPILE_MAX then
		new_grid[row + 1][col - 2 * d] = new_grid[row + 1][col - 2 * d] + 1
		moved = true
	else
		new_grid[row][col] = new_grid[row][col] + old_grid[row][col]
	end

	if moved ~= nil and moved then
		new_grid[row][col] = new_grid[row][col] + old_grid[row][col] - 1
	end
end

local function update_snowpile(row, col, old_grid, new_grid, lines)
	local d = 1
	if math.random() < 0.5 then
		d = -1
	end
	if
		inside_grid(row, col + d, new_grid)
		and old_grid[row][col + d] <= old_grid[row][col] - 3
		and not obstructed(row, col + d, lines, new_grid)
	then
		new_grid[row][col + d] = new_grid[row][col + d] + 1
		new_grid[row][col] = new_grid[row][col] + old_grid[row][col] - 1
	elseif
		inside_grid(row, col - d, new_grid)
		and old_grid[row][col - d] <= old_grid[row][col] - 3
		and not obstructed(row, col - d, lines, new_grid)
	then
		new_grid[row][col - d] = new_grid[row][col - d] + 1
		new_grid[row][col] = new_grid[row][col] + old_grid[row][col] - 1
	elseif inside_grid(row, col, new_grid) and not obstructed(row, col, lines, new_grid) then
		new_grid[row][col] = new_grid[row][col] + old_grid[row][col]
	end
end

local function update_grid(win, buf, old_grid, lines)
	local height = vim.api.nvim_buf_line_count(buf)
	local width = vim.api.nvim_win_get_width(win)

	local new_grid = make_grid(height, width)

	spawn_snowflake(new_grid, lines)

	-- Update positions of snow
	for row = 0, height do
		if row >= #old_grid then
			goto continue_outer
		end
		for col = 0, width do
			if col >= #old_grid[row] or old_grid[row][col] == 0 then
				goto continue_inner
			end
			if is_floating(row, col, old_grid, lines) then
				update_snowflake(row, col, old_grid, new_grid, lines)
			else
				update_snowpile(row, col, old_grid, new_grid, lines)
			end
			::continue_inner::
		end
		::continue_outer::
	end

	return new_grid
end

local function get_lines(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
    local tabwidth = vim.o.tabstop

    local tab_replacement = (" "):rep(tabwidth)

    for row = 1, #lines do
        lines[row] = lines[row]:gsub("\t", tab_replacement)
    end

    return lines
end

local function main_loop(win, buf, grid)
    local lines = get_lines(buf)
	grid = update_grid(win, buf, grid, lines)

	clear_snow(buf)

	show_grid(buf, grid, lines)

	-- TODO: Delay with desired - time_to_update_grid
	if not stop then
		vim.defer_fn(function()
			main_loop(win, buf, grid)
		end, 500)
	else
		clear_snow(buf)
	end
end

M._let_it_snow = function()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()

	local height = vim.api.nvim_buf_line_count(buf)
	local width = vim.api.nvim_win_get_width(win)
	local initial_grid = make_grid(height, width)

	vim.api.nvim_buf_create_user_command(buf, end_command_str, function()
		end_hygge(buf)
	end, {})

	stop = false

	vim.defer_fn(function()
		main_loop(win, buf, initial_grid)
	end, 0)
end

return M
