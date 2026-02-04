--------------------------------------------------------------------------------
-- Windsurf Cascade Integration for Hammerspoon
-- Copy this to ~/.hammerspoon/init.lua on your Mac (or append to existing)
--------------------------------------------------------------------------------

local cascadePrefix = "::cascade::"
local lastClipboard = ""

local function openWindsurfCascade(text)
    -- Store the actual text to paste
    hs.pasteboard.setContents(text)
    
    -- Activate Windsurf
    local windsurf = hs.application.get("Windsurf")
    if windsurf then
        windsurf:activate()
    else
        hs.application.launchOrFocus("Windsurf")
    end
    
    -- Wait for Windsurf to be ready, then focus Cascade input
    hs.timer.doAfter(0.3, function()
        -- First focus the editor to ensure Cmd+L will open (not close) Cascade
        hs.eventtap.keyStroke({"cmd"}, "1")
        hs.timer.doAfter(0.1, function()
            -- Cmd+L focuses the Cascade chat input in Windsurf
            hs.eventtap.keyStroke({"cmd"}, "l")
            hs.timer.doAfter(0.2, function()
                -- Paste the text
                hs.eventtap.keyStroke({"cmd"}, "v")
            end)
        end)
    end)
end

-- Clipboard watcher
cascadeWatcher = hs.timer.new(0.5, function()
    local content = hs.pasteboard.getContents()
    if content and content ~= lastClipboard then
        lastClipboard = content
        if content:sub(1, #cascadePrefix) == cascadePrefix then
            local text = content:sub(#cascadePrefix + 1)
            hs.pasteboard.setContents("")  -- Clear to prevent re-trigger
            lastClipboard = ""
            openWindsurfCascade(text)
        end
    end
end)

cascadeWatcher:start()
hs.alert.show("Cascade watcher started")
