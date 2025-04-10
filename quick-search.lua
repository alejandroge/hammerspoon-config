local function urlEncode(str)
  return hs.http.encodeForQuery(str)
end

hyper:bind({}, "F", function()
  hyper.triggered = true
  globalQuery = ""  -- Your search query

  -- Define the website options
  local siteChoices = {
    { title = "ChatGPT", url = "https://chat.openai.com/?q=" },
    { title = "Perplexity", url = "https://www.perplexity.ai/?q=" },
    { title = "Google", url = "https://www.google.com/search?q=" }
  }

  -- Create the chooser
  local chooser = hs.chooser.new(function(choice)
    if not choice then return end  -- Exit if no choice is made

    -- Build the URL with the selected website and the encoded query
    local encodedQuery = hs.http.encodeForQuery(globalQuery)  -- URL-encode the query
    local fullUrl = choice.url .. encodedQuery

    -- Launch Chrome with the selected website
    local cmd = string.format("open -na 'Google Chrome' '%s'", fullUrl)
    hs.execute(cmd)
  end)

  chooser:placeholderText("Search for:")  -- Placeholder text in the chooser
  chooser:queryChangedCallback(function(query)
    if query == "" then
      --
    else
      globalQuery = query  -- Update the global query variable
    end
  end)

  -- Populate the chooser with the site options
  local chooserItems = {}
  for _, site in ipairs(siteChoices) do
    table.insert(chooserItems, { text = site.title, url = site.url })
  end

  chooser:choices(chooserItems)
  chooser:show()  -- Show the chooser
end)
