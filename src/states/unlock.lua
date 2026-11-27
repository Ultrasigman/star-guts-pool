-- Star Guts Pool for Dice Have No Eyes 1.0.
-- Load the screen from the installed game before attaching the mod.

local screen_path = "src/states/unlock.lua"
local supported_build = "2026.11.27-76d72f4"
local utf8 = require("utf8")

local function little_endian(bytes, position, size)
	local number = 0
	for index = position + size - 1, position, -1 do
		number = number * 256 + bytes:byte(index)
	end
	return number
end

local function read_game_file_from_zip(file, path)
	local size = assert(file:seek("end"))
	local tail_start = math.max(0, size - 65557)
	assert(file:seek("set", tail_start))
	local tail = assert(file:read("*a"))
	local eocd
	for position = #tail - 21, 1, -1 do
		if tail:sub(position, position + 3) == "PK\5\6"
			and little_endian(tail, position + 20, 2) == #tail - position - 21
		then
			eocd = position
			break
		end
	end
	assert(eocd, "installed game ZIP directory is missing")

	local directory_size = little_endian(tail, eocd + 12, 4)
	local directory_start = tail_start + eocd - 1 - directory_size
	local zip_start = directory_start - little_endian(tail, eocd + 16, 4)
	assert(file:seek("set", directory_start))
	local directory = assert(file:read(directory_size))
	local position = 1
	while position + 45 <= #directory do
		assert(directory:sub(position, position + 3) == "PK\1\2", "invalid ZIP directory entry")
		local name_length = little_endian(directory, position + 28, 2)
		local extra_length = little_endian(directory, position + 30, 2)
		local comment_length = little_endian(directory, position + 32, 2)
		local name_start = position + 46
		if directory:sub(name_start, name_start + name_length - 1) == path then
			local local_offset = little_endian(directory, position + 42, 4)
			local compressed_size = little_endian(directory, position + 20, 4)
			local method = little_endian(directory, position + 10, 2)
			assert(file:seek("set", zip_start + local_offset))
			local header = assert(file:read(30))
			assert(header:sub(1, 4) == "PK\3\4", "invalid game ZIP entry")
			assert(file:seek("cur", little_endian(header, 27, 2) + little_endian(header, 29, 2)))
			local content = assert(file:read(compressed_size))
			if method == 0 then return content end
			assert(method == 8, "unsupported compression in game ZIP entry")
			return love.data.decompress("string", "deflate", content)
		end
		position = name_start + name_length + extra_length + comment_length
	end
	error("missing game file: " .. path)
end

local function original_file(path)
	local source = love.filesystem.getSource()
	local file = io.open(source .. "/" .. path, "rb")
	if file then
		local content = file:read("*a")
		file:close()
		return content
	end

	file = assert(io.open(source, "rb"))
	local ok, result = pcall(read_game_file_from_zip, file, path)
	file:close()
	assert(ok, result)
	return result
end

local function patch_once(source, marker, replacement)
	local first, last = source:find(marker, 1, true)
	assert(first and not source:find(marker, last + 1, true), "game source structure changed: " .. marker)
	return source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
end

local Pool = {}
Pool.__index = Pool

local labels = {
	en = {
		pool = "Upgrade pool", active = "Active", banned = "Banned", close = "Close", apply = "Apply",
		ban = "Ban", restore = "Restore", slots = "%d bans, %d slots", next_slot = "Next slot %d ¤",
		balance = "Stars %d ¤",
		locked = "Unlock Bans in the tree to change the pool.",
		empty_active = "No active upgrades", empty_banned = "No banned upgrades",
		favorites = "Favorites", protected = "Protected", favorite = "Favorite",
		mark_favorite = "Add to favorites and keep active", unmark_favorite = "Remove from favorites",
		open_contents = "View items in this upgrade", back_to_pool = "Back to pool",
		activate_all = "Activate all", pending_slots = "%d new slots for %d ¤",
		pending_note = "Changes pending",
		confirm_title = "Confirm slot purchase",
		purchase = "To apply these changes, buy %d ban %s for %d ¤.",
		slot_names = {"slot", "slots"},
		balance_now = "Current balance %d ¤", balance_after = "After purchase %d ¤",
		shortage = "You need %d ¤ more.",
		revise = "Edit bans", confirm = "Buy and apply",
		discard = "Discard changes", discard_title = "Discard pending changes?",
		keep_editing = "Keep editing", discard_close = "Discard and close",
		search = "Search upgrades or items", no_matches = "No matching upgrades",
		presets = "Presets", preset_name = "Preset name", save_new = "Save as new",
		load_preset = "Load", overwrite = "Overwrite", overwrite_title = "Overwrite saved preset?",
		cancel = "Cancel", empty_presets = "No saved presets",
		preset_hint = "Load a preset, then apply it in the upgrade pool.",
		duplicate_preset = "That name is taken. Use Overwrite to update the saved preset.",
		preset_saved = "Saved \"%s\".", preset_loaded = "Loaded \"%s\".",
	},
	ru = {
		pool = "Пул улучшений", active = "Активные", banned = "В бане", close = "Закрыть", apply = "Применить",
		ban = "Бан", restore = "Вернуть", slots = "Банов %d, слотов %d", next_slot = "Следующий слот %d ¤",
		balance = "Звёзды %d ¤",
		locked = "Откройте «Баны» в дереве, чтобы менять пул.",
		empty_active = "Нет активных улучшений", empty_banned = "Нет забаненных улучшений",
		favorites = "Избранное", protected = "Защищено", favorite = "В избранном",
		mark_favorite = "В избранное и оставить активным", unmark_favorite = "Убрать из избранного",
		open_contents = "Посмотреть состав набора", back_to_pool = "К спискам",
		activate_all = "Активировать всё", pending_slots = "Новых слотов %d за %d ¤",
		pending_note = "Есть неприменённые изменения",
		confirm_title = "Подтвердить покупку",
		purchase = "Для применения настроек нужно купить %d %s бана за %d ¤.",
		slot_names = {"слот", "слота", "слотов"},
		balance_now = "Сейчас %d ¤", balance_after = "После покупки %d ¤",
		shortage = "Не хватает %d ¤.",
		revise = "Изменить баны", confirm = "Купить и применить",
		discard = "Отменить изменения", discard_title = "Отменить неприменённые изменения?",
		keep_editing = "Продолжить редактирование", discard_close = "Отменить и закрыть",
		search = "Поиск по улучшениям и предметам", no_matches = "Совпадений нет",
		presets = "Пресеты", preset_name = "Название пресета", save_new = "Сохранить новый",
		load_preset = "Загрузить", overwrite = "Перезаписать", overwrite_title = "Перезаписать пресет?",
		cancel = "Отмена", empty_presets = "Нет сохранённых пресетов",
		preset_hint = "Загрузите пресет и нажмите «Применить» в пуле улучшений.",
		duplicate_preset = "Это имя занято. Нажмите «Перезаписать», чтобы обновить пресет.",
		preset_saved = "Сохранён «%s».", preset_loaded = "Загружен «%s».",
	},
}

local tint = {
	ink = {0.94, 0.93, 1, 1},
	muted = {0.72, 0.70, 0.84, 1},
	active = {0.51, 0.88, 0.78, 1},
	banned = {1, 0.57, 0.68, 1},
	box = {0.075, 0.061, 0.145, 0.98},
	edge = {0.51, 0.47, 0.69, 0.55},
	stripe = {0.14, 0.125, 0.23, 0.78},
	button = {0.16, 0.14, 0.28, 0.98},
	hover = {0.28, 0.24, 0.43, 1},
	favorite = {1, 0.83, 0.48, 1},
	favorite_row = {0.21, 0.16, 0.24, 0.98},
}

local rows_per_column = 6
local row_height = 46
local icon_size, icon_spacing = 20, 22
local detail_columns, detail_rows = 4, 4
local items_per_page = detail_columns * detail_rows
local favorite_var = "star_guts_pool_favorites"
local preset_var = "star_guts_pool_presets_v1"
local presets_per_page = 6

local function words()
	return labels[require("locale").get_code()] or labels.en
end

local function search_key(text)
	return (UTF8_LOWER(text):gsub("%s+", " ")):trim()
end

local function matches_query(entry, query, locale)
	if entry.sort_title:find(query, 1, true) then return true end
	for _, item in ipairs(entry.items) do
		if item.search_locale ~= locale then
			item.search_name = search_key(TS(item.config.name))
			item.search_locale = locale
		end
		if item.search_name:find(query, 1, true) then return true end
	end
	return false
end

local function box(mode, fill, x, y, width, height, radius)
	lg.setColor(unpack(fill))
	lg.rectangle(mode, x, y, width, height, radius)
end

local function set_ui_font(size, locale)
	if locale then
		display:set_locale_font("ui", size, locale)
	else
		display:set_font("ui", size)
	end
end

local function text_at(text, x, y, width, size, color, align, locale)
	set_ui_font(size, locale)
	local text_width = lg.getFont():getWidth(text)
	local limit = width * display.print_scale - 2
	if text_width > limit then
		set_ui_font(math.max(8, math.floor(size * limit / text_width)), locale)
	end
	lg.setColor(unpack(color))
	local height = lg.getFont():getHeight() / display.print_scale
	display:printf(text, x, y - height / 2, width, align)
end

local star_points = {}
for point = 0, 9 do
	local angle = -math.pi / 2 + point * math.pi / 5
	local radius = point % 2 == 0 and 8 or 3.8
	star_points[#star_points + 1] = math.cos(angle) * radius
	star_points[#star_points + 1] = math.sin(angle) * radius
end
local star_triangles = love.math.triangulate(star_points)

local function draw_star(x, y, marked, enabled)
	lg.push("all")
	lg.translate(x, y)
	lg.setColor(unpack(enabled and tint.favorite or tint.muted))
	if marked then
		for _, triangle in ipairs(star_triangles) do lg.polygon("fill", triangle) end
	else
		lg.polygon("line", star_points)
	end
	lg.pop()
end

local function favorite_keys()
	local saved = SAVE:get_var(favorite_var)
	return set(type(saved) == "string" and saved:split_and_trim(",") or {})
end

local function read_presets()
	local data = SAVE:get_var(preset_var)
	local entries = {}
	if type(data) ~= "string" then return entries end
	for record in data:gmatch("[^;]+") do
		local encoded, banned, favorites = record:match("^([^|]+)|([^|]*)|([^|]*)$")
		if encoded then
			local ok, name = pcall(love.data.decode, "string", "base64", encoded)
			if ok and name ~= "" and utf8.len(name) and not name:find("%c") then
				entries[#entries + 1] = {
					name = name, bans = set(banned:split_and_trim(",")),
					favorites = set(favorites:split_and_trim(",")),
				}
			end
		end
	end
	return entries
end

local function write_presets(entries)
	local records = {}
	for index, entry in ipairs(entries) do
		records[index] = table.concat({
			love.data.encode("string", "base64", entry.name),
			table.concat(entry.bans:values_readonly(), ","),
			table.concat(entry.favorites:values_readonly(), ","),
		}, "|")
	end
	SAVE:set_var(preset_var, table.concat(records, ";"))
	SAVE:save()
end

function Pool.is_favorite(key)
	return favorite_keys():has(key)
end

local function remove_favorite_bans(banned, favorites)
	local changed = false
	for _, key in favorites:ipairs() do
		if banned:has(key) then
			banned:remove(key)
			changed = true
		end
	end
	return changed
end

local function same_keys(first, second)
	if first:size() ~= second:size() then return false end
	for _, key in first:ipairs() do
		if not second:has(key) then return false end
	end
	return true
end

local function item_description(config, state)
	if config.dynamic_description then
		local ok, description = pcall(config.dynamic_description, table.overlay({state = state}, config))
		if ok and type(description) == "string" then return description:dedent() end
	end
	return TS((config.description or ""):dedent())
end

local function draw_cached_description(text, x, y)
	lg.push("all")
	lg.setColor(colour.unpack_argb(0xff150830))
	text:draw(x + 1, y + 4 / display.print_scale)
	lg.pop()
	text:draw(x, y)
end

local function cached_tooltip_drawer()
	local path = "src/ui/item_hover.lua"
	local source = (original_file(path):gsub("\r\n", "\n"))
	source = patch_once(source, "effects, already_translated)", "effects, already_translated, desc_text)")
	source = patch_once(source, "\tlocal translated_coloured_desc = coloured_text(desc)\n", "")
	source = patch_once(source,
		'\tlocal desc_text = display:static_text(translated_coloured_desc, w - padding_x * 2, "center", true)\n', "")
	source = patch_once(source,
		'display:print_shadowed(translated_coloured_desc, bx + padding_x, by + padding_y, w - padding_x * 2, "center")',
		'draw_cached_description(desc_text, bx + padding_x, by + padding_y)')
	local load_tooltip = assert(loadstring("local draw_cached_description = ...\n" .. source, "@" .. path))
	return load_tooltip(draw_cached_description).draw
end

function Pool:prepare_tooltip(item, width)
	local locale = require("locale").get_code()
	local font = display:get_font("ui", 11)
	local cached = self.cached_tooltip
	if cached and cached.item == item and cached.width == width and cached.locale == locale
		and cached.font == font and cached.scale == display.print_scale
	then
		return cached
	end

	local config = item.config
	local description = item_description(config, self.state)
	display:set_font("ui", 11)
	cached = {
		item = item, width = width, locale = locale, font = font, scale = display.print_scale,
		name = TS(config.name), description = description,
		tag = config.food and "SNACK" or config.usage == "active" and "SPELL" or nil,
		text = display:static_text(coloured_text(description), width - 10, "center", true),
	}
	self.cached_tooltip = cached
	return cached
end

function Pool:draw_item_tooltip(tooltip, x, y)
	self.tooltip_drawer(tooltip.name, tooltip.description, tooltip.tag, x, y, tooltip.width,
		tooltip.item.config, true, tooltip.text)
end

local function add_button(kernel, x, y, width, height, label, click, options)
	options = options or {}
	return kernel:add_from_system("ui", {
		pos = vec2(x + width / 2, y + height / 2),
		halfsize = vec2(width / 2, height / 2),
		click_type = "aabb",
		order = 240,
		gamepad_button = options.gamepad,
		keyboard_button = options.key,
		gamepad_button_pos = options.gamepad and vec2(width / 2 + 21, 0),
		suppress_gamepad_button_draw = options.key ~= nil,
		nav_cursor_offset = vec2(),
		click = click,
		hover = options.hover,
		draw = function(button)
			local enabled = button.available ~= false
			if enabled then button:hover_anim() end
			local hw, hh = button.halfsize:unpack()
			local focused = enabled and (button.hovered or button.selected)
			box("fill", focused and tint.hover or tint.button, -hw, -hh, hw * 2, hh * 2, 5)
			box("line", focused and tint.ink or tint.edge, -hw, -hh, hw * 2, hh * 2, 5)
			local ink = enabled and (button.ink or tint.ink) or tint.muted
			if options.content then
				options.content(button, enabled, ink)
			else
				text_at(label(button), -hw + 4, 0, hw * 2 - 8, options.font or 14, ink, "center")
			end
		end,
	})
end

local function slot_price(bans, slots)
	-- Use the game's pricing method with the slot count at this step of the quote.
	return bans.next_slot_cost({slots = function() return slots end})
end

function Pool:quote_purchase()
	local bans = require("src.bans")
	local owned = bans:slots()
	local used = self.draft.bans:size()
	local needed = math.max(0, used - owned)
	local total = 0
	for count = owned, owned + needed - 1 do
		total = total + slot_price(bans, count)
	end
	return {owned = owned, used = used, needed = needed, total = total, balance = SAVE.stars}
end

function Pool:toggle_tree_ban(key)
	if not SAVE:has_unlock("play_favs") then return false end
	local bans = require("src.bans")
	if bans:has(key) then
		bans:remove(key)
		return true
	end
	if Pool.is_favorite(key) or not self:is_purchased_upgrade(key) then return false end
	if bans:free_slot() then
		bans:add(key)
		return true
	end
	return self:open_panel() and self:toggle_draft_ban(key)
end

function Pool:toggle_draft_ban(key)
	if not self.draft or self.confirmation or not SAVE:has_unlock("play_favs") then return false end
	local draft = self.draft
	if draft.bans:has(key) then
		draft.bans:remove(key)
	elseif not draft.favorites:has(key) and self:is_purchased_upgrade(key) then
		draft.bans:add(key)
	else
		return false
	end
	self:refresh()
	return true
end

function Pool:activate_all()
	if not self.draft or self.confirmation or not SAVE:has_unlock("play_favs") then return end
	local banned = self.draft.bans
	for _, key in ipairs(banned:values()) do
		if self:is_purchased_upgrade(key) then
			banned:remove(key)
		end
	end
	self:refresh()
	if input.mode == "gamepad" then self.modal_ui:focus(self.close_button) end
end

function Pool.draw_favorite_label(button)
	local half = button.halfsize.x
	draw_star(-half + 9, 0, true, true)
	text_at(words().favorite, -half + 23, 0, half * 2 - 23, 13, tint.favorite)
end

function Pool:close()
	self:focus_text()
	self.open = false
	self.draft = nil
	self.confirmation = nil
	self.previous_focus = nil
	self.inspection = nil
	self.presets = nil
	self.cached_tooltip = nil
	if self.background then self.background.source = nil end
	self.modal_ui:focus(nil)
	self.details_ui:focus(nil)
	self.presets_ui:focus(nil)
	self.confirm_ui:focus(nil)
end

function Pool:reset_draft()
	local draft = self.draft
	draft.bans = draft.saved_bans:copy()
	draft.favorites = draft.saved_favorites:copy()
	remove_favorite_bans(draft.bans, draft.favorites)
	self:refresh()
	if input.mode == "gamepad" then self.modal_ui:focus(self.close_button) end
end

function Pool:apply_draft(quote)
	if self.draft.changed then
		local bans = require("src.bans")
		local queued_bans = self.draft.bans:values_readonly()
		local queued_favorites = table.concat(self.draft.favorites:values_readonly(), ",")
		if quote.needed > 0 then
			if not SAVE:try_take_stars(quote.total) then return end
			SAVE:set_var("ban_slots", quote.owned + quote.needed)
		end
		bans:_store(queued_bans)
		SAVE:set_var(favorite_var, queued_favorites)
	end
	self:close()
end

function Pool:show_confirmation(quote)
	self:focus_text()
	self.confirmation = quote
	self.buy_button.available = quote.discard or quote.overwrite ~= nil or quote.total <= quote.balance
	self.buy_button.suppress_sound = not self.buy_button.available
	self.revise_button.nav_right = self.buy_button.available and self.buy_button or nil
	self.confirm_ui:focus(self.revise_button)
end

function Pool:request_close()
	if not self.draft or self.confirmation then return end
	if self.draft.changed then
		self.previous_focus = self.modal_ui.gamepad_focus
		self:show_confirmation({discard = true})
	else
		self:close()
	end
end

function Pool:request_apply()
	if not self.draft or self.confirmation then return end
	local quote = self:quote_purchase()
	if quote.needed == 0 or not self.draft.changed then
		self:apply_draft(quote)
	else
		self.previous_focus = self.modal_ui.gamepad_focus
		self:show_confirmation(quote)
	end
end

function Pool:confirm_purchase()
	local previous = self.confirmation
	if not previous then return end
	local current = self:quote_purchase()
	if previous.owned ~= current.owned or previous.needed ~= current.needed
		or previous.total ~= current.total or previous.balance ~= current.balance
	then
		self:show_confirmation(current)
	elseif current.total <= current.balance then
		self:apply_draft(current)
	end
end

function Pool:leave_confirmation()
	if not self.confirmation then return end
	self.confirmation = nil
	self.confirm_ui:focus(nil)
	if self.presets then
		self.presets_ui:focus(self.previous_focus or self.presets_back)
	else
		self.modal_ui:focus(self.previous_focus or self.close_button)
	end
	self.previous_focus = nil
end

local function slot_word(names, count)
	if #names == 2 then return names[count == 1 and 1 or 2] end
	local last_two = count % 100
	if last_two >= 11 and last_two <= 14 then return names[3] end
	local last = count % 10
	if last == 1 then return names[1] end
	if last >= 2 and last <= 4 then return names[2] end
	return names[3]
end

function Pool:build_confirmation()
	local kernel = self.confirm_menu
	local w, h = math.min(self.width - 54, 570), 244
	local x, y = (self.width - w) / 2, (self.height - h) / 2
	kernel:add({draw = function()
		local L, quote = words(), self.confirmation
		box("fill", {0.025, 0.019, 0.055, 0.86}, 0, 0, self.width, self.height, 0)
		box("fill", tint.box, x, y, w, h, 10)
		box("line", tint.edge, x, y, w, h, 10)
		local sx, sy = lg.transformPoint(x + w / 2, y + h / 2)
		require("src.shaders.chromab"):add_rect_mask({pos = vec2(sx, sy), size = vec2(w, h) * display.scale})
		if quote.discard then
			text_at(L.discard_title, x + 24, y + 88, w - 48, 25, tint.ink, "center")
			return
		end
		if quote.overwrite then
			text_at(L.overwrite_title, x + 24, y + 62, w - 48, 25, tint.ink, "center")
			text_at(quote.overwrite.name, x + 24, y + 116, w - 48, 17, tint.favorite, "center", "zh")
			return
		end
		text_at(L.confirm_title, x + 24, y + 42, w - 48, 25, tint.ink, "center")
		local message = L.purchase:format(quote.needed, slot_word(L.slot_names, quote.needed), quote.total)
		text_at(message, x + 24, y + 90, w - 48, 15, tint.ink, "center")
		local remaining = quote.balance - quote.total
		local current = L.balance_now:format(quote.balance)
		if remaining >= 0 then
			text_at(current, x + 24, y + 132, w / 2 - 28, 17, tint.ink, "center")
			text_at(L.balance_after:format(remaining), x + w / 2 + 4, y + 132, w / 2 - 28, 17, tint.favorite, "center")
		else
			local note = current .. "    " .. L.shortage:format(-remaining)
			text_at(note, x + 24, y + 132, w - 48, 16, tint.banned, "center")
		end
	end})
	local width = (w - 72) / 2
	self.buy_button = add_button(kernel, x + w - width - 26, y + h - 66, width, 38,
		function()
			local L = words()
			if self.confirmation.overwrite then return L.overwrite end
			return self.confirmation.discard and L.discard_close or L.confirm
		end,
		function()
			if self.confirmation.discard then
				self:close()
			elseif self.confirmation.overwrite then
				local preset = self.confirmation.overwrite
				self:leave_confirmation()
				self:save_preset(preset)
			else
				self:confirm_purchase()
			end
		end)
	self.buy_button.ink = tint.favorite
	self.revise_button = add_button(kernel, x + 26, y + h - 66, width, 38,
		function()
			local L = words()
			if self.confirmation.overwrite then return L.cancel end
			return self.confirmation.discard and L.keep_editing or L.revise
		end,
		function() self:leave_confirmation() end, {key = "escape", gamepad = "b"})
	self.buy_button.nav_left = self.revise_button
end

function Pool:draw_frame(title)
	local pw, ph = self.panel_width, self.panel_height
	local x, y = self.panel_x, self.panel_y
	box("fill", {0.025, 0.019, 0.055, 0.78}, 0, 0, self.width, self.height, 0)
	box("fill", tint.box, x, y, pw, ph, 10)
	box("line", tint.edge, x, y, pw, ph, 10)
	text_at(title, x + 23, y + 31, pw - 190, 26, tint.ink)
	local sx, sy = lg.transformPoint(x + pw / 2, y + ph / 2)
	require("src.shaders.chromab"):add_rect_mask({pos = vec2(sx, sy), size = vec2(pw, ph) * display.scale})
end

function Pool:draw_item_icon(item, x, y, size)
	lg.setColor(1, 1, 1, 1)
	local w, h = self.item_frame_width, self.item_frame_height
	lg.draw(assets.items, item.quad, x, y, 0, size / w, size / h, w / 2, h / 2)
end

local function icon_count(column, entry)
	local capacity = math.floor((column.width - 18) / icon_spacing)
	return #entry.items > capacity and capacity - 1 or #entry.items
end

local function icon_index(column, row_top, entry, position)
	local index = math.floor((position.x - column.x - 9) / icon_spacing) + 1
	if math.abs(position.y - row_top - 34) <= icon_size / 2 and index >= 1
		and index <= icon_count(column, entry)
	then
		return index
	end
end

function Pool:draw_upgrade_row(column, row, row_top)
	local entry = row.entry
	local fill = row.preview.hovered and tint.hover or entry.favorite and tint.favorite_row or tint.stripe
	box("fill", fill, column.x, row_top, column.width, row_height - 3, 5)
	text_at(entry.title, column.x + 9, row_top + 13, column.width - 158, 14,
		entry.favorite and tint.favorite or tint.ink)
	local shown = icon_count(column, entry)
	local hover_index = row.preview.hovered and icon_index(column, row_top, entry, row.preview.mouse_pos)
	for index = 1, shown do
		local x = column.x + 9 + (index - 0.5) * icon_spacing
		local item = entry.items[index]
		if index == hover_index then
			box("fill", tint.button, x - 11, row_top + 24, 22, 20, 4)
			self.hovered_item = {item = item, x = x, y = row_top + 34}
		end
		self:draw_item_icon(item, x, row_top + 34, icon_size)
	end
	if #entry.items > shown then
		text_at("+" .. (#entry.items - shown), column.x + 9 + shown * icon_spacing,
			row_top + 34, icon_spacing, 11, tint.muted, "center")
	end
	if row.star.hovered and row.star.available then
		self.hover_help = entry.favorite and words().unmark_favorite or words().mark_favorite
	elseif row.preview.hovered and shown > 0 then
		self.hover_help = words().open_contents
	end
end

function Pool:draw_panel()
	local L = words()
	local pw, ph = self.panel_width, self.panel_height
	local x, y = self.panel_x, self.panel_y
	self:draw_frame(L.pool)
	self.hovered_item = nil
	self.hover_help = nil

	local summary = L.balance:format(SAVE.stars) .. "     " .. L.slots:format(self.used_slots, self.slot_count)
	text_at(summary, x + 24, y + 64, pw - 312, 14, tint.muted)
	if self.pending_slots > 0 then
		text_at(L.pending_slots:format(self.pending_slots, self.pending_total), x + pw - 283, y + 64,
			260, 15, tint.favorite, "right")
	elseif self.change_allowed and self.next_cost > 0 then
		text_at(L.next_slot:format(self.next_cost), x + pw - 283, y + 64, 260, 14, tint.muted, "right")
	end

	for index, column in ipairs(self.columns) do
		local ink = index == 1 and tint.active or tint.banned
		local heading = index == 1 and L.active or L.banned
		local heading_width = index == 1 and column.width / 2 or column.width - 181
		local count = tostring(#column.entries)
		if #column.entries ~= #column.all_entries then count = count .. "/" .. #column.all_entries end
		text_at(heading .. " " .. count, column.x + 8, column.y - 16, heading_width, 17, ink)
		if index == 1 then
			draw_star(column.x + heading_width + 2, column.y - 16, self.favorite_count > 0, true)
			text_at(L.favorites .. " " .. self.favorite_count, column.x + heading_width + 15, column.y - 16,
				column.width - heading_width - 23, 14, tint.favorite)
		end
		for row_number, row in ipairs(column.rows) do
			if row.visible then
				self:draw_upgrade_row(column, row, column.y + (row_number - 1) * row_height)
			end
		end
		if #column.entries == 0 then
			local message = #column.all_entries > 0 and L.no_matches
				or index == 1 and L.empty_active or L.empty_banned
			text_at(message, column.x + 8, column.y + 31, column.width - 16, 14, tint.muted)
		elseif #column.entries > rows_per_column then
			local last = math.min(#column.entries, column.first + rows_per_column - 1)
			text_at(("%d–%d / %d"):format(column.first, last, #column.entries),
				column.x + 8, column.y + row_height * rows_per_column + 15,
				column.width - 82, 13, tint.muted)
		end
	end

	if not self.change_allowed then
		text_at(L.locked, x + 24, y + ph - 23, pw - 48, 13, tint.muted)
	elseif self.pending_total > SAVE.stars then
		text_at(L.shortage:format(self.pending_total - SAVE.stars), x + 24, y + ph - 23, pw - 48, 13, tint.banned)
	elseif self.hover_help then
		text_at(self.hover_help, x + 24, y + ph - 23, pw - 48, 13, tint.muted)
	elseif self.loaded_preset then
		text_at(L.preset_loaded:format(self.loaded_preset), x + 24, y + ph - 23, pw - 48, 13, tint.active, nil, "zh")
	elseif self.draft.changed then
		text_at(L.pending_note, x + 24, y + ph - 23, pw - 48, 13, tint.muted)
	end
end

function Pool:draw_icon_hover()
	local hover = self.hovered_item
	if not hover then return end
	local width = 224
	local tooltip = self:prepare_tooltip(hover.item, width)
	local half = math.max(20, tooltip.text.size.y + 16) / 2
	local x = math.clamp(hover.x, 154, self.width - 154)
	local y = hover.y - half - 20
	if y - half < 38 then y = hover.y + half + 38 end
	box("fill", tint.box, x - width / 2 - 7, y - half - 25, width + 14, half * 2 + 37, 6)
	self:draw_item_tooltip(tooltip, x, y)
end

local function set_entry(control, entry, available)
	if control.entry ~= entry then control.press_started = false end
	control.entry = entry
	control.visible = entry ~= nil
	control.available = control.visible and available
	control.suppress_sound = not control.available
end

local function row_focus(row, lane)
	if not row then return end
	if lane and row[lane] and row[lane].available then return row[lane] end
	if row.available then return row end
	if row.star.available then return row.star end
	if row.preview.available then return row.preview end
end

function Pool:layout_rows()
	self.discard_button.visible = self.draft.changed
	self.search_clear.visible = self.search_query ~= ""
	self.presets_button.available = self.change_allowed
	self.presets_button.suppress_sound = not self.change_allowed
	local presets = self.change_allowed and self.presets_button or nil
	for index, column in ipairs(self.columns) do
		local last_first = math.max(1, #column.entries - rows_per_column + 1)
		column.first = math.clamp(column.first, 1, last_first)
		column.previous.visible = #column.entries > rows_per_column
		column.following.visible = column.previous.visible
		column.previous.available = column.first > 1
		column.following.available = column.first < last_first
		column.previous.suppress_sound = not column.previous.available
		column.following.suppress_sound = not column.following.available

		for row_number, row in ipairs(column.rows) do
			local entry = column.entries[column.first + row_number - 1]
			set_entry(row, entry, entry and not entry.favorite and self.change_allowed)
			set_entry(row.star, entry, entry and self.change_allowed and self:is_purchased_upgrade(entry.key))
			set_entry(row.preview, entry, entry and #entry.items > 0)
			row.ink = index == 1 and tint.banned or tint.active
		end
	end

	for index, column in ipairs(self.columns) do
		local other = self.columns[3 - index]
		local last = math.min(rows_per_column, #column.entries)
		local other_last = math.min(rows_per_column, #other.entries)
		local header = index == 2 and (self.activate_button.available and self.activate_button or presets)
			or self.search_button
		for row_number = 1, last do
			local row = column.rows[row_number]
			local opposite = row_focus(other.rows[math.min(row_number, other_last)]) or self.search_button
			local previous = column.rows[row_number - 1]
			local following = row_number < last and column.rows[row_number + 1] or nil
			local page = column.following.available and column.following or column.previous.available and column.previous or nil
			row.nav_up = row_focus(previous) or header
			row.nav_down = row_focus(following) or page
			row.nav_left = row.star.available and row.star or row.preview.available and row.preview
				or index == 2 and opposite or nil
			row.nav_right = index == 1 and opposite or nil
			row.star.nav_up = row_focus(previous, "star") or header
			row.star.nav_down = row_focus(following, "star") or page
			row.star.nav_left = row.preview.available and row.preview or index == 2 and opposite or nil
			row.star.nav_right = row.available and row or index == 1 and opposite or nil
			row.preview.nav_up = row_focus(previous, "preview") or header
			row.preview.nav_down = row_focus(following, "preview") or page
			row.preview.nav_left = index == 2 and opposite or nil
			row.preview.nav_right = row.star.available and row.star or row.available and row or index == 1 and opposite or nil
		end
		column.previous.nav_up = row_focus(column.rows[last]) or self.search_button
		column.following.nav_up = column.previous.nav_up
		column.previous.nav_right = column.following.available and column.following or nil
		column.following.nav_left = column.previous.available and column.previous or nil
	end
	local first_active = row_focus(self.columns[1].rows[1])
	local first_banned = row_focus(self.columns[2].rows[1])
	local edit_bans = self.activate_button.available and self.activate_button or first_banned
	self.activate_button.nav_up = presets or self.search_button
	self.activate_button.nav_down = first_banned or first_active
	self.activate_button.nav_left = first_active or self.search_button
	self.close_button.nav_down = presets or self.search_clear.visible and self.search_clear or self.search_button
	self.close_button.nav_left = self.discard_button.visible and self.discard_button or self.search_button
	self.discard_button.nav_right = self.close_button
	self.discard_button.nav_down = self.search_button
	self.search_button.nav_up = self.discard_button.visible and self.discard_button or self.close_button
	self.search_button.nav_down = first_active or edit_bans
	self.search_button.nav_right = self.search_clear.visible and self.search_clear or presets or edit_bans
	self.search_clear.nav_up = self.close_button
	self.search_clear.nav_left = self.search_button
	self.search_clear.nav_down = edit_bans or first_active
	self.search_clear.nav_right = presets
	self.presets_button.nav_up = self.close_button
	self.presets_button.nav_down = edit_bans or first_active
	self.presets_button.nav_left = self.search_clear.visible and self.search_clear or self.search_button
end

function Pool:is_purchased_upgrade(key)
	local cfg = self.unlock_by_key[key]
	return cfg and key:starts_with("item") and SAVE:has_unlock(key)
		and not (DEMO and cfg.demo_lock) and not table.contains(cfg.required_unlocks or {}, "disabled")
end

function Pool:toggle_favorite(key)
	if not self.draft or self.confirmation or not SAVE:has_unlock("play_favs") or not self:is_purchased_upgrade(key) then return false end
	local favorites = self.draft.favorites
	if favorites:has(key) then
		favorites:remove(key)
	else
		favorites:add(key)
		self.draft.bans:remove(key)
		self.columns[1].first = 1
	end
	self:refresh()
	return true
end

function Pool:refresh()
	local bans = require("src.bans")
	local draft = self.draft
	local banned, favorites = draft.bans, draft.favorites
	self.loaded_preset = nil
	draft.changed = not (same_keys(banned, draft.saved_bans) and same_keys(favorites, draft.saved_favorites))
	local quote = self:quote_purchase()
	self.used_slots, self.slot_count = quote.used, quote.owned
	self.pending_slots, self.pending_total = quote.needed, quote.total
	self.next_cost = quote.used < quote.owned and 0 or slot_price(bans, quote.owned + quote.needed)
	self.change_allowed = SAVE:has_unlock("play_favs")
	self.favorite_count = 0
	local active_entries, banned_entries = {}, {}
	for _, cfg in ipairs(self.unlocks) do
		if self:is_purchased_upgrade(cfg.key) and not banned:has(cfg.key) then
			local marked = favorites:has(cfg.key)
			if marked then self.favorite_count = self.favorite_count + 1 end
			active_entries[#active_entries + 1] = {
				key = cfg.key, title = TS(cfg.title), items = self.items_by_key[cfg.key] or {}, favorite = marked,
			}
		end
	end
	-- Old profiles can contain retired keys. They still occupy a slot until restored.
	local can_activate_all = false
	for _, key in banned:ipairs() do
		local cfg = self.unlock_by_key[key]
		local title = cfg and TS(cfg.title) or key
		if self:is_purchased_upgrade(key) then can_activate_all = true end
		banned_entries[#banned_entries + 1] = {
			key = key, title = title, items = self.items_by_key[key] or {}, favorite = false,
		}
	end
	self.activate_button.available = self.change_allowed and can_activate_all
	self.activate_button.suppress_sound = not self.activate_button.available
	self.columns[1].all_entries = active_entries
	self.columns[2].all_entries = banned_entries
	for _, column in ipairs(self.columns) do
		for _, entry in ipairs(column.all_entries) do
			entry.sort_title = search_key(entry.title)
		end
		table.sort(column.all_entries, function(a, b)
			if a.favorite ~= b.favorite then return a.favorite end
			if a.sort_title == b.sort_title then return a.key < b.key end
			return a.sort_title < b.sort_title
		end)
	end
	self.cached_tooltip = nil
	self:filter_entries()
end

function Pool:filter_entries(reset_page)
	local query = search_key(self.search_query)
	local locale = require("locale").get_code()
	for _, column in ipairs(self.columns) do
		if query == "" then
			column.entries = column.all_entries
		else
			local filtered = {}
			for _, entry in ipairs(column.all_entries) do
				if matches_query(entry, query, locale) then filtered[#filtered + 1] = entry end
			end
			column.entries = filtered
		end
		if reset_page then column.first = 1 end
	end
	self:layout_rows()
end

local function input_line(text, capacity)
	text = text:gsub("%c", " ")
	if not utf8.len(text) then return end
	local limit = utf8.offset(text, capacity + 1)
	return limit and text:sub(1, limit - 1) or text
end

function Pool:set_search_query(query)
	query = input_line(query, 80)
	if not query or self.search_query == query then return end
	self.search_query = query
	self:filter_entries(true)
end

function Pool:focus_text(button)
	local current = self.text_input
	if current and current.button == button then return end
	if current then
		if love.textinput == current.callback then love.textinput = current.previous end
		love.keyboard.setTextInput(current.text_enabled)
		love.keyboard.setKeyRepeat(current.key_repeat)
		current.button.selected = false
		self.text_input = nil
	end
	if not button then return end
	local field = button.field
	local editing = {
		button = button, previous = love.textinput,
		text_enabled = love.keyboard.hasTextInput(), key_repeat = love.keyboard.hasKeyRepeat(),
		callback = function(text) field.set(field.get() .. text) end,
	}
	self.text_input = editing
	button.selected = true
	love.textinput = editing.callback
	love.keyboard.setTextInput(true)
	love.keyboard.setKeyRepeat(true)
end

function Pool:update_text_input(ui)
	local editing = self.text_input
	if not editing then return false end
	local field = editing.button.field
	if input.keyboard:just_pressed("escape") or (input.mode == "gamepad" and input.gamepad:just_pressed("b")) then
		self:focus_text()
		return true
	end
	if input.keyboard:just_pressed("return") or input.keyboard:just_pressed("kpenter") then
		self:focus_text()
		if field.submit then field.submit() end
		return true
	elseif input.keyboard:just_pressed("backspace") then
		local value = field.get()
		local last = utf8.offset(value, -1)
		if last then field.set(value:sub(1, last - 1)) end
	elseif love.keyboard.isDown("lctrl", "rctrl") and input.keyboard:just_pressed("v") then
		field.set(field.get() .. love.system.getClipboardText())
	elseif input:cursor_just_pressed(1) and not editing.button:mouse_over(ui:mouse_pos()) then
		self:focus_text()
	end
	return false
end

function Pool:add_text_field(kernel, x, y, width, height, field)
	local button = add_button(kernel, x, y, width, height, nil,
		function(control) self:focus_text(control) end, {
			content = function(control)
				local value = field.get()
				if control.selected then value = value .. "|" end
				local text = value == "" and field.hint() or value
				text_at(text, -control.halfsize.x + 10, 0, width - (field.inset or 20), 14,
					value == "" and tint.muted or tint.ink, nil, field.locale)
			end,
		})
	button.field = field
	return button
end

function Pool:page(column, amount)
	column.first = column.first + amount
	self:layout_rows()
end

local row_lanes = {"action", "star", "preview"}

function Pool:scroll_focused_row()
	if input.mode ~= "gamepad" then return false end
	local down = input.gamepad:just_pressed("dpdown")
	local up = input.gamepad:just_pressed("dpup")
	if not (down or up) then return false end
	local position = self.modal_ui:mouse_pos()
	for _, column in ipairs(self.columns) do
		local pager = down and column.following or column.previous
		if pager.available then
			local row = column.rows[down and rows_per_column or 1]
			for _, lane in ipairs(row_lanes) do
				local control = row[lane] or row
				if control.available and control:mouse_over(position) then
					self:page(column, down and 1 or -1)
					self.modal_ui:focus(row_focus(row, lane) or self.search_button)
					return true
				end
			end
		end
	end
	return false
end

function Pool:open_panel()
	if self.open or self.state.target or self.state.transition then return end
	local scroll = self.state.scroll
	if scroll then
		scroll.click_pos = nil
		scroll.drag:sset(0, 0)
	end
	self.open = true
	self.search_query = ""
	local bans = require("src.bans")
	self.draft = {saved_bans = bans:get(), saved_favorites = favorite_keys()}
	self:reset_draft()
	local first = self.columns[1].rows[1]
	self.modal_ui:focus(row_focus(first) or self.search_button)
	return true
end

function Pool:build_panel()
	local pw, ph = self.panel_width, self.panel_height
	local x, y = self.panel_x, self.panel_y
	local body = self.modal
	body:add({draw = function() self:draw_panel() end})
	self.close_button = add_button(body, x + pw - 115, y + 15, 92, 31,
		function() return self.draft.changed and words().apply or words().close end,
		function() self:request_apply() end)
	self.discard_button = add_button(body, x + pw - 291, y + 15, 166, 31,
		function() return words().discard end, function() self:reset_draft() end)
	self.close_button.ink = tint.active
	local presets_width, presets_gap = 123, 10
	local search_width = pw - 46 - presets_width - presets_gap
	self.search_button = self:add_text_field(body, x + 23, y + 83, search_width, 29, {
		get = function() return self.search_query end,
		set = function(query) self:set_search_query(query) end,
		hint = function() return words().search end, inset = 57,
	})
	self.search_clear = add_button(body, x + 23 + search_width - 31, y + 86, 25, 23,
		function() return "X" end,
		function()
			self:set_search_query("")
			self.modal_ui:focus(self.search_button)
		end)
	self.search_clear.order = self.search_button.order + 1
	self.presets_button = add_button(body, x + pw - 23 - presets_width, y + 83, presets_width, 29,
		function() return words().presets end, function() self:open_presets() end)
	self.activate_button = add_button(body, x + pw - 183, y + 115, 160, 26,
		function() return words().activate_all end, function() self:activate_all() end)
	self.activate_button.ink = tint.active

	local gap = 20
	local width = (pw - gap - 46) / 2
	for index = 1, 2 do
		local cx = x + 23 + (index - 1) * (width + gap)
		local cy = y + 144
		local column = {x = cx, y = cy, width = width, first = 1, rows = {}, entries = {}, all_entries = {}}
		self.columns[index] = column
		for row_number = 1, rows_per_column do
			local row_top = cy + (row_number - 1) * row_height
			local row = add_button(body, cx + width - 110, row_top + 3, 106, 21,
				function(button)
					if button.entry.favorite then return words().protected end
					if index == 2 then return words().restore end
					return words().ban
				end,
				function(button)
					if not button.entry or not button.available or not self:toggle_draft_ban(button.entry.key) then return end
					if input.mode == "gamepad" then
						local last = math.min(rows_per_column, #column.entries)
						self.modal_ui:focus(row_focus(column.rows[math.min(row_number, last)]) or self.close_button)
					end
				end)
			row.star = add_button(body, cx + width - 142, row_top + 3, 28, 21, nil,
				function(button)
					if not button.available then return end
					local key = button.entry.key
					if not self:toggle_favorite(key) or input.mode ~= "gamepad" then return end
					for _, visible in ipairs(self.columns[1].rows) do
						if visible.entry and visible.entry.key == key then
							self.modal_ui:focus(visible.star)
							return
						end
					end
					self.modal_ui:focus(row_focus(self.columns[1].rows[1]) or self.close_button)
				end, {
					content = function(button, enabled) draw_star(0, 0, button.entry.favorite, enabled) end,
				})
			row.preview = body:add_from_system("ui", {
				order = 230,
				click_type = "aabb",
				pos = vec2(cx + width / 2, row_top + (row_height - 3) / 2),
				halfsize = vec2(width / 2, (row_height - 3) / 2),
				nav_cursor_offset = vec2(-width / 2 + 20, -8),
				click = function(button)
					if button.available then
						self:inspect_upgrade(button, icon_index(column, row_top, button.entry, button.mouse_pos) or 1)
					end
				end,
			})
			row.visible = false
			row.star.visible = false
			row.preview.visible = false
			column.rows[row_number] = row
		end
		local page_y = cy + rows_per_column * row_height + 3
		column.previous = add_button(body, cx + width - 65, page_y, 27, 24,
			function() return "<" end, function() self:page(column, -rows_per_column) end)
		column.following = add_button(body, cx + width - 30, page_y, 27, 24,
			function() return ">" end, function() self:page(column, rows_per_column) end)
	end
end

function Pool:purchased_keys(keys, keep_unavailable)
	local purchased = set()
	for _, key in keys:ipairs() do
		if self:is_purchased_upgrade(key) then purchased:add(key) end
	end
	if keep_unavailable then
		for _, key in keep_unavailable:ipairs() do
			if not self:is_purchased_upgrade(key) then purchased:add(key) end
		end
	end
	return purchased
end

function Pool:open_presets()
	if not self.draft or not self.change_allowed or self.confirmation then return end
	self:focus_text()
	self.modal_ui:focus(nil)
	local purchased = 0
	for _, cfg in ipairs(self.unlocks) do
		if self:is_purchased_upgrade(cfg.key) then purchased = purchased + 1 end
	end
	self.presets = {entries = read_presets(), name = "", first = 1, purchased = purchased}
	self:layout_presets()
	self.presets_ui:focus(self.preset_rows[1].load.visible and self.preset_rows[1].load or self.preset_name)
end

function Pool:leave_presets()
	self:focus_text()
	self.presets = nil
	self.presets_ui:focus(nil)
	self.modal_ui:focus(self.presets_button)
end

function Pool:set_preset_name(name)
	name = input_line(name, 64)
	if not name then return end
	self.presets.name = name
	self.presets.message = nil
	self:layout_presets()
end

function Pool:save_preset(preset)
	local menu = self.presets
	if not menu or not SAVE:has_unlock("play_favs") then return end
	if not preset then
		local name = menu.name:trim()
		if name == "" then return end
		local normalized = search_key(name)
		for _, entry in ipairs(menu.entries) do
			if search_key(entry.name) == normalized then
				menu.message = words().duplicate_preset
				return
			end
		end
		preset = {name = name}
		menu.entries[#menu.entries + 1] = preset
		menu.first = 1 + math.floor((#menu.entries - 1) / presets_per_page) * presets_per_page
		menu.name = ""
	end
	preset.bans = self:purchased_keys(self.draft.bans)
	preset.favorites = self:purchased_keys(self.draft.favorites)
	write_presets(menu.entries)
	menu.message = words().preset_saved:format(preset.name)
	self:layout_presets()
	if input.mode == "gamepad" then
		for _, row in ipairs(self.preset_rows) do
			if row.load.entry == preset then
				self.presets_ui:focus(row.load)
				break
			end
		end
	end
end

function Pool:load_preset(preset)
	if not self.presets or not preset or not SAVE:has_unlock("play_favs") then return end
	local draft = self.draft
	-- Keep retired keys in the draft so players can still restore them manually.
	draft.bans = self:purchased_keys(preset.bans, draft.bans)
	draft.favorites = self:purchased_keys(preset.favorites, draft.favorites)
	remove_favorite_bans(draft.bans, draft.favorites)
	self:leave_presets()
	self.search_query = ""
	for _, column in ipairs(self.columns) do column.first = 1 end
	self:refresh()
	self.loaded_preset = preset.name
end

function Pool:layout_presets()
	local menu = self.presets
	local count = #menu.entries
	local last = math.min(presets_per_page, count - menu.first + 1)
	local previous, following = self.preset_previous, self.preset_next
	previous.visible, following.visible = count > presets_per_page, count > presets_per_page
	previous.available = menu.first > 1
	following.available = menu.first + presets_per_page <= count
	previous.suppress_sound = not previous.available
	following.suppress_sound = not following.available
	previous.nav_right = following.available and following or nil
	following.nav_left = previous.available and previous or nil
	local page = following.available and following or previous.available and previous or nil

	self.preset_save.available = menu.name:trim() ~= ""
	self.preset_save.suppress_sound = not self.preset_save.available
	local save = self.preset_save.available and self.preset_save or nil
	for index, row in ipairs(self.preset_rows) do
		local entry = menu.entries[menu.first + index - 1]
		set_entry(row.load, entry, true)
		set_entry(row.overwrite, entry, true)
		if entry then
			local banned = self:purchased_keys(entry.bans)
			local favorites = self:purchased_keys(entry.favorites)
			remove_favorite_bans(banned, favorites)
			row.banned_count = banned:size()
			row.favorite_count = favorites:size()
		end
		local above, below = self.preset_rows[index - 1], index < last and self.preset_rows[index + 1] or nil
		row.load.nav_up = above and above.load or self.preset_name
		row.overwrite.nav_up = above and above.overwrite or save or self.preset_name
		row.load.nav_down = below and below.load or page
		row.overwrite.nav_down = below and below.overwrite or page
	end
	local first = last > 0 and self.preset_rows[1] or nil
	local bottom = last > 0 and self.preset_rows[last] or nil
	previous.nav_up = bottom and bottom.load or nil
	following.nav_up = bottom and bottom.overwrite or nil
	self.preset_name.nav_right = save or self.presets_back
	self.preset_name.nav_down = first and first.load or nil
	self.presets_back.nav_down = save or self.preset_name
	self.presets_back.nav_left = self.preset_name
	self.preset_save.nav_down = first and first.overwrite or nil
end

function Pool:page_presets(direction)
	local menu = self.presets
	local last_page = math.max(0, math.floor((#menu.entries - 1) / presets_per_page))
	local page = math.floor((menu.first - 1) / presets_per_page)
	local first = 1 + math.clamp(page + direction, 0, last_page) * presets_per_page
	if first == menu.first then return end
	menu.first = first
	self:layout_presets()
	if input.mode == "gamepad" then
		local pager = direction > 0 and self.preset_next or self.preset_previous
		if not pager.available then
			self.presets_ui:focus(direction > 0 and self.preset_previous or self.preset_next)
		end
	end
end

function Pool:draw_presets()
	local L, menu = words(), self.presets
	local x, y = self.panel_x + 23, self.panel_y
	local width, height = self.panel_width - 46, self.panel_height
	self:draw_frame(L.presets)
	for index, row in ipairs(self.preset_rows) do
		local entry = row.load.entry
		if entry then
			local top = y + 106 + (index - 1) * row_height
			box("fill", tint.stripe, x, top, width, row_height - 4, 6)
			text_at(entry.name, x + 12, top + 12, width - 267, 15, tint.ink, nil, "zh")
			local counts = ("%s %d    %s %d    %s %d"):format(
				L.favorites, row.favorite_count, L.active, menu.purchased - row.banned_count, L.banned, row.banned_count)
			text_at(counts, x + 12, top + 32, width - 267, 13, tint.muted)
		end
	end
	local count = #menu.entries
	if count == 0 then
		text_at(L.empty_presets, x, y + height / 2, width, 18, tint.muted, "center")
	elseif count > presets_per_page then
		local last = math.min(count, menu.first + presets_per_page - 1)
		text_at(("%d-%d / %d"):format(menu.first, last, count),
			x, y + height - 80, width - 84, 13, tint.muted, "right")
	end
	if menu.message then
		text_at(menu.message, x, y + height - 54, width, 14, tint.ink, nil, "zh")
	end
	text_at(L.preset_hint, x, y + height - 23, width, 13, tint.muted)
end

function Pool:build_presets()
	local body = self.presets_menu
	local x, y = self.panel_x + 23, self.panel_y
	local width, height = self.panel_width - 46, self.panel_height
	body:add({draw = function() self:draw_presets() end})
	self.presets_back = add_button(body, x + width - 123, y + 15, 123, 31,
		function() return words().back_to_pool end, function() self:leave_presets() end, {key = "escape", gamepad = "b"})
	self.preset_name = self:add_text_field(body, x, y + 58, width - 175, 33, {
		get = function() return self.presets.name end,
		set = function(name) self:set_preset_name(name) end,
		hint = function() return words().preset_name end, locale = "zh",
		submit = function() self:save_preset() end,
	})
	self.preset_save = add_button(body, x + width - 165, y + 58, 165, 33,
		function() return words().save_new end, function() self:save_preset() end)
	self.preset_save.ink = tint.active
	self.preset_save.nav_left = self.preset_name
	self.preset_save.nav_up = self.presets_back
	self.preset_name.nav_up = self.presets_back

	for index = 1, presets_per_page do
		local top = y + 106 + (index - 1) * row_height
		local load = add_button(body, x + width - 255, top + 6, 103, 30,
			function() return words().load_preset end, function(button) self:load_preset(button.entry) end)
		load.ink = tint.active
		local overwrite = add_button(body, x + width - 144, top + 6, 138, 30,
			function() return words().overwrite end, function(button)
				if not button.entry then return end
				self.previous_focus = button
				self:show_confirmation({overwrite = button.entry})
			end)
		load.nav_right = overwrite
		overwrite.nav_left = load
		self.preset_rows[index] = {load = load, overwrite = overwrite}
	end
	local page_y = y + height - 92
	self.preset_previous = add_button(body, x + width - 66, page_y, 27, 24,
		function() return "<" end, function() self:page_presets(-1) end)
	self.preset_next = add_button(body, x + width - 31, page_y, 27, 24,
		function() return ">" end, function() self:page_presets(1) end)
end

function Pool:select_inspected_item(item)
	if not self.inspection or not item then return end
	self.inspection.item = item
	for _, tile in ipairs(self.detail_tiles) do tile.selected = tile.entry == item end
end

function Pool:layout_details()
	local inspection = self.inspection
	local items = inspection.entry.items
	local last = math.min(items_per_page, #items - inspection.first + 1)
	for index, tile in ipairs(self.detail_tiles) do
		set_entry(tile, items[inspection.first + index - 1], true)
		local horizontal = (index - 1) % detail_columns
		tile.nav_up = self.detail_tiles[index - detail_columns] or self.details_back
		tile.nav_down = index + detail_columns <= last and self.detail_tiles[index + detail_columns]
			or #items > items_per_page and self.detail_next or nil
		tile.nav_left = horizontal > 0 and self.detail_tiles[index - 1] or nil
		tile.nav_right = horizontal < detail_columns - 1 and index < last and self.detail_tiles[index + 1] or nil
	end
	self.details_back.nav_down = self.detail_tiles[1]
	self.detail_previous.nav_up = self.detail_tiles[last]
	self.detail_next.nav_up = self.detail_tiles[last]
	self.detail_previous.nav_right = self.detail_next
	self.detail_next.nav_left = self.detail_previous
	self.detail_previous.visible = #items > items_per_page
	self.detail_next.visible = self.detail_previous.visible
	self.detail_previous.available = inspection.first > 1
	self.detail_next.available = inspection.first + items_per_page <= #items
	self.detail_previous.suppress_sound = not self.detail_previous.available
	self.detail_next.suppress_sound = not self.detail_next.available
	self:select_inspected_item(inspection.item)
end

function Pool:inspect_upgrade(button, index)
	if not self.draft or self.confirmation then return end
	self:focus_text()
	local entry = button.entry
	self.inspection = {
		entry = entry, return_to = button, item = entry.items[index],
		first = 1 + math.floor((index - 1) / items_per_page) * items_per_page,
		open_cursor = input:cursor():copy(),
	}
	self:layout_details()
	self.details_ui:focus(self.detail_tiles[(index - 1) % items_per_page + 1])
end

function Pool:leave_details()
	local return_to = self.inspection.return_to
	self.inspection = nil
	self.details_ui:focus(nil)
	self.modal_ui:focus(return_to)
end

function Pool:page_details(direction)
	local inspection = self.inspection
	local items = inspection.entry.items
	local last_page = math.floor((#items - 1) / items_per_page)
	local page = math.floor((inspection.first - 1) / items_per_page)
	local first = math.clamp(page + direction, 0, last_page) * items_per_page + 1
	if first == inspection.first then return end
	inspection.first = first
	inspection.item = items[first]
	self:layout_details()
end

function Pool:draw_details()
	local inspection = self.inspection
	local x, y = self.panel_x, self.panel_y
	local pw, ph = self.panel_width, self.panel_height
	self:draw_frame(inspection.entry.title)
	local config = self.unlock_by_key[inspection.entry.key]
	if config and config.description and config.description ~= "todo" then
		text_at(TS(config.description), x + 23, y + 67, pw - 46, 14, tint.muted)
	end

	local item = inspection.item
	local cx = x + pw - 23 - 158
	box("fill", tint.stripe, cx - 158, y + 98, 316, ph - 121, 8)
	self:draw_item_icon(item, cx, y + 162, 78)
	self:draw_item_tooltip(self:prepare_tooltip(item, 275), cx, y + 285)

	local count = #inspection.entry.items
	if count > items_per_page then
		text_at(("%d–%d / %d"):format(inspection.first, math.min(inspection.first + items_per_page - 1, count), count),
			x + 23, y + ph - 22, 146, 13, tint.muted)
	end
end

function Pool:build_details()
	local body = self.details
	local x, y = self.panel_x, self.panel_y
	local pw, ph = self.panel_width, self.panel_height
	body:add({draw = function() self:draw_details() end})
	self.details_back = add_button(body, x + pw - 146, y + 15, 123, 31,
		function() return words().back_to_pool end, function() self:leave_details() end, {key = "escape", gamepad = "b"})
	local gap, tile_height = 7, 78
	local grid_width = pw - 46 - 316 - 18
	local tile_width = (grid_width - (detail_columns - 1) * gap) / detail_columns
	for index = 1, items_per_page do
		local column = (index - 1) % detail_columns
		local row = math.floor((index - 1) / detail_columns)
		local function select_item(button) self:select_inspected_item(button.entry) end
		local tile = add_button(body, x + 23 + column * (tile_width + gap), y + 98 + row * (tile_height + gap),
			tile_width, tile_height, nil, select_item, {
				hover = function(button)
					if self.inspection and self.inspection.open_cursor:distance_squared(input:cursor()) > 4 then
						select_item(button)
					end
				end,
				content = function(button, _, ink)
					self:draw_item_icon(button.entry, 0, -8, 46)
					text_at(TS(button.entry.config.name), -tile_width / 2 + 4, 27, tile_width - 8, 11, ink, "center")
				end,
			})
		tile.visible = false
		self.detail_tiles[index] = tile
	end
	local page_x, page_y = x + 23 + grid_width - 62, y + ph - 31
	self.detail_previous = add_button(body, page_x, page_y, 27, 22,
		function() return "<" end, function() self:page_details(-1) end)
	self.detail_next = add_button(body, page_x + 35, page_y, 27, 22,
		function() return ">" end, function() self:page_details(1) end)
end

function Pool:index_items()
	local atlas_width, atlas_height = assets.items:getDimensions()
	local frame_width, frame_height = atlas_width / 10, atlas_height / 28
	self.item_frame_width, self.item_frame_height = frame_width, frame_height
	for id, config in pairs(require("src.items")) do
		local unlocks = config.required_unlocks
		if config.frame and unlocks and not config.bad_item and not table.contains(unlocks, "disabled") then
			local item
			for _, key in ipairs(unlocks) do
				if self.unlock_by_key[key] then
					if not item then
						local frame = config.frame
						item = {
							id = id, config = config, order = frame.y * 10 + frame.x,
							quad = lg.newQuad(frame.x * frame_width, frame.y * frame_height,
								frame_width, frame_height, atlas_width, atlas_height),
						}
					end
					local items = self.items_by_key[key] or {}
					items[#items + 1] = item
					self.items_by_key[key] = items
				end
			end
		end
	end
	for _, items in pairs(self.items_by_key) do
		table.sort(items, function(a, b)
			if a.order == b.order then return a.id < b.id end
			return a.order < b.order
		end)
	end
end

function Pool:set_zoom(zoom, pivot)
	zoom = math.clamp(zoom, 0.55, 1.8)
	if not self.buttons or zoom == self.zoom then return end
	local ratio = zoom / self.zoom
	local function transform(position)
		position:vsubi(pivot):smuli(ratio):vaddi(pivot)
	end
	for _, button in ipairs(self.buttons) do transform(button.pos) end
	for _, particle in ipairs(self.connections.particles or {}) do
		if not particle.destroyed then
			transform(particle.particle.pos)
			if not rawequal(particle.sprite.pos, particle.particle.pos) then transform(particle.sprite.pos) end
		end
	end
	self.zoom = zoom
	self.connections.zoom = zoom
	self.connections.frametimer = self.connections.frametime
	lg.push("all")
	for _, canvas in ipairs({self.connections.prev, self.connections.composite}) do
		lg.setCanvas(canvas)
		lg.clear(0, 0, 0, 0)
	end
	lg.pop()

	local scroll = self.state.scroll
	scroll.zoom_selection = self.info_box.selection
	scroll.click_pos = nil
	scroll.drag:sset(0, 0)
end

function Pool:reset_zoom()
	if not self.buttons then return end
	self:set_zoom(1, self.pivot)
	local scroll = self.state.scroll
	local offset = self.initial_anchor:vsub(self.buttons[1].pos)
	if offset:length_squared() > 0.01 then scroll:do_offset(offset) end
	scroll.zoom_selection = self.info_box.selection
	scroll.click_pos = nil
	scroll.drag:sset(0, 0)
end

function Pool:bind_tree(buttons, connection_rendering)
	self.buttons = buttons
	self.connections = connection_rendering
	self.initial_anchor = buttons[1].pos:copy()
	for _, button in ipairs(buttons) do
		local draw, click = button.draw, button.click
		function button:draw()
			lg.scale(self.pool.zoom)
			draw(self)
		end
		function button:mouse_over(position)
			return self.enabled and intersect.circle_point_overlap(self.pos, self.radius * self.pool.zoom, position)
		end
		function button:click()
			self.pool.state.scroll.zoom_selection = nil
			click(self)
		end
		button.pool = self
	end
end

function Pool:update(dt)
	if self.confirmation then
		self.confirm_menu:update(dt)
		return true
	end
	local scroll = input.mouse.scroll.y
	if self.presets then
		if self:update_text_input(self.presets_ui) then return true end
		if scroll ~= 0 and input.mode == "desktop" then self:page_presets(scroll > 0 and -1 or 1) end
		self.presets_menu:update(dt)
		return true
	end
	if self.inspection then
		if scroll ~= 0 and input.mode == "desktop" then self:page_details(scroll > 0 and -1 or 1) end
		self.details:update(dt)
		return true
	end
	if self.open then
		if love.keyboard.isDown("lctrl", "rctrl") and input.keyboard:just_pressed("f") then
			self:focus_text(self.search_button)
		end
		if self:update_text_input(self.modal_ui) then return true end
		if input.keyboard:just_pressed("escape") or (input.mode == "gamepad" and input.gamepad:just_pressed("b")) then
			self:request_close()
			return true
		end
		if self:scroll_focused_row() then return true end
	end
	if scroll ~= 0 and input.mode == "desktop" then
		self.state.camera:check_display()
		local pos = self.state.camera:screen_to_ui(input:cursor())
		if self.open then
			for _, column in ipairs(self.columns) do
				if pos.x >= column.x and pos.x < column.x + column.width
					and pos.y >= column.y and pos.y < column.y + row_height * rows_per_column + 30
				then
					self:page(column, scroll > 0 and -3 or 3)
				end
			end
		elseif pos.x >= 0 and pos.x < self.info_box.pos.x - self.info_box.halfsize.x
			and pos.y >= 0 and pos.y <= self.height
		then
			self:set_zoom(self.zoom * 1.16 ^ scroll, pos)
		end
	end
	if self.open then
		self.modal:update(dt)
		return true
	end
	return false
end

local function menu_kernel(camera)
	local ui = require("src.systems.ui")({camera = camera})
	-- The game's UI pass has already applied the display scale when the modal draws.
	ui.draw = false
	local kernel = soup.kernel():add_system("ui", ui)
	kernel:add(require("src.gamepad_cursor")())
	return kernel, ui
end

local function copy_canvas(source, target)
	lg.push("all")
	lg.origin()
	lg.setCanvas(target)
	lg.setScissor()
	lg.setShader()
	lg.setColor(1, 1, 1, 1)
	lg.setBlendMode("replace", "premultiplied")
	lg.draw(source)
	lg.pop()
end

function Pool:capture_background()
	local w, h = display:dimensions()
	local background = self.background
	if not background or background.width ~= w or background.height ~= h then
		background = {width = w, height = h, world = lg.newCanvas(w, h), ui = lg.newCanvas(w, h)}
		self.background = background
	end
	copy_canvas(display.current_frame, background.world)
	copy_canvas(display.ui_frame, background.ui)
	background.source = display.ui_frame
end

function Pool:draw_overlay()
	if self.confirmation then
		self.confirm_menu:draw()
	elseif self.presets then
		self.presets_menu:draw()
	elseif self.inspection then
		self.details:draw()
	else
		self.modal:draw()
		self:draw_icon_hover()
	end
end

function Pool:draw_cached_background()
	local background = self.background
	if not self.open or not background or background.source ~= display.ui_frame then return false end
	self.state.camera:check_display()
	copy_canvas(background.world, display.current_frame)
	display:start_ui()
	copy_canvas(background.ui, display.ui_frame)
	lg.scale(display.scale)
	self:draw_overlay()
	return true
end

function Pool.new(state, info_box, unlocks)
	local w, h = display:dimensions_scaled()
	local pw, ph = math.min(w - 44, 864), math.min(h - 36, 486)
	local self = setmetatable({
		state = state, info_box = info_box, unlocks = unlocks, unlock_by_key = {}, items_by_key = {},
		width = w, height = h, panel_width = pw, panel_height = ph,
		panel_x = (w - pw) / 2, panel_y = (h - ph) / 2,
		columns = {}, detail_tiles = {}, preset_rows = {}, zoom = 1, pivot = vec2(w * 0.33, h * 0.5),
	}, Pool)
	for _, cfg in ipairs(unlocks) do self.unlock_by_key[cfg.key] = cfg end
	self:index_items()
	local ok, tooltip_drawer = pcall(cached_tooltip_drawer)
	if not ok then
		print("Star Guts Pool tooltip cache skipped: " .. tostring(tooltip_drawer))
		tooltip_drawer = require("src.ui.item_hover").draw
	end
	self.tooltip_drawer = tooltip_drawer

	self.modal, self.modal_ui = menu_kernel(state.camera)
	self.details, self.details_ui = menu_kernel(state.camera)
	self.presets_menu, self.presets_ui = menu_kernel(state.camera)
	self.confirm_menu, self.confirm_ui = menu_kernel(state.camera)
	self:build_panel()
	self:build_details()
	self:build_presets()
	self:build_confirmation()

	local top = info_box.pos.y - info_box.halfsize.y - 42
	add_button(state.k, info_box.pos.x - 92, top, 184, 30,
		function() return words().pool end, function() self:open_panel() end, {gamepad = "x", font = 16})
	local zx, zy = w * 0.33 - 59, h * 0.90 - 14
	add_button(state.k, zx, zy, 29, 28, function() return "-" end,
		function() self:set_zoom(self.zoom / 1.16, self.pivot) end, {font = 18})
	add_button(state.k, zx + 33, zy, 52, 28, function() return ("%d%%"):format(math.floor(self.zoom * 100 + 0.5)) end,
		function() self:reset_zoom() end)
	add_button(state.k, zx + 89, zy, 29, 28, function() return "+" end,
		function() self:set_zoom(self.zoom * 1.16, self.pivot) end, {font = 18})
	state.k:add_from_system("ui", {
		order = 350,
		draw = function()
			if self.open then
				self:capture_background()
				self:draw_overlay()
			end
		end,
	})
	return self
end

local function attach_to_screen(source)
	local function patch(marker, replacement)
		source = patch_once(source, marker, replacement)
	end
	local unlocks = '\tlocal item_unlocks = require("src.item_unlocks")'
	patch(unlocks, unlocks .. '\n\tself.star_guts_pool = star_guts_pool.new(self, info_box, item_unlocks)')

	patch([[
			local bans = require("src.bans")
			if self:banned() then
				bans:remove(s.key)
			elseif bans:free_slot() or bans:buy_slot() then
				bans:add(s.key)
			end]], [[
			state.star_guts_pool:toggle_tree_ban(s.key)]])
	local banned_label = "local banned = self:banned()"
	patch(banned_label, [[if info_box.selection and star_guts_pool.is_favorite(info_box.selection.key) then
				star_guts_pool.draw_favorite_label(self)
				return
			end
			]] .. banned_label)

	patch('lg.circle("fill", a.x, a.y, rad)', 'lg.circle("fill", a.x, a.y, rad * (self.zoom or 1))')
	patch('lg.circle("fill", p.x, p.y, rad)', 'lg.circle("fill", p.x, p.y, rad * (self.zoom or 1))')
	patch('lg.circle("fill", p.x, p.y, traveler.rad)', 'lg.circle("fill", p.x, p.y, traveler.rad * (self.zoom or 1))')
	patch('local hover = info_box.selection', 'local hover = info_box.selection ~= self.zoom_selection and info_box.selection')
	patch('\t\t\t\t\tif input:cursor_pressed(1) then',
		'\t\t\t\t\tif input:cursor_pressed(1) and (self.click_pos or self.hovered and input:cursor_just_pressed(1)) then')

	patch('\n\t\t})\n\tend)\nend\n\nfunction state:update(dt)\n\tself.k:update(dt)', [[

		})
		self.star_guts_pool:bind_tree(buttons, connection_rendering)
	end)
end

function state:exit()
	if self.star_guts_pool then
		self.star_guts_pool:close()
		self.star_guts_pool.background = nil
	end
end

function state:update(dt)
	if not self.transition and self.star_guts_pool and self.star_guts_pool:update(dt) then return end
	self.k:update(dt)]])
	patch("function state:draw()\n\tself.camera:push()", [[
function state:draw()
	if self.star_guts_pool and self.star_guts_pool:draw_cached_background() then return end
	self.camera:push()]])
	return assert(loadstring("local star_guts_pool = ...\n" .. source, "@" .. screen_path))
end

local source = original_file(screen_path)
if BUILD_ID == supported_build then
	local ok, patched = pcall(attach_to_screen, (source:gsub("\r\n", "\n")))
	if ok then
		local state = patched(Pool)
		local favorites = favorite_keys()
		if favorites:size() > 0 then
			local bans = require("src.bans")
			local banned = bans:get()
			if remove_favorite_bans(banned, favorites) then bans:_store(banned:to_table()) end
		end
		print("Star Guts Pool enabled for " .. BUILD_ID)
		return state
	end
	print("Star Guts Pool skipped: " .. tostring(patched))
else
	print("Star Guts Pool uses the original screen for build " .. tostring(BUILD_ID))
end
return assert(loadstring(source, "@" .. screen_path))()
