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
    togglApiToken     = "",
    togglWorkspaceId  = "",
    gitlabToken       = "",
    gitlabBase        = "https://gitlab.com/api/v4",
    -- copy gitlab URL to clipboard, after selecting an issue to start a timer for
    copyUrlOnSelect   = true,
    -- seconds; 0 disables cache expiration
    issuesCacheTTL    = 3600,
}

----------------------------------------------------------------
-- Internals
----------------------------------------------------------------
local http   = hs.http
local base64 = hs.base64
local chooser = hs.chooser
local alert  = hs.alert
local menubar = hs.menubar

local logger = hs.logger.new("GlabToggl", "info")

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

local function iso_now_utc()
    return os.date("!%Y-%m-%dT%H:%M:%S.000Z")
end

local function togglAuthHeader(cfg)
    if not cfg.togglApiToken then return nil end
    if cfg.togglApiToken == "" then return nil end

    return "Basic " .. base64.encode(cfg.togglApiToken .. ":api_token")
end

local function gitlabAuthHeaders(cfg)
    if not cfg.gitlabToken then return nil end
    if cfg.gitlabToken == "" then return nil end

    return "Bearer " .. cfg.gitlabToken
end

local function parseIssues(raw)
    local decoded = hs.json.decode(raw) or {}
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

local function cacheKey(cfg)
    return cfg.issuesCacheKey or (obj.name .. ".issuesCache")
end

local function saveIssuesCache(cfg, raw)
    local key = cacheKey(cfg)
    local ok, err = pcall(function()
        hs.settings.set(key, {
            raw = raw,
            fetchedAt = os.time(),
        })
    end)
    if not ok then logger.i("Failed to persist issues cache: " .. tostring(err)) end
end

local function cachedIssuesRaw(cfg)
    local key = cacheKey(cfg)
    local ok, entry = pcall(function() 
        return hs.settings.get(key)
    end)

    if not ok then
        logger.i("Failed to read issues cache: " .. tostring(entry))
        return nil
    end
    if type(entry) ~= "table" or type(entry.raw) ~= "string" then return nil end

    local ttl = cfg.issuesCacheTTL
    local isFresh = true
    if ttl and ttl > 0 and entry.fetchedAt then
        local age = os.time() - (entry.fetchedAt or 0)
        isFresh = age <= ttl
    end

    return entry.raw, isFresh
end

local function shouldFetchIssues(cachedRaw, isFresh)
    if not cachedRaw then return true end
    if isFresh == nil then return true end
    return not isFresh
end

local function parseInt(h) return (h and h ~= "" and tonumber(h)) or nil end

local function fetchIssues(cfg, onSuccess, onError)
    local auth = gitlabAuthHeaders(cfg)
    if not auth then
        local msg = "Missing GITLAB_TOKEN"
        alert.show(msg)
        if onError then onError(msg) end
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

    local function reportError(status, body)
        local msg = "GitLab API error " .. tostring(status)
        alert.show(msg)
        logger.i(("%s body: %s"):format(msg, body or "(nil)"))
        if onError then onError(msg) end
    end

    local function getPage()
        local full = url .. "?" .. table.concat(qs, "&")
        hs.http.asyncGet(full, headers, function(status, body, headers)
            if status < 200 or status >= 300 then
                reportError(status, body)
                return
            end
            local chunk = hs.json.decode(body) or {}
            for _, it in ipairs(chunk) do table.insert(results, it) end
            if onSuccess then onSuccess(hs.json.encode(results)) end -- reuse existing parseIssues(jsonString)
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
        billable      = false,
    }
    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = auth,
    }
    local body = hs.json.encode(bodyTbl, true)
    http.doAsyncRequest(url, "POST", body, headers, function(status, resp, _)
        if status >= 200 and status < 300 then
            self:_setRunningDescription(desc)
            logger.i("Started: " .. (desc or ""))
        else
            alert.show("Toggl error " .. tostring(status))
            logger.i("Response: " .. (resp or ""))
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
    local cachedRaw, cacheFresh = cachedIssuesRaw(cfg)
    local needFetch = shouldFetchIssues(cachedRaw, cacheFresh)
    local cachedChoices = cachedRaw and parseIssues(cachedRaw) or nil

    if cachedRaw then
        if cacheFresh then
            logger.i("Using cached GitLab issues (fresh)")
        else
            logger.i("Using cached GitLab issues (stale, refreshing)")
        end
    else
        logger.i("No cached GitLab issues found; fetching latest")
    end

    local function statusChoice(text, sub)
        return { text = text, subText = sub or "", _status = true }
    end

    local c = chooser.new(function(choice)
        if not choice or choice._status then return end
        local desc = string.format("%s #%s", choice.text, tostring(choice.iid or ""))

        startTogglTimer(self, cfg, desc)
        if cfg.copyUrlOnSelect and choice.url then hs.pasteboard.setContents(choice.url) end
    end)

    c:placeholderText("Select a GitLab issue")
    if cachedChoices then
        if #cachedChoices > 0 then
            c:choices(cachedChoices)
        else
            c:choices({ statusChoice("No assigned GitLab issues", cacheFresh and "Cached results" or "Refreshing…") })
        end
    else
        c:choices({ statusChoice("Loading GitLab issues…", "Fetching latest data") })
    end
    c:show()

    if needFetch then
        fetchIssues(cfg, function(raw)
            saveIssuesCache(cfg, raw)
            local freshChoices = parseIssues(raw)
            if #freshChoices > 0 then
                c:choices(freshChoices)
            else
                c:choices({ statusChoice("No assigned GitLab issues", "Just refreshed") })
            end
        end, function(err)
            if cachedChoices and #cachedChoices > 0 then return end
            c:choices({ statusChoice("Unable to load GitLab issues", err or "Request failed") })
        end)
    end
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

        local running = hs.json.decode(resp) or nil
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
