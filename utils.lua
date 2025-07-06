function readOnlyTable(table)
    return setmetatable({}, {
        __index = table,
        __newindex = function(_, key, _)
            error("Attempt to modify read-only table: " .. tostring(key))
        end,
        __metatable = false
    })
end
