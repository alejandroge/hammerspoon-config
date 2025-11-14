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

obj._menubarItem = nil
obj._currentTimerDescription = nil

local function ensureStatusItem(self)
    if not self._menubarItem then
        self._menubarItem = menubar.new()
    end
    return self._menubarItem
end

function obj:_updateStatusDisplay()
    local item = ensureStatusItem(self)
    if not item then return end

    if self._currentTimerDescription and self._currentTimerDescription ~= "" then
        local tooltip = string.format("Tracking: %s", self._currentTimerDescription)
        item:setTitle("GlabToggl: tracking")
        item:setTooltip(tooltip)
        item:setMenu({
            { title = self._currentTimerDescription, disabled = true },
        })
    else
        item:setTitle("GlabToggl: idle")
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

local function saveIssuesToCache(cfg, raw)
    local key = cacheKey(cfg)
    local ok, err = pcall(function()
        hs.settings.set(key, {
            raw = raw,
            fetchedAt = os.time(),
        })
    end)
    if not ok then logger.i("Failed to persist issues cache: " .. tostring(err)) end
end

local function parseInt(h) return (h and h ~= "" and tonumber(h)) or nil end

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
        created_with  = "hammerspoon (GlabToggl)",
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

local function getConfigErrors(cfg)
    local errors = {}

    if not cfg.togglApiToken or cfg.togglApiToken == "" then
        table.insert(errors, "togglApiToken is required")
    end

    if not cfg.togglWorkspaceId or cfg.togglWorkspaceId == "" then
        table.insert(errors, "togglWorkspaceId is required")
    end

    if not cfg.gitlabToken or cfg.gitlabToken == "" then
        table.insert(errors, "gitlabToken is required")
    end

    return errors
end

local function fetchIssues(cfg, onSuccess, onError)
    local auth = gitlabAuthHeaders(cfg)
    local base = cfg.gitlabBase:gsub("/+$","")
    local url  = base .. "/issues"

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

            if onSuccess then onSuccess(hs.json.encode(results)) end
        end)
    end

    getPage()
end

local function getCachedIssuesRaw(cfg)
    local key = cacheKey(cfg)
    local ok, entry = pcall(function() 
        return hs.settings.get(key)
    end)

    if not ok then
        logger.i("Failed to read issues cache: " .. tostring(entry))
        return nil, true
    end

    if type(entry) ~= "table" or type(entry.raw) ~= "string" then return nil end

    local ttl = cfg.issuesCacheTTL
    local isFresh = false

    if ttl and ttl > 0 and entry.fetchedAt then
        local age = os.time() - (entry.fetchedAt or 0)
        isFresh = age <= ttl
    end

    return entry.raw, not isFresh
end

local function getGitlabIssues(cfg, onSuccess)
    local cachedIssues, shouldFetch = getCachedIssuesRaw(cfg)

    if shouldFetch then
        logger.i("No valid cached GitLab issues found; fetching latest")

        fetchIssues(cfg, function(raw)
            saveIssuesToCache(cfg, raw)
            local freshChoices = parseIssues(raw)

            logger.i("fetched...." .. tostring(#freshChoices) .. " issues")
            if #freshChoices <= 0 then
                logger.i("No assigned GitLab issues", "Just refreshed")
            end
            onSuccess(freshChoices)
        end, function(err)
            if cachedChoices and #cachedChoices > 0 then return end
            logger.i("Unable to load GitLab issues", err or "Request failed")
        end)
    else
        logger.i("Using cached GitLab issues")
        local parsedIssues = cachedIssues and parseIssues(cachedIssues) or nil
        onSuccess(parsedIssues)
    end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function obj:configure(o)
    for k,v in pairs(o or {}) do self.config[k] = v end
    return self
end

function obj:start()
    self._menubarItem = menubar.new()

    local errors = getConfigErrors(self.config)
    if #errors > 0 then
        self._menubarItem:setTitle("GlabToggl: ⚠")
        self._menubarItem:setTooltip("Some issues were found in the GlabToggl configuration")

        local menuItems = {}
        for _, err in ipairs(errors) do
            logger.e("Configuration error: " .. err)
            table.insert(menuItems, { title = err, disabled = true })
        end

        table.insert(menuItems, { title = "-" }) -- separator
        table.insert(menuItems, { title = "Please update the configuration", disabled = true })

        self._menubarItem:setMenu(menuItems)
        return
    end

    self:_setRunningDescription(nil)
end

function obj:openChooser()
    local cfg = self.config

    local gitlabIssues = {}
    getGitlabIssues(cfg, function(issues)
        logger.i("returned from getGitlabIssues callback")
        gitlabIssues = issues or {}

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
        if gitlabIssues and #gitlabIssues > 0 then
            c:choices(gitlabIssues)
        else
            c:choices({ statusChoice("No assigned GitLab issues") })
        end

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
        openChooser = function() self:openChooser() end,
        stopCurrent = function() self:stopCurrent() end,
    }
    hs.spoons.bindHotkeysToSpec(spec, mapping or {})
    return self
end

return obj
