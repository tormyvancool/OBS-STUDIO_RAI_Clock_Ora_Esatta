--[=[
@file RAI-Clock-Ora-Esatta.lua
@brief Custom OBS Studio video source rendering the late-1970s RAI analog clock ("Ora Esatta").
@author Tormy Van Cool
@copyright Copyright (c) 2026 Tormy Van Cool
@license Creative Commons Attribution-NoDerivatives 4.0 International (CC BY-ND 4.0)
         https://creativecommons.org
         You are free to share and use this script for any purpose, provided you give
         appropriate credit. You may not distribute modified versions of this script.
@version 1.0.2

@details
Registers a custom 1920x1440 OBS source ("Lua RAI Clock") that composites four PNG layers
(dial, hour hand, minute hand, and second hand) and rotates the hands in real time based
on the local system clock. The second hand sweeps continuously (sub-second precision is
obtained by combining the system clock with OBS's high-resolution timer, see `smooth_time`).

Optional vocal announcement (configured in the source's properties: double-click the source):
- Two drop-downs select the hour (00-23) and the minute (00-59) of the announcement.
- 6 seconds before that time, `Beep.wav` is played once. It is a single pre-mixed 6-second file
  that already contains the whole beep pattern and ends exactly at the announcement time.
- At the selected time, `hXX.wav` is played (e.g. `h13.wav`). If the minute is not 0,
  `mXX.wav` (e.g. `m12.wav`) is played immediately after it.
- It repeats every day at the selected time.

@requires
- OBS Studio with LuaJIT scripting support (`obslua`, `bit`)
- Subfolder `RAI-Clock-Ora-Esatta/` in the same directory as this script containing:
  * `RAI-Clock-Ora-Esatta.lua` (this script)
  * `Images/` subfolder with the four PNG layers:
  * `RAI-Clock-Dial.png`
  * `RAI-Clock-Hours.png`
  * `RAI-Clock-Minutes.png`
  * `RAI-Clock-Seconds.png`
  * `Audio/` subfolder with the audio files:
  * `Beep.wav`
  * `h00.wav` ... `h23.wav`
  * `m01.wav` ... `m59.wav`
]=]

obs = obslua
bit = require("bit")

--- OBS source definition table for the RAI analog clock.
source_def = {}
source_def.id = "lua_RAI_clock_Ora_Esatta"
source_def.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO, obs.OBS_SOURCE_CUSTOM_DRAW)

--- Loads an image file into an OBS graphics texture.
--- Safely frees any existing texture before initializing the new image file.
--- @param image userdata An `obs.gs_image_file_ex()` structure.
--- @param file string Full file path to the PNG asset.
function image_source_load(image, file)
	obs.obs_enter_graphics();
	obs.gs_image_file_ex_free(image);
	obs.obs_leave_graphics();

	obs.gs_image_file_ex_init(image, file, obs.GS_IMAGE_ALPHA_STRAIGHT);

	obs.obs_enter_graphics();
	obs.gs_image_file_ex_init_texture(image);
	obs.obs_leave_graphics();

	if not image.loaded then
		print("failed to load texture " .. file);
	end
end

--- Returns the display name shown in OBS's "Add Source" menu.
--- @return string
source_def.get_name = function()
	return "RAI Clock \"Ora Esatta\" with Audio Announcement"
end

--- Initializes the source instance and loads all four clock layer textures.
--- @param settings userdata OBS source settings data (OBS passes settings first, then the source).
--- @param source userdata The OBS source object.
--- @return table data Table holding the initialized `gs_image_file_ex` textures.
source_def.create = function(settings, source)
	local data = {}
	data.image = obs.gs_image_file_ex()
	data.hour_image = obs.gs_image_file_ex()
	data.minute_image = obs.gs_image_file_ex()
	data.second_image = obs.gs_image_file_ex()

	image_source_load(data.image, script_path() .. "Images/RAI-Clock-Dial.png")
	image_source_load(data.hour_image, script_path() .. "Images/RAI-Clock-Hours.png")
	image_source_load(data.minute_image, script_path() .. "Images/RAI-Clock-Minutes.png")
	image_source_load(data.second_image, script_path() .. "Images/RAI-Clock-Seconds.png")

	ann.instances = ann.instances + 1
	ann_apply_settings(settings)

	return data
end

--- Frees all graphics textures when the source is removed or OBS shuts down.
--- @param data table Source instance data returned by `source_def.create`.
source_def.destroy = function(data)
	obs.obs_enter_graphics();
	obs.gs_image_file_ex_free(data.image);
	obs.gs_image_file_ex_free(data.hour_image);
	obs.gs_image_file_ex_free(data.minute_image);
	obs.gs_image_file_ex_free(data.second_image);
	obs.obs_leave_graphics();

	ann.instances = math.max(0, ann.instances - 1)
	if ann.instances == 0 then
		ann.enabled = false
	end
end

--- Default values of the source's properties.
--- @param settings userdata
source_def.get_defaults = function(settings)
	obs.obs_data_set_default_bool(settings, "ann_enabled", true)
	obs.obs_data_set_default_int(settings, "ann_hour", 12)
	obs.obs_data_set_default_int(settings, "ann_minute", 0)
end

--- Builds the source's properties dialog (hour and minute drop-downs).
--- @param data table Source instance data.
--- @return userdata
source_def.get_properties = function(data)
	local props = obs.obs_properties_create()

	obs.obs_properties_add_bool(props, "ann_enabled", "Enable vocal announcement")

	local ph = obs.obs_properties_add_list(props, "ann_hour", "Announcement hour",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	for h = 0, 23 do
		obs.obs_property_list_add_int(ph, string.format("%02d", h), h)
	end

	local pm = obs.obs_properties_add_list(props, "ann_minute", "Announcement minute",
		obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	for m = 0, 59 do
		obs.obs_property_list_add_int(pm, string.format("%02d", m), m)
	end

	obs.obs_properties_add_button(props, "ann_test", "Test now (starts in 8 seconds)", ann_test_clicked)

	return props
end

--- Called when the user changes the source's properties.
--- @param data table Source instance data.
--- @param settings userdata
source_def.update = function(data, settings)
	ann_apply_settings(settings)
end

--- State used by `smooth_time` to interpolate between whole seconds.
clk = { origin_ns = nil, offset = nil, last_sec = nil }

--- Returns the current local time in epoch seconds with a fractional part.
--- `os.time()` only has 1 s resolution, so the exact instant at which it changes is detected
--- and the OBS high-resolution timer (`obs.os_gettime_ns`) is used to interpolate in between.
--- Until the first second change is seen, the plain integer time is returned.
--- @return number
function smooth_time()
	local sec = os.time()
	if not obs.os_gettime_ns then
		return sec
	end

	local t_ns = obs.os_gettime_ns()
	if not clk.origin_ns then
		clk.origin_ns = t_ns
	end
	local t = (t_ns - clk.origin_ns) / 1e9

	if clk.last_sec == nil then
		clk.last_sec = sec
	elseif sec ~= clk.last_sec then
		clk.last_sec = sec
		-- A change is detected at most one frame late, so the best estimate is the largest
		-- candidate. The small decay lets it follow tiny clock drifts; a big gap means the
		-- system clock was changed, so resynchronise.
		local candidate = sec - t
		if clk.offset == nil or math.abs(candidate - clk.offset) > 0.5 then
			clk.offset = candidate
		else
			clk.offset = math.max(candidate, clk.offset - 0.001)
		end
	end

	if clk.offset == nil then
		return sec
	end
	return t + clk.offset
end

--- Renders the clock dial and rotates each hand around the center pivot (960, 720).
--- @param data table Source instance data containing loaded textures.
--- @param effect userdata Active OBS graphics effect.
source_def.video_render = function(data, effect)
	if not data.image.texture then
		return;
	end

	local now = smooth_time()
	local whole = math.floor(now)
	local time = os.date("*t", whole)
	local seconds = time.sec + (now - whole)
	local mins = time.min + seconds / 60.0;
	local hours = time.hour + mins / 60.0;

	effect = obs.obs_get_base_effect(obs.OBS_EFFECT_DEFAULT)

	obs.gs_blend_state_push()
	obs.gs_reset_blend_state()

	while obs.gs_effect_loop(effect, "Draw") do
		obs.obs_source_draw(data.image.texture, 0, 0, data.image.cx, data.image.cy, false);
	end

	obs.gs_matrix_push()
	obs.gs_matrix_translate3f(960, 720, 0)
	obs.gs_matrix_rotaa4f(0.0, 0.0, 1.0, 2 * math.pi / 60 * mins);
	obs.gs_matrix_translate3f(-960, -720, 0)

	while obs.gs_effect_loop(effect, "Draw") do
		obs.obs_source_draw(data.minute_image.texture, 0, 0, data.image.cx, data.image.cy, false);
	end

	obs.gs_matrix_pop()

	obs.gs_matrix_push()
	obs.gs_matrix_translate3f(960, 720, 0)
	obs.gs_matrix_rotaa4f(0.0, 0.0, 1.0, 2.0 * math.pi / 12 * hours);
	obs.gs_matrix_translate3f(-960, -720, 0)

	while obs.gs_effect_loop(effect, "Draw") do
		obs.obs_source_draw(data.hour_image.texture, 0, 0, data.image.cx, data.image.cy, false);
	end

	obs.gs_matrix_pop()

	obs.gs_matrix_push()
	obs.gs_matrix_translate3f(960, 720, 0)
	obs.gs_matrix_rotaa4f(0.0, 0.0, 1.0, 2 * math.pi / 60 * seconds);
	obs.gs_matrix_translate3f(-960, -720, 0)

	while obs.gs_effect_loop(effect, "Draw") do
		obs.obs_source_draw(data.second_image.texture, 0, 0, data.image.cx, data.image.cy, false);
	end

	obs.gs_matrix_pop()

	obs.gs_blend_state_pop()
end

--- Returns the native canvas width of the source in pixels.
--- @param data table Source instance data.
--- @return number
source_def.get_width = function(data)
	return 1920
end

--- Returns the native canvas height of the source in pixels.
--- @param data table Source instance data.
--- @return number
source_def.get_height = function(data)
	return 1440
end

-- ======================================================================================
-- Vocal announcement
-- ======================================================================================

--- Subfolder (next to this script) holding Beep.wav, hXX.wav and mXX.wav.
AUDIO_SUBDIR = "Audio/"
--- Countdown file, played once.
BEEP_FILE = "Beep.wav"
--- Seconds to wait after the end of the beep before the voice starts (0 = immediately).
VOICE_DELAY = 1
--- Seconds before the announcement at which Beep.wav is started. Beep.wav is one pre-mixed
--- file (made in a DAW) that contains the whole beep pattern and ends at the announcement time.
BEEP_LEAD = 6
--- OBS global audio channels used for the two private players (0 is video, 1-5 are used by OBS).
AUDIO_CHANNEL_BEEP = 10
AUDIO_CHANNEL_VOICE = 11
--- Audio tracks the announcement is sent to (bitmask: 63 = tracks 1-6).
AUDIO_MIXERS = 63
--- Set to true to also hear the announcement on the OBS monitoring device.
MONITOR_LOCALLY = false
--- Polling interval of the announcement timer, in milliseconds.
TICK_MS = 20
--- Ticks ignored after a voice file starts, before its "ended" state is trusted (~300 ms).
VOICE_GUARD_TICKS = 15
--- Safety timeout for a single voice file, in ticks (~20 s).
VOICE_TIMEOUT_TICKS = 1000

--- Announcement runtime state.
ann = {
	enabled = false,
	instances = 0,      -- number of clock sources currently existing
	hour = 12,
	minute = 0,
	beep_src = nil,
	voice_src = nil,
	last_t = 0,         -- last wall-clock second that has been processed
	test_target = nil,  -- epoch second of a manually triggered test announcement
	queue = {},         -- voice files still to play
	voice_busy = false,
	voice_ticks = 0,
	voice_dur = nil,       -- length in seconds of the voice file being played (nil = unknown)
	voice_start_ns = nil,  -- OBS high-resolution time at which it started
}

--- Returns the absolute path of the audio folder.
--- @return string
function ann_dir()
	return script_path() .. AUDIO_SUBDIR
end

--- Checks whether a file can be opened for reading.
--- @param path string
--- @return boolean
function file_exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

--- Reads a little-endian unsigned 32-bit integer from a string.
--- @param s string
--- @param i number 1-based position of the first byte.
--- @return number
function u32le(s, i)
	local a, b, c, d = s:byte(i, i + 3)
	return a + b * 256 + c * 65536 + d * 16777216
end

--- Returns the duration in seconds of a PCM WAV file by reading its header, or nil.
--- @param path string
--- @return number|nil
function wav_duration(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local head = f:read(12)
	if not head or #head < 12 or head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WAVE" then
		f:close()
		return nil
	end
	local size = f:seek("end")
	local byte_rate, data_size
	local pos = 12
	while pos + 8 <= size do
		f:seek("set", pos)
		local hdr = f:read(8)
		if not hdr or #hdr < 8 then
			break
		end
		local id, len = hdr:sub(1, 4), u32le(hdr, 5)
		if id == "fmt " then
			local fmt = f:read(16)
			if fmt and #fmt >= 16 then
				byte_rate = u32le(fmt, 9)
			end
		elseif id == "data" then
			if len == 0 or pos + 8 + len > size then
				len = size - pos - 8
			end
			data_size = len
			break
		end
		pos = pos + 8 + len + (len % 2)
	end
	f:close()
	if byte_rate and byte_rate > 0 and data_size then
		return data_size / byte_rate
	end
	return nil
end

--- Creates a private media player routed to a global audio channel.
--- @param name string Internal source name.
--- @param channel number OBS output channel.
--- @param file string|nil File to preload (opened but not played).
--- @return userdata|nil
function ann_create_player(name, channel, file)
	local settings = obs.obs_data_create()
	obs.obs_data_set_bool(settings, "is_local_file", true)
	obs.obs_data_set_bool(settings, "looping", false)
	obs.obs_data_set_bool(settings, "close_when_inactive", false)
	obs.obs_data_set_bool(settings, "restart_on_activate", false)
	if file then
		obs.obs_data_set_string(settings, "local_file", file)
	end
	local src = obs.obs_source_create_private("ffmpeg_source", name, settings)
	obs.obs_data_release(settings)

	if src then
		obs.obs_source_set_audio_mixers(src, AUDIO_MIXERS)
		if MONITOR_LOCALLY then
			obs.obs_source_set_monitoring_type(src, obs.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT)
		end
		obs.obs_set_output_source(channel, src)
	else
		print("RAI Clock: unable to create audio player " .. name)
	end
	return src
end

--- Loads and starts a file on one of the private audio players.
--- @param src userdata Player created by `ann_create_player`.
--- @param path string
function ann_play(src, path)
	local s = obs.obs_data_create()
	obs.obs_data_set_string(s, "local_file", path)
	obs.obs_source_update(src, s)
	obs.obs_data_release(s)
	obs.obs_source_media_restart(src)
	obs.obs_source_media_play_pause(src, false)
end

--- Copies the user's choices from a clock source's settings.
--- @param settings userdata
function ann_apply_settings(settings)
	ann.enabled = obs.obs_data_get_bool(settings, "ann_enabled")
	ann.hour = obs.obs_data_get_int(settings, "ann_hour")
	ann.minute = obs.obs_data_get_int(settings, "ann_minute")
end

--- Plays the next existing file in the queue; marks the voice player idle when empty.
function ann_next_voice()
	while #ann.queue > 0 do
		local name = table.remove(ann.queue, 1)
		local path = ann_dir() .. name
		if file_exists(path) then
			ann.voice_dur = wav_duration(path)
			ann.voice_start_ns = obs.os_gettime_ns and obs.os_gettime_ns() or nil
			ann_play(ann.voice_src, path)
			ann.voice_ticks = 0
			ann.voice_busy = true
			print(string.format("RAI Clock: playing %s (%s)", name,
				ann.voice_dur and string.format("%.2f s", ann.voice_dur) or "length unknown"))
			return
		else
			print("RAI Clock: missing audio file " .. path)
		end
	end
	ann.voice_busy = false
end

--- Builds the list of files to speak for an hour/minute pair, e.g. {"h13.wav", "m12.wav"}.
--- @param hour number 0-23
--- @param minute number 0-59
--- @return table
function ann_files_for(hour, minute)
	local files = { string.format("h%02d.wav", hour) }
	if minute ~= 0 then
		files[#files + 1] = string.format("m%02d.wav", minute)
	end
	return files
end

--- Reads the announcement settings directly from the clock source(s) that exist in OBS.
--- This does not depend on `create`/`update` having been called in the current Lua state, which
--- is not the case after the script is reloaded. The first enabled clock source wins.
function ann_refresh_from_sources()
	local enabled, hour, minute = false, ann.hour, ann.minute
	local sources = obs.obs_enum_sources()
	if sources then
		for _, src in ipairs(sources) do
			if obs.obs_source_get_id(src) == source_def.id then
				local st = obs.obs_source_get_settings(src)
				if st then
					if obs.obs_data_get_bool(st, "ann_enabled") then
						enabled = true
						hour = obs.obs_data_get_int(st, "ann_hour")
						minute = obs.obs_data_get_int(st, "ann_minute")
					end
					obs.obs_data_release(st)
				end
				if enabled then
					break
				end
			end
		end
		obs.source_list_release(sources)
	end
	ann.enabled, ann.hour, ann.minute = enabled, hour, minute
end

--- Timer callback: drives the countdown beeps and the chained voice files.
function announcement_tick()
	-- 1) Chain the voice files: start the next one as soon as the current one has ended.
	if ann.voice_busy and ann.voice_src then
		ann.voice_ticks = ann.voice_ticks + 1
		local finished = ann.voice_ticks > VOICE_TIMEOUT_TICKS
		if not finished and ann.voice_dur then
			-- Length known from the WAV header: do not depend on OBS reporting the end of playback.
			local elapsed = ann.voice_ticks * TICK_MS / 1000
			if ann.voice_start_ns and obs.os_gettime_ns then
				elapsed = (obs.os_gettime_ns() - ann.voice_start_ns) / 1e9
			end
			finished = elapsed >= ann.voice_dur
		elseif not finished and ann.voice_ticks > VOICE_GUARD_TICKS then
			local state = obs.obs_source_media_get_state(ann.voice_src)
			finished = (state == obs.OBS_MEDIA_STATE_ENDED)
				or (state == obs.OBS_MEDIA_STATE_STOPPED)
				or (state == obs.OBS_MEDIA_STATE_NONE)
				or (state == obs.OBS_MEDIA_STATE_ERROR)
		end
		if finished then
			ann_next_voice()
		end
	end

	-- 2) Act once per wall-clock second.
	local now_t = os.time()
	if now_t == ann.last_t then
		return
	end
	ann.last_t = now_t
	ann_refresh_from_sources()

	-- d = seconds remaining until the announcement time (negative once it has passed)
	local d
	if ann.test_target then
		d = ann.test_target - now_t
		if d <= -VOICE_DELAY then
			ann.test_target = nil
		end
		if d < -VOICE_DELAY then
			return
		end
	elseif ann.enabled then
		local t = os.date("*t", now_t)
		local sod = t.hour * 3600 + t.min * 60 + t.sec
		d = ((ann.hour * 3600 + ann.minute * 60 - sod + 43200) % 86400) - 43200
	else
		return
	end

	if d == BEEP_LEAD and ann.beep_src then
		local path = ann_dir() .. BEEP_FILE
		if file_exists(path) then
			ann_play(ann.beep_src, path)
		else
			print("RAI Clock: missing audio file " .. path)
		end
	elseif d == -VOICE_DELAY and ann.voice_src then
		ann.queue = ann_files_for(ann.hour, ann.minute)
		ann_next_voice()
	end
end

--- Button callback: runs a full announcement (beeps + voice) starting in a few seconds.
function ann_test_clicked(props, property)
	ann.test_target = os.time() + BEEP_LEAD + 1
	return false
end

--- Creates the audio players and starts the announcement timer.
--- @param settings userdata
function script_load(settings)
	print("RAI Clock v1.3.2 loaded (audio folder: " .. ann_dir() .. ")")
	ann.beep_src = ann_create_player("RAI Clock Beep", AUDIO_CHANNEL_BEEP, nil)
	ann.voice_src = ann_create_player("RAI Clock Voice", AUDIO_CHANNEL_VOICE, nil)
	obs.timer_add(announcement_tick, TICK_MS)
end

--- Stops the timer and releases the audio players.
function script_unload()
	obs.timer_remove(announcement_tick)
	obs.obs_set_output_source(AUDIO_CHANNEL_BEEP, nil)
	obs.obs_set_output_source(AUDIO_CHANNEL_VOICE, nil)
	if ann.beep_src then
		obs.obs_source_release(ann.beep_src)
		ann.beep_src = nil
	end
	if ann.voice_src then
		obs.obs_source_release(ann.voice_src)
		ann.voice_src = nil
	end
end

--- Displays the script summary inside OBS Studio's Scripts dialog.
--- @return string
function script_description()
	return "Adds \"RAI Clock Ora Esatta\" which draws the animated RAI analog clock of the end of the 70s.\n" ..
		"Optional vocal announcement: add the source to a scene, double-click it and pick hour and minute. " ..
		"Shortly before the chosen time Beep.wav is played once, then hXX.wav and, if the minute is not 0, mXX.wav."
end

obs.obs_register_source(source_def)
