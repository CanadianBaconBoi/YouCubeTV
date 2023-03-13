local modem
local modem_channels = {
    c2s = 35284,
    s2c = 35285
}
local maximum_control_distance = 40

local Packet = {
    protocol = "",
    payload = nil
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

function Packet:setPayload (payload)
    if type(payload) == "string" or type(payload) == "table" then
        self.payload = payload
    end
end

function Packet:send (channel, replyChannel)
    if type(self.protocol == "string") then
        if type(self.payload) == "string"
        or (type(self.payload) == "table" and type(self.payload.type) == "string") then
            modem.transmit(channel, replyChannel, self)
        end
    end
end

local function initialize()
    modem = peripheral.find("modem") or error("No modem attached", 0)
    modem.open(modem_channels.s2c)

    local channel, message
    local pingTimer
    repeat
        pingTimer = os.startTimer(1)
        modem.transmit(modem_channels.c2s, modem_channels.s2c, {protocol = "ping", payload = 1})
        _, _, channel, _, message = os.pullEvent()
    until message and message.protocol and message.protocol == "pong" and channel == modem_channels.s2c
    os.cancelTimer(pingTimer)
end

local function sendPacket(protocol, payload)
    local packet = Packet:new()
    packet:setProtocol(protocol)
    packet:setPayload(payload)
    packet:send(modem_channels.c2s, modem_channels.s2c)
end

local function sendRequest(request)
    local packet = Packet:new()
    packet:setProtocol("request")
    packet:setPayload(request)
    packet:send(modem_channels.c2s, modem_channels.s2c)
end

local function sendControl(control)
    local packet = Packet:new()
    packet:setProtocol("control")
    packet:setPayload(control)
    packet:send(modem_channels.c2s, modem_channels.s2c)
end

local function requestInfo(control)
    local packet = Packet:new()
    packet:setProtocol("info")
    packet:setPayload(control)
    packet:send(modem_channels.c2s, modem_channels.s2c)

    local channel, replyChannel, message, distance
    repeat
        _, _, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    until channel == modem_channels.s2c
    return message
end


return {
    initialize = initialize,
    sendRequest = sendRequest,
    sendControl = sendControl,
    requestInfo = requestInfo
}