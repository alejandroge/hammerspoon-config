hs.loadSpoon("GlabToggl")

spoon.GlabToggl:configure({
  assignee       = "alejandro.ge",
})
:bindHotkeys({
  run  = {{"cmd", "alt", "ctrl"}, "I"},
  stop = {{"cmd", "alt", "ctrl"}, "O"},
})

hyper:bind({}, "I", function()
  hyper.triggered = true
  hs.eventtap.keyStroke({"cmd", "alt", "ctrl"}, "I")
end)

hyper:bind({}, "O", function()
  hyper.triggered = true
  hs.eventtap.keyStroke({"cmd", "alt", "ctrl"}, "O")
end)

