local obj = {}
obj.__index = obj

obj.name = "GlabToggl"
obj.version = "0.1"
obj.author = "Alejandro Guevara <alejandro.guevara.esc@gmail.com>"
obj.homepage = "local"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local secrets = dofile(os.getenv("HOME") .. "/.hammerspoon/secrets.lua")

----------------------------------------------------------------
-- Defaults (override via obj:configure({...}) in init.lua)
----------------------------------------------------------------
obj.config = {
    togglApiToken     = secrets.togglApiToken,
    togglWorkspaceId  = secrets.togglWorkspaceId,
    gitlabToken       = secrets.gitlabToken,
    gitlabBase        = "https://gitlab.com/api/v4",
    createdWith       = "hammerspoon",
    billable          = false,
    copyUrlOnSelect   = true,                           -- copy URL to clipboard
    logPrefix         = "[GlabToggl] ",
}

----------------------------------------------------------------
-- Internals
----------------------------------------------------------------
local json   = hs.json
local task   = hs.task
local http   = hs.http
local base64 = hs.base64
local chooser = hs.chooser
local alert  = hs.alert
local menubar = hs.menubar
local log    = hs.logger.new("GlabToggl", "info")

obj._statusItem = nil
obj._currentTimerDescription = nil

local function ensureStatusItem(self)
    if not self._statusItem then
        self._statusItem = menubar.new()
    end
    return self._statusItem
end

function obj:_updateStatusDisplay()
    local item = ensureStatusItem(self)
    if not item then return end

    if self._currentTimerDescription and self._currentTimerDescription ~= "" then
        local tooltip = string.format("Tracking: %s", self._currentTimerDescription)
        item:setTitle("Toggl: tracking")
        item:setTooltip(tooltip)
        item:setMenu({
            { title = self._currentTimerDescription, disabled = true },
        })
    else
        item:setTitle("Toggl: idle")
        item:setTooltip("No GlabToggl timer running")
        item:setMenu({
            { title = "No timer running", disabled = true },
        })
    end
end

function obj:_setRunningDescription(desc)
    self._currentTimerDescription = desc
    self:_updateStatusDisplay()
end

local function L(cfg, msg)
    log.i((cfg.logPrefix or "") .. msg)
end

local function iso_now_utc()
    return os.date("!%Y-%m-%dT%H:%M:%S.000Z")
end

local function togglAuthHeader(cfg)
    if not cfg.togglApiToken then return nil end
    return "Basic " .. base64.encode(cfg.togglApiToken .. ":api_token")
end

local function gitlabAuthHeaders(cfg)
    if not cfg.gitlabToken then return nil end
    return "Bearer " .. cfg.gitlabToken
end

local function parseIssues(raw)
    local decoded = json.decode(raw) or {}
    local choices = {}
    for _, it in ipairs(decoded) do
        local title = it.title or "(no title)"
        local iid   = it.iid
        local url   = it.web_url or it.webUrl
        local proj  = (it.references and it.references.full)
        or (it.project and it.project.path_with_namespace)
        or (it.references and it.references.relative)
        or ""
        local labels = ""
        if type(it.labels) == "table" and #it.labels > 0 then
            labels = table.concat(it.labels, ", ")
        end
        local sub = string.format("#%s · %s", tostring(iid or "?"), labels)
        table.insert(choices, {
            text        = title,
            subText     = sub,
            url         = url,
            projectPath = proj,
            iid         = iid,
        })
    end
    return choices
end

local function parseInt(h) return (h and h ~= "" and tonumber(h)) or nil end

local function fetchIssues(cfg, cb)
    local auth = gitlabAuthHeaders(cfg)
    if not auth then
        alert.show("Missing GITLAB_TOKEN")
        return
    end

    local base = cfg.gitlabBase:gsub("/+$","")
    local url  = base .. "/issues"

    -- Build query
    local qs = {
        "state=opened",
        "order_by=updated_at",
        "per_page=100",
        "scope=assigned_to_me",
    }

    local results = {}

    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = auth,
    }

    local function getPage()
        local full = url .. "?" .. table.concat(qs, "&")
        hs.http.asyncGet(full, headers, function(status, body, headers)
            if status < 200 or status >= 300 then
                hs.alert.show("GitLab API error " .. tostring(status))
                L(cfg, ("GitLab error %s body: %s"):format(status, body or "(nil)"))
                return
            end
            local chunk = hs.json.decode(body) or {}
            for _, it in ipairs(chunk) do table.insert(results, it) end
            cb(hs.json.encode(results)) -- reuse existing parseIssues(jsonString)
        end)
    end

    getPage()
end

local function startTogglTimer(self, cfg, desc)
    if not cfg.togglWorkspaceId then
        alert.show("Missing TOGGL_WORKSPACE_ID")
        return
    end
    local auth = togglAuthHeader(cfg)
    if not auth then
        alert.show("Missing TOGGL_API_TOKEN")
        return
    end

    local url = ("https://api.track.toggl.com/api/v9/workspaces/%s/time_entries"):format(cfg.togglWorkspaceId)
    local bodyTbl = {
        description   = desc,
        created_with  = cfg.createdWith,
        start         = iso_now_utc(),
        duration      = -1, -- running entry
        workspace_id  = tonumber(cfg.togglWorkspaceId),
        billable      = cfg.billable,
    }
    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = auth,
    }
    local body = json.encode(bodyTbl, true)
    http.doAsyncRequest(url, "POST", body, headers, function(status, resp, _)
        if status >= 200 and status < 300 then
            self:_setRunningDescription(desc)
            L(cfg, "Started: " .. (desc or ""))
        else
            alert.show("Toggl error " .. tostring(status))
            L(cfg, "Response: " .. (resp or ""))
        end
    end)
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function obj:configure(o)
    for k,v in pairs(o or {}) do self.config[k] = v end
    return self
end

function obj:start()
    local cfg = self.config
    fetchIssues(cfg, function(raw)
        local choices = parseIssues(raw)

        local c = chooser.new(function(choice)
            if not choice then return end
            local desc = string.format("%s #%s", choice.text, tostring(choice.iid or ""))

            startTogglTimer(self, cfg, desc)
            if cfg.copyUrlOnSelect and choice.url then hs.pasteboard.setContents(choice.url) end
        end)

        c:placeholderText("Select a GitLab issue")
        c:choices(choices)
        c:show()
    end)
end

function obj:stopCurrent()
    local cfg = self.config
    local auth = togglAuthHeader(cfg)
    if not auth then alert.show("Missing TOGGL_API_TOKEN"); return end
    if not cfg.togglWorkspaceId then alert.show("Missing TOGGL_WORKSPACE_ID"); return end

    local headers = { ["Authorization"] = auth }
    local currentTimeEntryUrl = "https://api.track.toggl.com/api/v9/me/time_entries/current"

    http.doAsyncRequest(currentTimeEntryUrl, "GET", nil, headers, function(status, resp, _)
        if status < 200 or status >= 300 then alert.show("Toggl list error " .. status); return end

        local running = json.decode(resp) or nil
        if not running or running.duration >= 0 then alert.show("No running entry"); return end

        local stopUrl = (
        "https://api.track.toggl.com/api/v9/workspaces/%s/time_entries/%s/stop"
        ):format(cfg.togglWorkspaceId, running.id)

        local spoon = self
        http.doAsyncRequest(
        stopUrl,
        "PATCH",
        "{}",
        {["Authorization"]=auth, ["Content-Type"]="application/json"},
        function(st, _, _)
            if st >= 200 and st < 300 then
                spoon:_setRunningDescription(nil)
            else
                alert.show("Stop failed " .. st)
            end
        end
        )
    end)
end

function obj:bindHotkeys(mapping)
    local spec = {
        run  = function() self:start() end,
        stop = function() self:stopCurrent() end,
    }
    hs.spoons.bindHotkeysToSpec(spec, mapping or {})
    return self
end

obj:_setRunningDescription(nil)

return obj
