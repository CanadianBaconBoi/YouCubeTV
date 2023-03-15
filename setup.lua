local completion = require "cc.completion"
local github_base_url = "https://raw.githubusercontent.com/CanadianBaconBoi/YouCubeTV/master/"

local files = {
    remote = {
        "startup.lua",
        "remoteapi.lua"
    },
    television = {
        "startup.lua",
        "lib/argparse.lua",
        "lib/numberformatter.lua",
        "lib/semver.lua",
        "lib/string_pack.lua",
        "lib/youcubeapi.lua"
    }
}

local settings = {
    remote = {},
    television = {
        server = {
            prompt = "YouCube ingest server to use",
            default = "wss://youcube.knijn.one"
        },
        channels = {
            c2s = {
                prompt = "Remote to TV modem channel",
                default = 35284
            },
            s2c = {
                prompt = "TV to Remote modem channel",
                default = 35285
            }
        },
        default_volume = {
            prompt = "Default Audio Volume",
            default = 100
        },
        playback_buffer_size = {
            prompt = "Playback buffer size in frames (30 frames = 1 second)",
            default = 60
        },
        max_back = {
            prompt = "Maximum size of back buffer (only for playlists)",
            default = 32
        },
        maximum_control_distance = {
            prompt = "Maximum distance TV can be controlled",
            default = 40
        }
    }
}

--#region Helper Functions
local function userPrompt(prompt_text, completions, validity_function)
    print(prompt_text)

    local selection
    if not validity_function then
        validity_function = function(text)
            if completions[text] then
                return true
            else
                return false
            end
        end
    end
    while true do
        write("> ")
        selection = read(nil, nil, function(text) return completion.choice(text, completions) end)
        if validity_function(selection) then
            return selection
        else
            print(selection .. " is not a valid selection")
        end
    end
end

local function setSetting(setting_data)
    if setting_data.prompt then
        return userPrompt(setting_data.prompt .. " (default: " .. setting_data.default .. ")", { setting_data.default },
            function(text)
                return type(text) == type(setting_data.default)
            end)
    else
        for setting_name, data in pairs(setting_data) do
            setSetting(setting_data)
        end
    end
end

local function downloadFile(sUrl, outputPath)
    write("Downloading file " .. outputPath .. "... ")

    local ok, err = http.checkURL(sUrl)
    if not ok then
        error("Failed to find file at '"..sUrl.."'.")
    end

    local response = http.get(sUrl, nil, true)
    if not response then
        error("Failed to download file '"..outputPath.."'.")
    end

    print("Downloaded file " .. outputPath .. "!")

    local sResponse = response.readAll()
    response.close()

    local file = fs.open(outputPath, "wb")
    file.write(sResponse)
    file.close()
end
--#endregion

print("YouCubeTV Install Script")
local side = userPrompt("Select a side, one of 'television' or 'remote'", { "remote", "television" })
github_base_url = github_base_url .. side .. "/"

--#region Settings
if fs.exists("/settings.lua") then
    fs.delete("/settings.lua")
end
local settings_file = io.open("/settings.lua", "w")
local advanced = userPrompt("[Advanced Users] Modify Settings?", { "yes", "no" })
if advanced == "yes" then
    for _, data in pairs(settings[side]) do
        data.value = setSetting(data)
    end
else
    for _, data in pairs(settings[side]) do
        data.value = data.default
    end
end
local settings_file_string = "return {"
for setting_name, data in pairs(settings[side]) do
    settings_file_string = settings_file_string .. string.char(10)
        .. "  --" .. data.prompt .. string.char(10)
        .. "  " .. setting_name .. " = " .. data.value
end
settings_file_string = settings_file_string .. string.char(10) .. "}"
--#endregion

--#region Download
for _, value in pairs(files[side]) do
    if fs.exists(value) then
        local overwrite = userPrompt("File '" .. value .. "' already exists, would you like to overwrite? [y/n]",
        { "y", "n" })
        if overwrite == "y" then
            fs.delete(value)
        else
            error("User did not agree to overwrite file '" .. value "'")
        end
        return
    end
end

for _, value in pairs(files[side]) do
    downloadFile(github_base_url .. value, value)
end
--#endregion

print("Succesfully installed, press any key to reboot")
os.pullEvent("key")
os.reboot()
