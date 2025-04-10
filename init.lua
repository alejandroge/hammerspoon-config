-- setup
require("hyper-key")

-- commands
hyper:bind({}, "W", function()
  hs.alert.show("Hello World!")
end)

hyper:bind({}, "L", function()
  hs.caffeinate.lockScreen()
  hyper.triggered = true
end)

require("windows")
require("clipboard-tool")
require("app-launcher")
require("quick-search")

hyper:bind({}, "R", function()
  hyper.triggered = true
  hs.reload()
end)
hs.alert.show("Config loaded")
