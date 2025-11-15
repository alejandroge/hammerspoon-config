local obj = {}
obj.__index = obj

obj.name = "GlabToggl"
obj.version = "0.1"
obj.author = "Alejandro Guevara <alejandro.guevara.esc@gmail.com>"
obj.homepage = "local"
obj.license = "MIT - https://opensource.org/licenses/MIT"

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
local logger = hs.logger.new("GlabToggl", "info")

obj._menubarItem = nil
obj._currentTimerDescription = nil
obj._runningGitlabIssue = nil

function obj:_ensureStatusItem()
    if not self._menubarItem then
        self._menubarItem = hs.menubar.new()
    end
    return self._menubarItem
end

function obj:_setMenubarItemStatus(runningGitlabIssue)
    local item = self:_ensureStatusItem()
    if not item then return end

    if not runningGitlabIssue then
        item:setTitle("GlabToggl: idle")
        item:setTooltip("No timer running")
    else
        local desc = string.format("%s #%s", runningGitlabIssue.text, tostring(runningGitlabIssue.iid or ""))

        item:setTitle("GlabToggl: tracking")
        item:setTooltip("Tracking: " .. runningGitlabIssue.text)
    end
end

function obj:_setMenubarItemIssuesList(gitlabIssues)
    local item = self:_ensureStatusItem()
    if not item then return end

    if gitlabIssues and #gitlabIssues > 0 then
        local menuItems = {}
        for _, issue in ipairs(gitlabIssues) do
            table.insert(menuItems, {
                title = issue.text .. " #" .. tostring(issue.iid or ""),
                disabled = true,
            })
        end
        item:setMenu(menuItems)
    else
        item:setMenu({
            { title = "No assigned GitLab issues", disabled = true },
        })
    end
end

function obj:_setRunningDescription(desc)
    self._currentTimerDescription = desc
    self:_setMenubarItemStatus(desc)
end

local function iso_now_utc()
    return os.date("!%Y-%m-%dT%H:%M:%S.000Z")
end

local function togglAuthHeader(cfg)
    if not cfg.togglApiToken then return nil end
    if cfg.togglApiToken == "" then return nil end

    return "Basic " .. hs.base64.encode(cfg.togglApiToken .. ":api_token")
end

local function parseInt(h) return (h and h ~= "" and tonumber(h)) or nil end

local function startTogglTimer(self, cfg, desc, callback)
    local auth = togglAuthHeader(cfg)

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
    hs.http.doAsyncRequest(url, "POST", body, headers, function(status, resp, _)
        if status >= 200 and status < 300 then
            logger.i("Started: " .. (desc or ""))
            if callback then callback(true) end
        else
            logger.i("Response: " .. (resp or ""))
            if callback then callback(false) end
        end
    end)
end

local function stopTogglTimer(self, cfg, callback)
    local auth = togglAuthHeader(cfg)

    local currentTimeEntryUrl = "https://api.track.toggl.com/api/v9/me/time_entries/current"
    local headers = {
        ["Authorization"] = auth,
        ["Content-Type"] = "application/json",
    }

    hs.http.doAsyncRequest(currentTimeEntryUrl, "GET", nil, headers, function(status, resp, _)
        if status < 200 or status >= 300 then
            hs.alert.show("Toggl list error " .. status)
            logger.e("Failed to get current time entry: " .. tostring(resp))
            callback(false)
            return
        end

        local running = hs.json.decode(resp) or nil
        if not running or running.duration >= 0 then
            callback(true)
            return
        end

        local stopUrl = (
            "https://api.track.toggl.com/api/v9/workspaces/%s/time_entries/%s/stop"
        ):format(cfg.togglWorkspaceId, running.id)

        hs.http.doAsyncRequest(
            stopUrl,
            "PATCH",
            "{}",
            headers,
            function(st, _, _)
                if st >= 200 and st < 300 then
                    callback(true)
                else
                    hs.alert.show("Stop failed " .. st)
                    logger.e("Failed to stop time entry: " .. tostring(st))
                    callback(false)
                end
            end
        )
    end)
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
        hs.alert.show(msg)
        logger.e(("%s body: %s"):format(msg, body or "(nil)"))
        if onError then onError(msg) end
    end

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

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function obj:configure(o)
    for k,v in pairs(o or {}) do self.config[k] = v end
    return self
end

function obj:start()
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

    self._runningGitlabIssue = nil
    self:_setMenubarItemStatus(nil)
end

function obj:openChooser()
    local cfg = self.config

    local gitlabIssues = {}
    getGitlabIssues(cfg, function(gitlabIssues)
        local function statusChoice(text, sub)
            return { text = text, subText = sub or "", _status = true }
        end

        local c = hs.chooser.new(function(selectedGitlabIssue)
            if not selectedGitlabIssue or selectedGitlabIssue._status then return end
            local desc = string.format("%s #%s", selectedGitlabIssue.text, tostring(selectedGitlabIssue.iid or ""))

            startTogglTimer(self, cfg, desc, function(success)
                obj._runningGitlabIssue = selectedGitlabIssue

                if success then
                    if cfg.copyUrlOnSelect and selectedGitlabIssue.url then
                        hs.pasteboard.setContents(selectedGitlabIssue.url)
                    end

                    self:_setMenubarItemStatus(selectedGitlabIssue)
                end
            end)
        end)

        self:_setMenubarItemIssuesList(gitlabIssues)

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
    stopTogglTimer(self, cfg, function(success)
        if success then
            self._runningGitlabIssue = nil
            self:_setMenubarItemStatus(nil)
        end
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
