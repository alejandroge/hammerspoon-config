hs.loadSpoon("GlabToggl")

local secrets = dofile(os.getenv("HOME") .. "/.hammerspoon/secrets.lua")
spoon.GlabToggl:configure({
    assignee            = "alejandro.ge",
    togglApiToken       = secrets.togglApiToken,
    togglWorkspaceId    = secrets.togglWorkspaceId,
    gitlabToken         = secrets.gitlabToken,
})
:bindHotkeys({
    openChooser = {{"cmd", "alt", "ctrl"}, "I"},
    stopCurrent = {{"cmd", "alt", "ctrl"}, "O"},
})
:start()

hyper:bind({}, "I", function()
    hyper.triggered = true
    hs.eventtap.keyStroke({"cmd", "alt", "ctrl"}, "I")
end)

hyper:bind({}, "O", function()
    hyper.triggered = true
    hs.eventtap.keyStroke({"cmd", "alt", "ctrl"}, "O")
end)

