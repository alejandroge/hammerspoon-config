-- This small utility allows to transform text directly in any text field.
-- any transformation can be triggered by typing a specific pattern.

-- Usage:
-- 1. Activate the transformator by pressing Hyper + T.
-- 2. Type your text normally.
-- 3. To trigger a transformation, type a pattern like "/upper{your text}" or "/random{your text}".
-- 4. The text will be transformed and replaced in the text field.

local eventtap = require("hs.eventtap")
local keycodes = require("hs.keycodes")

local secrets = dofile(os.getenv("HOME") .. "/.hammerspoon/secrets.lua")

local function toRandomCase(str)
    local result = ""
    for i = 1, #str do
        local c = str:sub(i,i)
        if math.random() < 0.2 then
            if math.random() < 0.5 then
                result = result .. c:lower()
            else
                result = result .. c:upper()
            end
        elseif i % 2 == 0 then
            result = result .. c:upper()
        else
            result = result .. c:lower()
        end
    end
    return result
end

local function tryTransform(buffer)
    local patterns = {
        upper = function(s) return s:upper() end,
        random = toRandomCase,
        email = function() return secrets.email end,
        address = function() return secrets.address end,
    }

    for key, fn in pairs(patterns) do
        local fullPattern = "/" .. key .. "{(.-)}"
        local content = buffer:match(fullPattern)
        if content then
            local fullMatch = "/" .. key .. "{" .. content .. "}"
            return fullMatch, fn(content)
        end
    end
    return nil
end

-- Buffer for typed characters
local typedBuffer = ""
local MAX_BUFFER_SIZE = 100
local active = false
local transformator = nil

local function createEventTap()
    return eventtap.new({eventtap.event.types.keyDown}, function(event)
        local char = event:getCharacters()
        if not char then return false end

        -- Handle backspace key
        if keycodes.map[char] == "delete" or char == string.char(127) then
            typedBuffer = typedBuffer:sub(1, -2)
            return false
        end

        if #char ~= 1 then return false end

        -- Append to buffer
        typedBuffer = typedBuffer .. char
        if #typedBuffer > MAX_BUFFER_SIZE then
            typedBuffer = typedBuffer:sub(-MAX_BUFFER_SIZE)
        end

        -- Try transformation
        if char == "}" then
            local match, transformed = tryTransform(typedBuffer)
            if match and transformed then
                -- Delete typed characters
                for _ = 1, #match do
                    eventtap.keyStroke({}, "delete", 0)
                end
                -- Type transformed text
                eventtap.keyStrokes(transformed)
                typedBuffer = "" -- reset buffer
                return true
            end
        end

        return false
    end)
end

hyper:bind({}, "T", function()
    if active then
        if transformator then transformator:stop() transformator = nil end
    else
        typedBuffer = ""
        transformator = createEventTap()
        transformator:start()
    end
    active = not active
    hs.alert.show("Text transformator: " .. (active and "ON" or "OFF"))
end)
