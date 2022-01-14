-- folders in this location can be opened with keywords
-- eg "code auth" will offer to open the folder /Users/gcox/code/auth-service in VSCode
codeDir = "/Users/gcox/code/"

keywords = {
    {
        ["keyword"] = "git",
        ["appName"] = "Sourcetree",
        ["launch"] = function(item)
            hs.execute("stree " .. item["folderPath"], true)
        end,
    },
    {
        ["keyword"] = "code",
        ["appName"] = "Code", -- VSCode
        ["launch"] = function(item)
            hs.execute("code " .. item["folderPath"], true)
        end,
    },
    {
        ["keyword"] = "pr",
        ["appName"] = "Pull-Request",
        ["launch"] = function(item)
            hs.urlevent.openURL(item["subText"])
        end,
        ["choices"] = function(folderName)
            return {
                {
                    ["text"] = 'Create new Pull Request for "' .. folderName .. '"',
                    ["subText"] = "https://github.com/account/" .. folderName .. "/compare",
                    ["action"] = "new",
                    ["folderName"] = folderName,
                },
                {
                    ["text"] = 'Show existing Pull Requests for "' .. folderName .. '"',
                    ["subText"] = "https://github.com/account/" .. folderName .. "/pulls",
                    ["action"] = "existing",
                    ["folderName"] = folderName,
                }
            }
        end
    }
}


log = hs.logger.new("fuzzy", "debug")

function getSubfolderNames(directory)
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

-- setup
_currentWindows = {}
_codeFolders = getSubfolderNames(codeDir)
_windowChooser = nil
_lastFocusedWindow = nil
_keywordsIndexed = {}
for i, kw in pairs(keywords) do
    _keywordsIndexed[kw["keyword"]] = kw
end


function _queryChanged(query)
    searchInWindows = _currentWindows
    queryWords = string.gmatch(query:lower(), "%S+")
    nonKeywords = {}

    -- if the query includes one of these keywords, then restrict the choices to that app
    -- and ensure we have options to launch a new window in that app
    keywordApp = nil

    for word in queryWords do
        if _keywordsIndexed[word] then
            -- only allow choices of windows from this app
            restrictApp = _keywordsIndexed[word]
            filtered = {}
            for i, win in pairs(searchInWindows) do
                if win["appName"] == restrictApp["appName"] then
                    table.insert(filtered, win)
                end
            end
            searchInWindows = filtered

            -- offer to load code paths in this app
            keywordApp = restrictApp
        else
            -- this is not a keyword, use it for filtering windows and codebases
            table.insert(nonKeywords, word)
        end
    end
    -- log.d("_filterChoices nonKeywords:", nonKeywords)

    -- now filter possible windows
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

    -- if any of the non-keywords match code folders, offer to load them in our keyword apps
    if len(nonKeywords) > 0 then

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
            -- add chooser options to launch these folders in apps
            if keywordApp ~= nil then
                -- show option to launch in just this app
                launchInApps = { [""] = keywordApp }
            else
                -- show options to launch in all keyword apps
                launchInApps = keywords
            end

            for i, app in pairs(launchInApps) do
                for j, folderName in pairs(matchingCodeFolders) do
                    if app["choices"] then
                        -- this app implements custom choices
                        choices = app["choices"](folderName)
                        for i, choice in pairs(choices) do
                            -- ensure these choices have the required props
                            choice["type"] = "keyword"
                            choice["keyword"] = app["keyword"]
                            table.insert(newChooserOptions, choice)
                        end

                    else
                        -- use the default choice
                        item = {
                            ["type"] = "keyword",
                            ["keyword"] = app["keyword"],
                            ["text"] = 'Open "' .. folderName .. '" with ' .. app["appName"],
                            ["subText"] = codeDir .. folderName,
                            -- any props the custom app launcher may want
                            ["folderPath"] = codeDir .. folderName,
                            ["folderName"] = folderName,
                        }
                        table.insert(newChooserOptions, item)
                    end
                end
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
        app = _keywordsIndexed[item["keyword"]]
        app["launch"](item)
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
            :queryChangedCallback(_queryChanged)
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


