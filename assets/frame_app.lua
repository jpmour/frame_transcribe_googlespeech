local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local plain_text = require('plain_text.min')

-- Phone to Frame flags
TEXT_MSG = 0x0b
STYLED_TEXT_MSG = 0x0c
AUDIO_SUBS_MSG = 0x30
TAP_SUBS_MSG = 0x10

-- Speaker colours. The Frame only has 16 fixed palette names, so we reassign the RGB value
-- of some of them. Speaker 0 (white) means "no speaker information".
-- 0 WHITE, 1 SKYBLUE (cyan), 2 YELLOW, 3 GREEN, 4 PINK, 5 CLOUDBLUE (lavender)
local speaker_colors = {[0]='WHITE', 'SKYBLUE', 'YELLOW', 'GREEN', 'PINK', 'CLOUDBLUE'}

function setup_palette()
    pcall(frame.display.assign_color, 'WHITE', 255, 255, 255)
    pcall(frame.display.assign_color, 'SKYBLUE', 100, 200, 255)
    pcall(frame.display.assign_color, 'YELLOW', 255, 220, 100)
    pcall(frame.display.assign_color, 'GREEN', 150, 255, 150)
    pcall(frame.display.assign_color, 'PINK', 255, 150, 200)
    pcall(frame.display.assign_color, 'CLOUDBLUE', 200, 180, 255)
end

-- Parse a styled text message: [line count] then per line [speaker byte][length byte][text].
-- The whole display arrives as one message, so text and colours always update together.
-- A damaged message gives fewer lines instead of an error (an error would stop the app).
function parse_styled_text(block)
    local lines = {}
    local count = string.byte(block, 1) or 0
    local pos = 2
    for i = 1, count do
        local speaker = string.byte(block, pos)
        local len = string.byte(block, pos + 1)
        if speaker == nil or len == nil then break end
        lines[i] = { speaker = speaker, text = string.sub(block, pos + 2, pos + 1 + len) }
        pos = pos + 2 + len
    end
    return lines
end

-- register the message parser so it's automatically called when matching data comes in
data.parsers[TEXT_MSG] = plain_text.parse_plain_text
data.parsers[STYLED_TEXT_MSG] = parse_styled_text
data.parsers[AUDIO_SUBS_MSG] = code.parse_code
data.parsers[TAP_SUBS_MSG] = code.parse_code

-- Frame to Phone flags
AUDIO_DATA_NON_FINAL_MSG = 0x05
AUDIO_DATA_FINAL_MSG = 0x06
TAP_MSG = 0x09

function handle_tap()
	pcall(frame.bluetooth.send, string.char(TAP_MSG))
end

-- draw the current text on the display
function print_text()
    local i = 0
    for line in data.app_data[TEXT_MSG].string:gmatch("([^\n]*)\n?") do
        if line ~= "" then
            frame.display.text(line, 1, i * 60 + 1)
            i = i + 1
        end
    end
end

-- draw lines that each carry a speaker colour
function print_styled_text(lines)
    for i, line in ipairs(lines) do
        if line.text ~= "" then
            local color = speaker_colors[line.speaker] or 'WHITE'
            frame.display.text(line.text, 1, (i - 1) * 60 + 1, {color=color})
        end
    end
end

-- Main app loop
function app_loop()
	setup_palette()
	-- clear the display
	frame.display.text(" ", 1, 1)
	frame.display.show()
    local last_batt_update = 0
    local streaming = false
	local audio_data = ''
	local mtu = frame.bluetooth.max_length()
	-- data buffer needs to be even for reading from microphone
	if mtu % 2 == 1 then mtu = mtu - 1 end

    while true do
        rc, err = pcall(
            function()
                -- process any raw items, if ready (parse into image or text, then clear raw)
                local items_ready = data.process_raw_items()

                if items_ready > 0 then

                    if (data.app_data[STYLED_TEXT_MSG] ~= nil) then
                        -- a styled message replaces the whole display, and any older plain text
                        print_styled_text(data.app_data[STYLED_TEXT_MSG])
                        frame.display.show()
                        data.app_data[STYLED_TEXT_MSG] = nil
                        data.app_data[TEXT_MSG] = nil
                    elseif (data.app_data[TEXT_MSG] ~= nil and data.app_data[TEXT_MSG].string ~= nil) then
                        print_text()
                        frame.display.show()
                    end

                    if (data.app_data[TAP_SUBS_MSG] ~= nil) then

                        if data.app_data[TAP_SUBS_MSG].value == 1 then
                            -- start subscription to tap events
                            frame.imu.tap_callback(handle_tap)
                        else
                            -- cancel subscription to tap events
                            frame.imu.tap_callback(nil)
                        end

                        data.app_data[TAP_SUBS_MSG] = nil
                    end

                    if (data.app_data[AUDIO_SUBS_MSG] ~= nil) then

                        if data.app_data[AUDIO_SUBS_MSG].value == 1 then
                            -- start subscription to audio
                            audio_data = ''
                            pcall(frame.microphone.start, {sample_rate=8000, bit_depth=16})
                            streaming = true
                            frame.display.text("Streaming Audio", 1, 1)
                            frame.display.show()
                        else
                            -- cancel subscription to audio
                            pcall(frame.microphone.stop)
                            -- clear the display
                            frame.display.text(" ", 1, 1)
                            frame.display.show()
                        end

                        data.app_data[AUDIO_SUBS_MSG] = nil
                    end
                end
            end
        )
        -- Catch the break signal here and clean up the display
        if rc == false then
            -- send the error back on the stdout stream
            print(err)
            frame.display.text(" ", 1, 1)
            frame.display.show()
            frame.sleep(0.04)
            break
        end

        -- send any pending audio data back
		-- Streams until AUDIO_SUBS_MSG (with value 0) is sent from phone
		-- (prioritize the reading and sending about 20x compared to checking for other events e.g. AUDIO_SUBS_MSG/0)
        if streaming then
            for i=1,20 do
				audio_data = frame.microphone.read(mtu)

				-- Calling frame.microphone.stop() will allow this to break the loop
				if audio_data == nil then
					-- send an end-of-stream message back to the phone
					pcall(frame.bluetooth.send, string.char(AUDIO_DATA_FINAL_MSG))
					frame.sleep(0.0025)
					streaming = false
                    break

				-- send the data that was read
				elseif audio_data ~= '' then
					pcall(frame.bluetooth.send, string.char(AUDIO_DATA_NON_FINAL_MSG) .. audio_data)
					frame.sleep(0.0025)
				end
			end
		end

        -- periodic battery level updates, 120s
        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

		if not streaming then frame.sleep(0.1) end
    end
end

-- run the main app loop
app_loop()