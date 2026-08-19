hs.loadSpoon("WallpaperChooser")

spoon.WallpaperChooser:configure({
  sourceURL = "https://www.smashingmagazine.com/2026/07/desktop-wallpaper-calendars-august-2026/",
  preferredResolutions = { "1680x1050", "1920x1080", "2560x1440", "1920x1200" },
  cacheDir = os.getenv("HOME") .. "/Documents/wallpapers",
  cycleEnabled = true,
  cycleInterval = 60 * 60,
})
:bindHotkeys({
  choose = {{"cmd", "alt", "ctrl"}, "P"},
  cycleOnce = {{"cmd", "alt", "ctrl"}, "B"},
})
:start()

hyper:bind({}, "P", function()
  hyper.triggered = true
  hs.eventtap.keyStroke({"cmd", "alt", "ctrl"}, "P")
end)

hyper:bind({}, "B", function()
  hyper.triggered = true
  hs.eventtap.keyStroke({"cmd", "alt", "ctrl"}, "B")
end)
