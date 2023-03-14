local remoteapi = require "remoteapi"
local completion = require "cc.completion"

--#region Color Schemes
local color_schemes = {
    dracula = {
        background = 0x282a36,
        selected = 0x44475a,
        primary_text = 0xf8f8f2,
        secondary_text = 0x6272a4,
        tertiary_text = 0x8be9fd,
        features = 0xbd93f9
    },
    matte_blue = {
        background = 0x121212,
        selected = 0xf8f8f2,
        primary_text = 0x5983FC,
        secondary_text = 0x3E60C1,
        tertiary_text = 0x2E4583,
        features = 0x293556
    },
    kiwi = {
        background = 0x121212,
        selected = 0xf8f8f2,
        primary_text = 0xFFE3B3,
        secondary_text = 0x92DE8B,
        tertiary_text = 0x0AB68B,
        features = 0x028174
    },
    vaporwave = {
        background = 0x121212,
        selected = 0xf8f8f2,
        primary_text = 0xEA80FC,
        secondary_text = 0xAA4FF6,
        tertiary_text = 0x8D39EC,
        features = 0x7827E6
    },
    hot_pink = {
        background = 0x121212,
        selected = 0xf8f8f2,
        primary_text = 0xFF80AB,
        secondary_text = 0xFF4081,
        tertiary_text = 0xF50057,
        features = 0xC61063
    }
}

local color_scheme_map = {
    background = colors.black,
    selected = colors.gray,
    primary_text = colors.white,
    secondary_text = colors.gray,
    tertiary_text = colors.purple,
    features = colors.cyan
}

local choosing_theme = false

local function resetTerminal()
    for _, color in pairs(colors) do
        if type(color) == "number" then
            term.setPaletteColor(color, colors.packRGB(term.nativePaletteColor(color)))
        end
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function selectColorScheme(manual)
    choosing_theme = true
    local selected = ""
    resetTerminal()
    repeat
        if not manual and fs.exists("/preferred_theme") then
            local preferred_theme = io.open("/preferred_theme", "r"):read("l")
            if color_schemes[preferred_theme] ~= nil then
                selected = preferred_theme
            else
                fs.delete("/preferred_theme")
                selected = ""
            end
        else
            if fs.exists("/preferred_theme") then
                fs.delete("/preferred_theme")
            end
            local color_scheme_names = {}
            print("Select a color scheme")
            write("One of")
            for k, _ in pairs(color_schemes) do
                table.insert(color_scheme_names, k)
                write(" '"..k.."'")
            end
            print("")
            write("> ")
            repeat
                selected = read(nil, nil,
                    function(text) return completion.choice(text, color_scheme_names) end)
            until color_schemes[selected] ~= nil
            io.open("/preferred_theme", "w"):write(selected)
        end
    until selected ~= ""

    for index, value in pairs(color_schemes[selected]) do
        term.setPaletteColor(color_scheme_map[index], value)
    end
    term.setBackgroundColor(color_scheme_map.background)
    term.setTextColor(color_scheme_map.selected)
    term.setCursorBlink(false)
    term.clear()

    choosing_theme = false
    os.queueEvent("update_ui")
end
--#endregion

remoteapi.initialize()

selectColorScheme()

local button_colors = {
    color = "features",
    hover_color = "tertiary_text",
    click_color = "primary_text"
}

local focus_search = true

local text_boxes = {}
local buttons = {}

local function updateQueue()
    local current_queue = remoteapi.requestInfo("queue").payload.payload
    for i = 1, 4, 1 do
        text_boxes["queue_" .. i].content = current_queue[i + 1] or ""
    end
end

local function updateNowPlaying()
    local current_track = remoteapi.requestInfo("nowplaying").payload.payload
    text_boxes["now_playing"].content = current_track.title or "Nothing Playing"
end

local function updateVolume()
    local current_volume = remoteapi.requestInfo("volume").payload.payload
    text_boxes["volume"].content = tostring(current_volume)
end

text_boxes = {
    search_bar = {
        x1 = 2,
        y1 = 1,
        x2 = 25,
        y2 = 2,
        overflow = true,
        color = color_scheme_map[button_colors.hover_color],
        content = ""
    },
    now_playing = {
        x1 = 2,
        y1 = 14,
        x2 = 25,
        y2 = 14,
        content = "Now Playing",
        color = color_scheme_map[button_colors.hover_color],
        update = updateNowPlaying
    },
    volume = {
        x1 = 24,
        y1 = 8,
        x2 = 26,
        y2 = 8,
        content = "100",
        color = color_scheme_map[button_colors.hover_color],
        update = updateVolume
    },
    queue_1 = {
        x1 = 2,
        y1 = 16,
        x2 = 25,
        y2 = 16,
        content = "Queue 1",
        color = color_scheme_map[button_colors.hover_color],
        update = updateQueue
    },
    queue_2 = {
        x1 = 2,
        y1 = 17,
        x2 = 25,
        y2 = 17,
        content = "Queue 2",
        color = color_scheme_map[button_colors.hover_color],
    },
    queue_3 = {
        x1 = 2,
        y1 = 18,
        x2 = 25,
        y2 = 18,
        content = "Queue 3",
        color = color_scheme_map[button_colors.hover_color],
    },
    queue_4 = {
        x1 = 2,
        y1 = 19,
        x2 = 25,
        y2 = 19,
        content = "Queue 4",
        color = color_scheme_map[button_colors.hover_color],
    }
}

buttons = {
    {
        x1 = 1,
        y1 = 4,
        x2 = 2,
        y2 = 7,
        content = "Rply",
        text_direction = "vertical",
        color = color_scheme_map[button_colors.color],
        action = function()
            remoteapi.sendControl("replay")
        end
    },
    {
        x1 = 1,
        y1 = 9,
        x2 = 2,
        y2 = 12,
        content = "Rset",
        text_direction = "vertical",
        color = color_scheme_map[button_colors.color],
        action = function()
            remoteapi.sendControl("restart")
            print("rebooting")
            os.reboot()
        end
    },
    {
        x1 = 1,
        y1 = 20,
        x2 = 1,
        y2 = 20,
        content = "X",
        color = color_scheme_map[button_colors.color],
        action = function()
            os.queueEvent("exitRemote")
        end
    },
    {
        x1 = 24,
        y1 = 4,
        x2 = 26,
        y2 = 7,
        content = "V+",
        --        text_direction = "vertical",
        color = color_scheme_map[button_colors.color],
        action = function()
            local message = remoteapi.requestInfo("volume")
            if message.payload.payload + 5 <= 100 then
                remoteapi.sendControl("volume" .. (message.payload.payload + 5))
            else
                remoteapi.sendControl("volume100")
            end
        end
    },
    {
        x1 = 24,
        y1 = 9,
        x2 = 26,
        y2 = 12,
        content = "V-",
        --        text_direction = "vertical",
        color = color_scheme_map[button_colors.color],
        action = function()
            local message = remoteapi.requestInfo("volume")
            if message.payload.payload - 5 >= 0 then
                remoteapi.sendControl("volume" .. (message.payload.payload - 5))
            else
                remoteapi.sendControl("volume0")
            end
        end
    },
    {
        x1 = 26,
        y1 = 20,
        x2 = 26,
        y2 = 20,
        content = "T",
        color = color_scheme_map[button_colors.color],
        action = function() selectColorScheme(true) end
    },
    {
        x1 = 11,
        y1 = 5,
        x2 = 15,
        y2 = 7,
        content = "Resme",
        color = color_scheme_map[button_colors.color],
        action = function()
            remoteapi.sendControl("resume")
        end
    },
    {
        x1 = 11,
        y1 = 9,
        x2 = 15,
        y2 = 11,
        content = "Pause",
        color = color_scheme_map[button_colors.color],
        action = function()
            remoteapi.sendControl("pause")
        end
    },
    {
        x1 = 6,
        y1 = 7,
        x2 = 8,
        y2 = 9,
        content = "<",
        color = color_scheme_map[button_colors.color],
        action = function()
            remoteapi.sendControl("previous")
        end
    },
    {
        x1 = 18,
        y1 = 7,
        x2 = 20,
        y2 = 9,
        content = ">",
        color = color_scheme_map[button_colors.color],
        action = function()
            remoteapi.sendControl("next")
        end
    },
}

local search_bar = text_boxes["search_bar"]

local event_handlers = {
    update_ui = function()
        for _, value in pairs(text_boxes) do
            if value.update and type(value.update) == "function" then
                value.update()
            end
        end
        term.setBackgroundColor(color_scheme_map.background)
        term.setTextColor(color_scheme_map.selected)
        term.setCursorBlink(false)
        term.clear()
        
        for _, value in pairs(buttons) do
            if value.color then
                paintutils.drawFilledBox(value.x1, value.y1, value.x2, value.y2, value.color)
            else
                paintutils.drawFilledBox(value.x1, value.y1, value.x2, value.y2, color_scheme_map[button_colors.color])
            end
            local displayText = value.content
            if value.text_direction and value.text_direction == "vertical" then
                if #displayText > (value.y2 - value.y1) + 1 then
                    displayText = value.content:sub(-((value.y2 - value.y1) + 1))
                end
                local itr = 0
                for c in displayText:gmatch "." do
                    term.setCursorPos(math.ceil((value.x1 + value.x2) / 2),
                        math.ceil(((value.y1 + value.y2) / 2) - (#displayText / 2)) + itr)
                    term.write(c)
                    itr = itr + 1
                end
            else
                if #displayText > (value.x2 - value.x1) + 1 then
                    displayText = value.content:sub(-((value.x2 - value.x1) + 1))
                end
                term.setCursorPos(math.ceil(((value.x1 + value.x2) / 2) - (#displayText / 2)),
                    math.ceil((value.y1 + value.y2) / 2))
                term.write(displayText)
            end
        end
        for _, value in pairs(text_boxes) do
            if value.color then
                paintutils.drawFilledBox(value.x1, value.y1, value.x2, value.y2, value.color)
            else
                paintutils.drawFilledBox(value.x1, value.y1, value.x2, value.y2,
                color_scheme_map[button_colors.hover_color])
            end
            local displayText = value.content
            if value.text_direction and value.text_direction == "vertical" then
                if #displayText > (value.y2 - value.y1) + 1 then
                    displayText = value.content:sub(-((value.y2 - value.y1) + 1))
                end
                local itr = 0
                for c in displayText:gmatch "." do
                    term.setCursorPos(math.ceil((value.x1 + value.x2) / 2),
                        math.ceil(((value.y1 + value.y2) / 2) - (#displayText / 2)) + itr)
                    term.write(c)
                    itr = itr + 1
                end
            else
                if #displayText > (value.x2 - value.x1) + 1 then
                    displayText = value.content:sub(-((value.x2 - value.x1) + 1))
                end
                term.setCursorPos(math.ceil(((value.x1 + value.x2) / 2) - (#displayText / 2)),
                    math.ceil((value.y1 + value.y2) / 2))
                term.write(displayText)
            end
        end
    end,
    mouse_click = function (button, x, y)
        if button == 1 then
            if x >= search_bar.x1 and x <= search_bar.x2 and y >= search_bar.y1 and y <= search_bar.y2 then
                focus_search = true
                search_bar.color = color_scheme_map[button_colors.click_color]
            else
                focus_search = false
                search_bar.color = color_scheme_map[button_colors.hover_color]
            end
            for _, button in pairs(buttons) do
                if x >= button.x1 and x <= button.x2 and y >= button.y1 and y <= button.y2 then
                    button.action()
                    break
                end
            end
            os.queueEvent("update_ui")
        end
    end,
    char = function(char)
        if focus_search then
            search_bar.content = search_bar.content .. tostring(char)
            os.queueEvent("update_ui")
        end
    end,
    key = function(key, held)
        if focus_search then
            if not held and key == keys.enter then
                remoteapi.sendRequest(search_bar.content)
                search_bar.content = ""
                os.queueEvent("update_ui")
            elseif key == keys.backspace then
                if #search_bar.content > 1 then
                    search_bar.content = search_bar.content:sub(1, -2)
                else
                    search_bar.content = ""
                end
                os.queueEvent("update_ui")
            end
        end
    end,
    paste = function(text)
        if focus_search then
            search_bar.content = text
            os.queueEvent("update_ui")
        end
    end
}

parallel.waitForAny(function()
        while true do
            local event, param1, param2, param3 = os.pullEvent()
            
            if event == "exitRemote" then
                resetTerminal()
                break
            elseif event_handlers[event] then
                event_handlers[event](param1, param2, param3)
            end
        end
    end,
    function()
        while true do
            repeat
                os.sleep(0)
            until not choosing_theme
            os.queueEvent("update_ui")
            os.sleep(3)
        end
    end
)
