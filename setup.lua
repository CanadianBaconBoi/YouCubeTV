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
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

local function try_convert(input, output_type)
    local conversion_methods = {
        number = function (input)
            return tonumber(input)
        end,
        string = function (input)
            return tostring(input)
        end,
        boolean = function (input)
            if type(input) == "number" then
                return input ~= 0
            elseif type(input) == "string" then
                if input == "true" or input == "1" then
                    return true
                elseif input == "false" or input == "0" then
                    return false
                else
                    error("'"..input.."' is not a valid boolean value")
                end
            else
                error("Type '"..type(input).."' cannot be converted to 'boolean'")
            end
        end
    }
    if output_type == "nil" then
        return nil
    elseif conversion_methods[output_type] then
        return conversion_methods[output_type](input)
    else
        error("Conversion to '"..output_type.."' is not supported")
    end
end

local function format_value(input)
    local formatter_methods = {
        number = function (input)
            return tostring(input)
        end,
        string = function (input)
            return "\""..input.."\""
        end,
        boolean = function (input)
            if input then
                return "true"
            else
                return "false"
            end
        end,
    }
    if type(input) == "nil" then
        return nil
    elseif formatter_methods[type(input)] then
        return formatter_methods[type(input)](input)
    else
        error("No formatter for type '"..type(input).."'")
    end

end

local function userPrompt(prompt_text, completions, validity_function)
    print(prompt_text)

    local selection
    if not validity_function then
        validity_function = function(text)
            if table.contains(completions, text) then
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

local function setSetting(setting_data, default)
    if setting_data.prompt then
        if default == true then
            setting_data.value = setting_data.default
        else
            setting_data.value = try_convert(userPrompt(setting_data.prompt .. " (default: " .. setting_data.default .. ")", { tostring(setting_data.default) },
                function(text)
                    return type(try_convert(text, type(setting_data.default))) == type(setting_data.default)
                end), type(setting_data.default))
        end
    else
        for _, data in pairs(setting_data) do
            setSetting(data, default)
        end
    end
end

local function generateSettingsString(setting_name, data)
    if data.prompt then
        return  string.char(10) .. "  --" .. data.prompt .. string.char(10)
        .. "  " .. setting_name .. " = " .. format_value(data.value) .. ","
    else
        local retval = string.char(10) .. setting_name .. " = {"
        for setting_name, data in pairs(data) do
            retval = retval .. generateSettingsString(setting_name, data)
        end
        retval = retval .. string.char(10) .. "},"
        return retval
    end
end

local function downloadFile(sUrl, outputPath)
    write("Downloading file " .. outputPath .. "... ")

    local ok, err = http.checkURL(sUrl)
    if not ok then
        error("Failed to find file at '" .. sUrl .. "'.")
    end

    local response = http.get(sUrl, nil, true)
    if not response then
        error("Failed to download file '" .. outputPath .. "'.")
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
local settings_file = fs.open("/settings.lua", "wb")
local default_settings = userPrompt("[Advanced Users] Modify Settings?", { "yes", "no" }) == "no"

for _, data in pairs(settings[side]) do
    setSetting(data, default_settings)
end

local settings_file_string = "return {"
for setting_name, data in pairs(settings[side]) do
    settings_file_string = settings_file_string .. generateSettingsString(setting_name, data)
end
settings_file_string = settings_file_string .. string.char(10) .. "}"

settings_file.write(settings_file_string)
settings_file.close()
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
    end
end

for _, value in pairs(files[side]) do
    downloadFile(github_base_url .. value, value)
end
--#endregion

print("Succesfully installed, press any key to reboot")
os.pullEvent("key")
os.reboot()
