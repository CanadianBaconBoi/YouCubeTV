local modem
local modem_channels = {
    c2s = 35284,
    s2c = 35285
}
--[[
    Packet format
    {
        protocol = string,
        payload = {
            message = string,
            data = any|nil
        }
    }
--]]

local established = false

local Packet = {
    protocol = "",
    payload = {
        message = "",
        data = nil
    }
}
function Packet:new (o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Packet:setProtocol (proto)
    if type(proto) == "string" then
        self.protocol = proto
    end
end

function Packet:setPayload (message, data)
    if type(message) == "string" then
        self.payload = {
            message = message,
            data = data
        }
    end
end

function Packet:send (channel, replyChannel)
    if type(self.protocol == "string") then
        if type(self.payload) == "table" and type(self.payload.message) == "string" then
            modem.transmit(channel, replyChannel, self)
        end
    end
end

local function connectionWatchdog()
    local channel, message
    local pingTimer
    while true do
        pingTimer = os.startTimer(1)
        parallel.waitForAny(
            function ()
                modem.transmit(modem_channels.c2s, modem_channels.s2c, {protocol = "ping", payload = {message = "ping", data = 1}})
                while true do
                    _, _, channel, _, message, _ = os.pullEvent("modem_message")
                    if message and message.protocol and message.protocol == "ping" and channel == modem_channels.s2c then
                        established = true
                        break
                    end
                end
            end,
            function ()
                local timer
                repeat
                    _, timer = os.pullEvent("timer")
                until timer == pingTimer

                established = false
            end
        )
        os.cancelTimer(pingTimer)
        os.sleep(1)
    end
end

local function initialize()
    term.clear()
    local sX, sY = term.getSize()
    term.setCursorPos((sX/2)-10, (sY/2))
    write("Initializing Network")
    modem = peripheral.find("modem") or error("No modem attached", 0)
    modem.open(modem_channels.s2c)
    
    parallel.waitForAny(function ()
        repeat
            os.sleep(0)
        until established == true
    end,
    connectionWatchdog)
end

local function sendPacket(protocol, payload_message, payload_data)
    local packet = Packet:new()
    packet:setProtocol(protocol)
    packet:setPayload(payload_message, payload_data)
    packet:send(modem_channels.c2s, modem_channels.s2c)
end

local function requestInfo(control, data)
    if not established then
        return nil
    end

    sendPacket("info", control, data)

    local channel, message
    parallel.waitForAny(
        function ()
            repeat
                _, _, channel, _, message, _ = os.pullEvent("modem_message")
            until channel == modem_channels.s2c and type(message.protocol) == "string" and message.protocol == "info_response"
        end,
        function ()
            repeat
                os.sleep(0)
            until not established
        end
    )
    return message
end

return {
    initialize = initialize,
    sendRequest = function (request)
        sendPacket("request", "single", request)
    end,
    sendControl = function (control, data)
        sendPacket("control", control, data)
    end,
    requestInfo = requestInfo,
    connectionWatchdog = connectionWatchdog,
    isEstablished = function ()
        return established
    end
}