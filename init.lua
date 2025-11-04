-- trigger hammerspoon to ask for location permission
-- https://github.com/Hammerspoon/hammerspoon/issues/3537
print(hs.location.get())

-- setup
require("hyper-key")
require("utils")

hyper:bind({}, "L", function()
  hs.caffeinate.lockScreen()
  hyper.triggered = true
end)

require("app-launcher")
require("clipboard-tool")
require("glab-toggl-track")
require("quick-search")
require("text-transformation")
require("windows")
require("workspaces")

hyper:bind({}, "R", function()
  hyper.triggered = true
  hs.reload()
end)
hs.alert.show("Config loaded")
