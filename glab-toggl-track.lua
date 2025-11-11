hs.loadSpoon("GlabToggl")

local secrets = dofile(os.getenv("HOME") .. "/.hammerspoon/secrets.lua")
spoon.GlabToggl:configure({
    assignee            = "alejandro.ge",
    togglApiToken       = secrets.togglApiToken,
    togglWorkspaceId    = secrets.togglWorkspaceId,
    gitlabToken         = secrets.gitlabToken,
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

