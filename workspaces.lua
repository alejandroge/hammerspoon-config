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

function applyLayoutForWorkspace(workspace)
  if currentWorkspace == Workspace.LaptopOnly or currentWorkspace == Workspace.Unknown then
    return -- No layout needed
  end

  local primaryScreen = hs.screen.primaryScreen()
  local secondaryScreen = nil

  -- Find another screen that isn't the primary
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:id() ~= primaryScreen:id() then
      secondaryScreen = screen
      break
    end
  end

  if not secondaryScreen then return end

  -- Apps to move to primary
  local primaryApps = { App.Terminal, App.Browser, App.IDE, App.Notes }
  local secondaryApps = { App.Music, App.Slack }

  for _, appName in ipairs(primaryApps) do
    moveAppToScreen(appName, primaryScreen)
  end

  for _, appName in ipairs(secondaryApps) do
    moveAppToScreen(appName, secondaryScreen)
  end
end

function moveAppToScreen(appName, targetScreen)
  local app = hs.application.get(appName)
  if not app then return end -- App not running

  for _, win in ipairs(app:allWindows()) do
    if win:isStandard() then
      win:moveToScreen(targetScreen)
    end
  end
end

function initWorkspaces()
    detectAndSaveWorkspace()
    updateMenubar()
    applyLayoutForWorkspace()
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
