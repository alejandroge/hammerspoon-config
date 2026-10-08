-- setup
require("hyper-key")
require("utils")
require("hs.ipc")

hyper:bind({}, "L", function()
  hs.caffeinate.lockScreen()
  hyper.triggered = true
end)

require("app-launcher")
require("clipboard-tool")
require("glab-toggl-track")
require("quick-search")
require("text-transformation")
require("wallpaper-chooser")
require("windows")

hyper:bind({}, "R", function()
  hyper.triggered = true
  hs.reload()
end)
hs.alert.show("Config loaded")
