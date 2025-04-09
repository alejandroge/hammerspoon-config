-- https://www.hammerspoon.org/Spoons/ClipboardTool.html
hs.loadSpoon("ClipboardTool")

spoon.ClipboardTool:bindHotkeys({
    toggle_clipboard = { {"cmd", "alt", "ctrl"}, "H"}
})

spoon.ClipboardTool:start()
hyper:bind({}, "H", function()
  hyper.triggered = true
  hs.eventtap.keyStroke({"cmd", "alt", "ctrl"}, "H")
end)
