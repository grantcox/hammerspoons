-- folders in this location can be opened with keywords
-- eg "code auth" will offer to open the folder /Users/gcox/code/auth-service in VSCode
codeDir = "/Users/gcox/code/"

keywords = {
    -- a mapping of "codeword" => "app name / window title"
    ["git"] = "Sourcetree",
    ["code"] = "Code", -- VSCode
}

function launchKeywordApp(appName, folderPath)
    -- for these CLI commands to work, you need to enable the appropriate
    -- CLI integration in each app
    if appName == "Sourcetree" then
        hs.execute("stree " .. folderPath, true)
    elseif appName == "Code" then
        hs.execute("code " .. folderPath, true)
    end
end


log = hs.logger.new("fuzzy", "debug")

function scandir(directory)
    -- return all subfolders basenames of the given directory
    -- sorted in modified order desc (most recent first)
    local result = {}
    local folders = io.popen("cd " .. codeDir .. " && ls -ldt1 */")
    for filename in folders:lines() do
        -- trim the trailing slash
        filename = filename:sub(1, -2)
        table.insert(result, filename)
    end
    folders:close()
    return result
end

function len(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end


_currentWindows = {}
_codeFolders = scandir(codeDir)
_windowChooser = nil
_lastFocusedWindow = nil


function _filterWindows(query)
    searchInWindows = _currentWindows
    queryWords = string.gmatch(query:lower(), "%S+")
    nonKeywords = {}

    -- if the query includes one of these keywords, then restrict the choices to that app
    -- and ensure we have options to launch a new window in that app
    createWindowInApp = nil

    for word in queryWords do
        if keywords[word] then
            -- only allow choices of windows from this app
            restrictAppname = keywords[word]
            filtered = {}
            for i, win in pairs(searchInWindows) do
                if win["appName"] == restrictAppname then
                    table.insert(filtered, win)
                end
            end
            searchInWindows = filtered

            -- offer to load code paths in this app
            createWindowInApp = restrictAppname
        else
            table.insert(nonKeywords, word)
        end
    end
    -- log.d("_filterChoices nonKeywords:", nonKeywords)

    -- now filter possible windows by the non-keywords
    for i, word in pairs(nonKeywords) do
        filtered = {}
        for i, win in pairs(searchInWindows) do
            if string.find(win["searchText"], word, 1, true) then
                -- the search term is in this window name, keep as an option
                table.insert(filtered, win)
            end
        end
        searchInWindows = filtered
    end

    -- from here on we may add non-window items to the chooser too
    -- so rename the variable
    newChooserOptions = searchInWindows

    -- if a specific app has been chosen via keyword, offer to open any matching folders in there too
    if (createWindowInApp ~= nil and len(nonKeywords) > 0) then

        -- find code folders that matches the search terms
        matchingCodeFolders = _codeFolders
        for i, word in pairs(nonKeywords) do
            filtered = {}
            for i, folderName in pairs(_codeFolders) do
                if string.find(folderName, word, 1, true) then
                    -- the search term is in this folder name, keep as an option
                    table.insert(filtered, folderName)
                end
            end
            matchingCodeFolders = filtered
        end

        if matchingCodeFolders ~= nil then
            -- add chooser options to launch these folders in the chosen app

            for i, folderName in pairs(matchingCodeFolders) do
                item = {
                    ["type"] = "keyword",
                    ["text"] = 'Open "' .. folderName .. '" with ' .. createWindowInApp,
                    ["subText"] = codeDir .. folderName,
                    ["appName"] = createWindowInApp,
                    ["folderPath"] = codeDir .. folderName,
                }
                table.insert(newChooserOptions, item)
            end
        end
    end

    _windowChooser:choices(newChooserOptions)
end


function _optionChosen(item)
    if item == nil then
        -- when they cancel the chooser, focus on the last window again
        if _lastFocusedWindow then
            _lastFocusedWindow:focus()
            _lastFocusedWindow = nil
        end
        return
    end

    if item["type"] == "window" then
        window = hs.window.get(item["windowID"])
        window:focus()

    elseif item["type"] == "keyword" then
        launchKeywordApp(item["appName"], item["folderPath"])
    end
end


function _collectAllCurrentWindows()
    windows = hs.window.filter.default:getWindows(hs.window.filter.sortByFocusedLast)

    currentWindows = {}
    for i,w in pairs(windows) do
        title = w:title()
        app = w:application():name()
        item = {
            ["type"] = "window",
            ["text"] = app,  -- the chooser primary label
            ["subText"] = title,  -- the chooser sub-label
            ["windowID"] = w:id(),
            ["appName"] = app,
            ["searchText"] = (app .. " " .. title):lower(),
        }
        table.insert(currentWindows, item)
    end

    return currentWindows
end


function appSwitcher()
    -- show the popup immediately, then refresh the window options
    if _windowChooser == nil then
        _windowChooser = hs.chooser.new(_optionChosen)
            :choices(_currentWindows)
            :queryChangedCallback(_filterWindows)
            :searchSubText(true)
    end
    _windowChooser:query(""):show()

    _lastFocusedWindow = hs.window.focusedWindow()
    _currentWindows = _collectAllCurrentWindows()
    _windowChooser:choices(_currentWindows)
end


hs.hotkey.bind({"cmd"}, ";", function()
    appSwitcher()
end)


