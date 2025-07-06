local secrets = dofile(os.getenv("HOME") .. "/.hammerspoon/secrets.lua")
local wifiHome = secrets.wifiHome

Workspace = readOnlyTable({
    Laptop = "laptop",
    Home = "home",
    Office = "office",
})

-- Main detection function
function detectWorkspace()
    local screens = hs.screen.allScreens()
    local screenCount = #screens
    local wifi = hs.wifi.currentNetwork()

    -- Laptop-only scenario
    if screenCount == 1 then
        return Workspace.Laptop
    end

    -- Multiple monitors
    if wifi == wifiHome then
        return Workspace.Home
    else
        return Workspace.Office
    end
end

currentWorkspace = "unknown"
workspaceMenu = hs.menubar.new()

local function detectAndSaveWorkspace()
    local ws = detectWorkspace()
    currentWorkspace = ws
end

function updateMenubar()
    if workspaceMenu then
        workspaceMenu:setTitle("📍 " .. (currentWorkspace or "unknown"))

        workspaceMenu:setMenu({
            {
                title = "Manually detect workspace",
                fn = function()
                    detectAndSaveWorkspace()
                    updateMenubar()
                    hs.alert.show("Workspace detected: " .. currentWorkspace)
                end
            }
            -- { title = "-" }, -- separator
        })
    end
end

function initWorkspaces()
    detectAndSaveWorkspace()
    updateMenubar()
end

initWorkspaces()

hyper:bind({}, "W", function()
    hyper.triggered = true
    hs.alert.show("Current workspace: " .. currentWorkspace)
end)

-- Watcher setup
local screenWatcher = hs.screen.watcher.new(function()
    detectAndSaveWorkspace()
    updateMenubar()
    hs.alert.show("Workspace detected: " .. currentWorkspace)
end)
screenWatcher:start()
