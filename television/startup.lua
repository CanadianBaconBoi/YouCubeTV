local settings = require("settings")

local modem = peripheral.find("modem") or error("No modem attached", 0)
local modem_channels = {
    c2s = settings.channels.c2s or 35284,
    s2c = settings.channels.s2c or 35285
}
local maximum_control_distance = settings.maximum_control_distance or 40

modem.open(modem_channels.c2s)

local receieve_cancelled = false
local play_cancelled = false
local server = settings.server or "wss://youcube.knijn.one"
local queries = {}
local _query = ""
local control_message = nil
local control_table = { pause = false }
local audiovolume = settings.default_volume or 100
local playback_buffer_size = settings.playback_buffer_size or 60
local nowplaying = {}

-- #region playback controll vars
local back_buffer = {}
local max_back = settings.max_back or 32
local queue = {}
local restart = falsecontrol
-- #endregion

local function is_lib(Table, Item)
    for key, value in ipairs(Table) do
        if value == Item or value .. ".lua" == Item then
            return true, value
        end
    end
    return false
end

local libs = { "youcubeapi", "numberformatter", "semver", "argparse", "string_pack" }
local lib_paths = { ".", "./lib", "./apis", "./modules", "/", "/lib", "/apis", "/modules" }

if _G.lOS then
    table.insert(lib_paths, "/Program_Files/YouCube/lib")
end

for i, path in pairs(lib_paths) do
    if fs.exists(path) then
        for _i, file_name in pairs(fs.list(path)) do
            local found, lib = is_lib(libs, file_name)
            if found and libs[lib] == nil then
                if require then
                    libs[lib] = require(path .. "/" .. file_name:gsub(".lua", ""))
                else
                    libs[lib] = dofile(path .. "/" .. file_name)
                end
            end
        end
    end
end

for key, lib in ipairs(libs) do
    if libs[lib] == nil then
        error("Library \"" .. lib .. "\" not found")
    end
end

local youcubeapi = libs.youcubeapi.API.new(http.websocket(server))

local speakers   = { peripheral.find("speaker") }
if #speakers == 0 then
    error("You need a tapedrive or speaker in order to use YouCube!")
end

local monitors = { peripheral.find("monitor") }
local outputmonitor
for _, monitor in pairs(monitors) do
    if monitor then
        outputmonitor = monitor
    end
end

if not outputmonitor then
    error("You need a monitor in order to use YouCube!")
end


outputmonitor.setTextScale(0.5)
outputmonitor.setCursorPos(1, 1)
outputmonitor.clear()
term.setCursorPos(1, 1)
term.clear()

local audiodevices = {}

for _, speaker in pairs(speakers) do
    table.insert(audiodevices, libs.youcubeapi.Speaker.new(speaker))
end

local last_error
local valid_audiodevices = {}

for i, audiodevice in pairs(audiodevices) do
    local _error = audiodevice:validate()
    if _error ~= nil then
        last_error = _error
    else
        table.insert(valid_audiodevices, audiodevice)
    end
end

if #valid_audiodevices == 0 then
    error(last_error)
end

local function shallow_copy(t)
    local t2 = {}
    for k, v in pairs(t) do
        t2[k] = v
    end
    return t2
end

--[[
    Packet format
    {
        protocol = string,
        payload = table {
            message = string,
            data = any|nil
        }
    }
--]]
local protocol_handlers = {
    request = {
        handler = function(payload)
            if payload.message == "single" and type(payload.data) == "string" and payload.data ~= "" then
                print("Received message " .. payload.data)
                table.insert(queries, payload.data)
            elseif payload.message == "multiple" and type(payload.data) == "table" then
                for _, request in pairs(payload.data) do
                    print("Received request " .. request)
                    table.insert(queries, request)
                end
            end
        end
    },
    ping = {
        handlers = {
            ping = function (payload_data)
                if type(payload_data) == "number" then
                    modem.transmit(modem_channels.s2c, modem_channels.c2s,
                    { protocol = "ping", payload = { message = "pong", data = payload_data } })
                end
            end
        }
    },
    control = {
        handler = function(payload)
            if type(payload.message) == "string" then
                control_message = payload.message
            end
        end,
        handlers = { -- payload.message
            restart = function(payload_data)
                os.reboot()
            end,
            stop = function(payload_data)
                os.shutdown()
            end,
            pause = function(payload_data)
                control_table["pause"] = true
            end,
            resume = function(payload_data)
                control_table["pause"] = false
                os.queueEvent("resumeVideo")
                os.queueEvent("resumeAudio")
            end,
            volume = function(payload_data)
                if type(payload_data) == "number" then
                    audiovolume = payload_data
                    for _, audiodevice in pairs(valid_audiodevices) do
                        audiodevice:reset()
                        audiodevice:setVolume(audiovolume)
                    end
                end
            end
        }
    },
    info = {
        handlers = { -- payload.message
            queue = function(payload_data)
                local retval = {}
                if nowplaying and nowplaying["title"] and nowplaying["title"] ~= "" then
                    table.insert(retval, nowplaying["title"])
                elseif _query and _query ~= "" then
                    table.insert(retval, _query)
                end
                if queue and next(queue) then
                    for _, v in ipairs(queue) do
                        table.insert(retval, v)
                    end
                end
                if queue and next(queries) then
                    for _, v in ipairs(queries) do
                        table.insert(retval, v)
                    end
                end
                modem.transmit(modem_channels.s2c, modem_channels.c2s, {
                    protocol = "info_response",
                    payload = {
                        message = "queue",
                        data = retval
                    }
                })
            end,
            volume = function(payload_data)
                modem.transmit(modem_channels.s2c, modem_channels.c2s, {
                    protocol = "info_response",
                    payload = {
                        message = "volume",
                        data = audiovolume
                    }
                })
            end,
            nowplaying = function(payload_data)
                modem.transmit(modem_channels.s2c, modem_channels.c2s, {
                    protocol = "info_response",
                    payload = {
                        message = "nowplaying",
                        data = nowplaying
                    }
                })
            end
        }
    }
}

local function do_receive()
    while receieve_cancelled == false do
        local _, _, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if distance <= maximum_control_distance and type(message.protocol) == "string" and protocol_handlers[message.protocol] and type(message.payload) == "table" and type(message.payload.message) == "string" then
            local protocol_handler = protocol_handlers[message.protocol]
            if protocol_handler.handlers and protocol_handler.handlers[message.payload.message] then
                local message_handler = protocol_handler.handlers[message.payload.message]
                message_handler(message.payload.data)
            elseif protocol_handler.handler then
                protocol_handler.handler(message.payload)
            end
        end
    end
end

local function play_audio(buffer, title)
    for _, audiodevice in pairs(valid_audiodevices) do
        audiodevice:reset()
        audiodevice:setLabel(title)
        audiodevice:setVolume(audiovolume)
    end

    while true do
        if control_table["pause"] == true then
            parallel.waitForAny(function()
                    while true do
                        youcubeapi:handshake()
                        os.sleep(1)
                    end
                end,
                function()
                    os.pullEvent("resumeAudio")
                end
            )
        end

        local chunk = buffer:next()

        -- Adjust buffer size on first chunk
        if buffer.filler.chunkindex == 1 then
            buffer.size = math.ceil(1024 / (#chunk / 16))
        end

        if chunk == "" then
            local play_functions = {}
            for _, audiodevice in pairs(valid_audiodevices) do
                table.insert(play_functions, function()
                    audiodevice:play()
                end)
            end

            parallel.waitForAll(table.unpack(play_functions))
            return
        end

        local write_functions = {}
        for _, audiodevice in pairs(valid_audiodevices) do
            table.insert(write_functions, function()
                audiodevice:write(chunk)
            end)
        end

        parallel.waitForAll(table.unpack(write_functions))
    end
end

local function play(url)
    restart = false
    print("Requesting media ...")

    youcubeapi:request_media(url, outputmonitor.getSize())

    local data
    local x, y = term.getCursorPos()
    local mX, mY = outputmonitor.getCursorPos()

    repeat
        data = youcubeapi:receive()
        if data.action == "status" then
            term.setCursorPos(x, y)
            outputmonitor.setCursorPos(mX, mY)
            term.clearLine()
            outputmonitor.clearLine()
            term.write("Status: ")
            outputmonitor.write("Status: ")
            term.setTextColor(colors.green)
            outputmonitor.setTextColor(colors.green)
            os.queueEvent("youcube:status", data)
            term.write(data.message)
            outputmonitor.write(data.message)
            term.setTextColor(colors.white)
            outputmonitor.setTextColor(colors.white)
        else
            print()
        end
    until data.action == "media"

    if data.action == "error" then
        error(data.message)
    end

    term.write("Playing: ")
    term.setTextColor(colors.lime)
    print(data.title)
    term.setTextColor(colors.white)

    if data.like_count then
        print("Likes: " .. libs.numberformatter.compact(data.like_count))
    end

    if data.view_count then
        print("Views: " .. libs.numberformatter.compact(data.view_count))
    end

    nowplaying = shallow_copy(data)
    nowplaying["action"] = nil

    sleep(2)

    local video_buffer = libs.youcubeapi.Buffer.new(
        libs.youcubeapi.VideoFiller.new(
            youcubeapi,
            data.id,
            outputmonitor.getSize()
        ),
        --[[
            Most videos run on 30 fps, so we store 2s of video.
        ]]
        playback_buffer_size
    )

    local audio_buffer = libs.youcubeapi.Buffer.new(
        libs.youcubeapi.AudioFiller.new(
            youcubeapi,
            data.id
        ),
        --[[
            We want to buffer 1024 chunks.
            One chunks is 16 bits.
            The server (with default settings) sends 32 chunks at once.
        ]]
        32
    )

    parallel.waitForAny(
        function()
            -- Fill Buffers
            while true do
                os.queueEvent("youcube:fill_buffers")
                os.pullEvent()

                audio_buffer:fill()
                video_buffer:fill()
            end
        end,
        function()
            os.queueEvent("youcube:playing")
            parallel.waitForAll(
                function()
                    local string_unpack
                    if not string.unpack then
                        string_unpack = libs.string_pack.unpack
                    end

                    os.queueEvent("youcube:vid_playing", data)
                    libs.youcubeapi.play_vid_monitor(video_buffer, outputmonitor, string_unpack, control_table)
                    os.queueEvent("youcube:vid_eof", data)
                    nowplaying = {}
                end,
                function()
                    os.queueEvent("youcube:audio_playing", data)
                    play_audio(audio_buffer, data.title)
                    os.queueEvent("youcube:audio_eof", data)
                end
            )
        end,
        function()
            while true do
                if control_message then
                    if control_message == "next" then
                        table.insert(back_buffer, url)   --finished playing, push the value to the back buffer
                        if #back_buffer > max_back then
                            table.remove(back_buffer, 1) --remove it from the front of the buffer
                        end
                        libs.youcubeapi.reset_monitor(outputmonitor)
                        control_message = nil
                        nowplaying = {}
                        break
                    elseif control_message == "replay" then
                        if queue and next(queue) then
                            table.insert(queue, 1, url)   --add the current song to upcoming
                        else
                            table.insert(queries, 1, url) --add the current song to upcoming
                        end
                        libs.youcubeapi.reset_monitor(outputmonitor)
                        control_message = nil
                        break
                    end
                end
                os.sleep(0)
            end
        end
    )

    if data.playlist_videos then
        return data.playlist_videos
    end
end

local function play_playlist(playlist)
    queue = playlist
    while #queue ~= 0 do
        local pl = table.remove(queue, 1)
        parallel.waitForAny(
            function()
                while true do
                    if control_message then
                        if control_message == "previous" then
                            table.insert(queue, pl)       --add the current song to upcoming
                            local prev = table.remove(back_buffer)
                            if prev then                  --nil/false check
                                table.insert(queue, prev) --add previous song to upcoming
                            end
                            libs.youcubeapi.reset_monitor(outputmonitor)
                            control_message = nil
                            break
                        end
                    end
                    os.sleep(0)
                end
            end,
            function()
                play(pl) --play the url
            end
        )
    end
end


local function do_play()
    while play_cancelled == false do
        if next(queries) then
            _query                = table.remove(queries, 1)

            youcubeapi            = libs.youcubeapi.API.new(http.websocket(server))

            local playlist_videos = play(_query)

            if playlist_videos then
                play_playlist(playlist_videos)
            end

            while restart do
                play(_query)
            end

            youcubeapi.websocket.close()

            libs.youcubeapi.reset_monitor(outputmonitor)
        end
        os.sleep(0)
    end
end



parallel.waitForAny(do_receive, do_play)
