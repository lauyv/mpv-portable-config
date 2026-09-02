-- sub-fonts-dir-auto.lua
--
-- Automatically use a fonts directory next to the playing file as
-- `sub-fonts-dir` (mpv >= 0.34).
--
-- On file load, looks for a `Fonts` directory (case-insensitive match) in the
-- same directory as the video and sets it file-locally, unless the option was
-- given explicitly on the command line.
--
-- Config (script-opts/sub-fonts-dir-auto.conf):
--   fonts_dir_name=Fonts    # directory name to look for
--
-- Core logic from Frédéric Brière's script of the same name; trimmed to
-- modern mpv and hardened for URLs and directory inputs.

local utils = require "mp.utils"
local msg = require "mp.msg"

local o = { fonts_dir_name = "Fonts" }
require("mp.options").read_options(o, "sub-fonts-dir-auto")

local function find_fonts_dir(dir)
    local entries = utils.readdir(dir, "dirs")
    if not entries then
        return nil
    end
    for _, entry in ipairs(entries) do
        if entry:lower() == o.fonts_dir_name:lower() then
            return utils.join_path(dir, entry)
        end
    end
end

local function set_file_local(name, value)
    -- an explicit command-line value wins over the auto-detection
    if mp.get_property_bool("option-info/" .. name .. "/set-from-commandline") then
        msg.debug("not overriding command-line value of " .. name)
        return
    end
    mp.set_property("file-local-options/" .. name, value)
    msg.verbose("set " .. name .. " to " .. value)
end

mp.add_hook("on_load", 50, function()
    local path = mp.get_property("path")
    if not path or path == "" or path:match("^%a[%w+.-]*://") then
        return -- no path or a URL: no local Fonts folder to find
    end

    -- skip when the path is a directory being played as a playlist
    if utils.readdir(path .. "/.") ~= nil then
        msg.debug("path is a directory, skipping")
        return
    end

    local dir = utils.split_path(path):gsub("(.)/+$", "%1")
    local fonts_dir = find_fonts_dir(dir)
    if fonts_dir then
        set_file_local("sub-fonts-dir", fonts_dir)
    else
        msg.debug("no " .. o.fonts_dir_name .. " directory in " .. dir)
    end
end)
