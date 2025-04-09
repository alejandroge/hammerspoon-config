-- Helper to move and resize window
local function moveWindow(fn)
  return function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local screen = win:screen()
    local max = screen:frame()
    local f = fn(max)
    win:setFrame(f)
  end
end

-- split to the left
hyper:bind({}, "Left", moveWindow(function(max)
  hyper.triggered = true
  return { x = max.x, y = max.y, w = max.w / 2, h = max.h }
end))

-- split to the right
hyper:bind({}, "Right", moveWindow(function(max)
  hyper.triggered = true
  return { x = max.x + (max.w / 2), y = max.y, w = max.w / 2, h = max.h }
end))

-- cover all the screen, without maximizing
hyper:bind({}, "Up", moveWindow(function(max)
  hyper.triggered = true
  return { x = max.x, y = max.y, w = max.w, h = max.h }
end))

-- minize current window
hyper:bind({}, "Down", function()
  hyper.triggered = true
  local win = hs.window.focusedWindow()
  win:minimize()
end)
