local utf8 = require("utf8")

local marker = {}

local paramUnsetKeywords = {"none", "unset", "/"}

----------------------------------------------------------------------------------------------------
-- Class definitions ------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

---@class MarkerParamDictionary
---@field [string] string|false

---@class MarkerParamChar
---@field text string The string this character represents. Usually one character, but can actually be more, however, it will still act as one character and won't be able to be split.
---@field params MarkerParamDictionary The parameters and their values for this char

---@alias textAlign
---| '"default' # A default alignment. Identical to "left" (but you should use "left" instead of "default")
---| '"left"' # Aligns text to the left horizontally
---| '"right"' # Aligns text to the right horizontally
---| '"center"' # Aligns text to the center horizontally
---| '"middle"' # Identical to "center"

---@class MarkedText
---@field x number The X location to draw the text at
---@field y number The Y location to draw the text at
---@field font love.Font The font used for drawing the text
---@field maxWidth number The maximum width the text can take up
---
---@field rawString string The string used in creation of this markedText, with no processing
---@field strippedString string The raw string stripped of its tags, leaving only plaintext
---@field paramString MarkerParamChar[] The full paramString

----------------------------------------------------------------------------------------------------
-- Generic local functions ------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

---@param str string
---@return string
local function trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

---@param t table Table to copy
---@param target? table Table to copy the values to
---@return table
local function shallowCopy(t, target)
    local newTable = target or {}
    for key, value in pairs(t) do
        newTable[key] = value
    end
    return newTable
end

----------------------------------------------------------------------------------------------------
-- Petite local functions ------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

--- Parses and deletes the escape characters
---@param str any
---@return string
---@return integer count
local function parseEscapes(str)
    return string.gsub(str, "\\(.)", "%1")
end

---@param str string
---@return boolean
local function isParamUnsetKeyword(str)
    for i = 1, #paramUnsetKeywords do
        if str == paramUnsetKeywords[i] then return true end
    end
    return false
end

----------------------------------------------------------------------------------------------------
-- Meaty local functions --------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

--- Attempts to find a tag in the input string
---@param str string String to find tag in
---@param searchStart integer The number where to start the search at
---@return integer|nil tagStart The index in the string at which this match starts, or nil if a match wasn't found
---@return integer|nil tagEnd The index in the string at which this match ends, or nil if a match wasn't found
---@return string|nil tag The text of the tag or nil if this isn't a tag
local function findTagInString(str, searchStart)
    -- Find a tag, leave if there is none
    local startIndex, endIndex, match = string.find(str, "(%b[])", searchStart)
    if not startIndex then return end

    -- Early returned if the tag is escaped
    local charBefore = string.sub(str, startIndex-1, startIndex-1)
    local charBeforeCharBefore = string.sub(str, startIndex-2, startIndex-2)
    if charBefore == "\\" and charBeforeCharBefore ~= "\\" then -- It's escaped, and the escape isn't escaped
        return startIndex, endIndex
    end

    -- Make sure it's actually a tag (double brackets) and not just a set of brackets
    if not(string.sub(match, 2, 2) == "[" and string.sub(match, -2, -2) == "]") then
        return startIndex, endIndex
    end

    -- We found a tag, return it
    return startIndex, endIndex, string.sub(match, 3, -3)
end

---@param str string The tag text (excluding the [[ and ]] at the start and end)
---@return MarkerParamDictionary params Table of params (as keys) and their values as strings, or as false if the param has been unset
---@return boolean glueTagged
local function decodeTag(str)
    local glueTagged = false
    if string.sub(str, 1, 1) == "~" then
        str = string.sub(str, 2, -1)
        glueTagged = true
    end

    ---@type MarkerParamDictionary
    local params = {}

    for param, value in string.gmatch(str, "([^:;]+):([^;]+)") do
        param = trim(param)
        value = trim(value)

        if isParamUnsetKeyword(value) then
            params[param] = false
        else
            params[param] = value
        end
    end

    return params, glueTagged
end

--- Takes a string and removes all tags from it, returning the stripped string and a table of the parsed tags instead
---@param str string The string to parse
---@return string strippedString The string without any tags
---@return table<integer, MarkerParamDictionary> params A dictionary with character indices and the params that start there
local function stripStringOfTags(str)
    ---@type table<integer, MarkerParamDictionary>
    local tags = {}
    local previousTag = nil
    local searchStart = 1
    while true do
        -- Find a match for a tag, break if there is none
        local tagStart, tagEnd, tagText = findTagInString(str, searchStart)
        if not tagStart or not tagEnd then
            break
        end

        -- If a tag has been found
        if tagText then
            -- Track tag
            -- Edit the tag at this location, or if it doesnt exist, copy the values of the previous tag if there was one
            local currentTag = tags[tagStart] or (previousTag and shallowCopy(previousTag) or {})
            local decodedTag, glueTagged = decodeTag(tagText)
            for param, value in pairs(decodedTag) do
                currentTag[param] = value and value or nil -- Convert falsey values to nil to remove them from the table fully
            end
            tags[tagStart] = currentTag
            previousTag = currentTag

            -- Remove tag from string and adjust searchStart accordingly
            str = string.sub(str, 1, tagStart-1) .. string.sub(str, tagEnd+1)
            searchStart = tagStart
        else
            -- No tag, just move the searchStart
            searchStart = tagStart + 1
        end
    end

    -- Remove the escaping backslashes
    str = parseEscapes(str)

    return str, tags
end

---@param strippedString string
---@param params table<integer, MarkerParamDictionary>
---@return MarkerParamChar[]
local function convertStrippedStringToParamString(strippedString, params)
    ---@type MarkerParamChar[]
    local tagString = {}
    local currentParams = {}
    for pos, char in utf8.codes(strippedString) do
        if params[pos] then
            currentParams = params[pos]
        end

        tagString[#tagString+1] = {text = utf8.char(char), params = currentParams}
    end

    return tagString
end

--- Converts a string to a paramString
---@param str string The input string
---@return MarkerParamChar[] paramString The output paramString
---@return string strippedString The input string stripped of all of its tags
local function stringToTagString(str)
    local strippedString, params = stripStringOfTags(str)
    local paramString = convertStrippedStringToParamString(strippedString, params)
    return paramString, strippedString
end

----------------------------------------------------------------------------------------------------
-- The markedText class ----------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

-- Holds different functions for drawing the text differently based on the textAlign property
local drawFunctions = {}

---@param markedText MarkedText
---@param alignment? number
function drawFunctions.default(markedText, alignment)
    alignment = alignment or -1

    local x = markedText.x
    local y = markedText.y
    local maxWidth = markedText.maxWidth
    local paramString = markedText.paramString
    local font = markedText.font
    local lineHeight = font:getHeight()

    local stringEndFound = false
    local lineCharacterIndex = 1
    local lineIndex = 1
    while not stringEndFound do
        local lineCharacterCount = 0
        local lineWidth = 0
        local lineOverflowed = false
        local lastWhitespaceAtCount
        while true do
            local currentCharIndex = lineCharacterIndex + lineCharacterCount
            local paramChar = paramString[currentCharIndex]
            if not paramChar then
                stringEndFound = true
                break
            end
            if paramChar.text == "\n" then
                lineCharacterCount = lineCharacterCount + 1
                break
            end

            if paramChar.text == " " then
                lastWhitespaceAtCount = lineCharacterCount + 1 -- +1 to include the whitespace in the count
            end

            local charWidth = font:getWidth(paramChar.text)
            if lineWidth + charWidth > maxWidth and lineCharacterCount > 0 then
                -- We've reached max width, + one character per line minimum to avoid an infinite loop
                lineOverflowed = true

                -- Only split at spaces if possible
                lineCharacterCount = lastWhitespaceAtCount or lineCharacterCount
                break
            end

            -- We're safe to add this character to the current line
            lineCharacterCount = lineCharacterCount + 1
            lineWidth = lineWidth + charWidth
        end

        local fontPrevious = love.graphics.getFont()
        love.graphics.setFont(font)
        local lineWidthProgress = 0 -- todo: set this as negative space width if the line was split at a space
        for charIndex = lineCharacterIndex, lineCharacterIndex + lineCharacterCount - 1 do
            local paramChar = paramString[charIndex]
            local charText = paramChar.text

            local drawX = x + lineWidthProgress
            local drawY = y + (lineIndex - 1) * lineHeight
            love.graphics.print(charText, drawX, drawY)

            lineWidthProgress = lineWidthProgress + font:getWidth(charText)
        end
        love.graphics.setFont(fontPrevious)

        lineCharacterIndex = lineCharacterIndex + lineCharacterCount
        lineIndex = lineIndex + 1
    end
end

---@class MarkedText
local markedTextMetatable = {}
markedTextMetatable.__index = markedTextMetatable

--- Draws the text, optionally overriding the set X and Y coordinates with the given parameters
function markedTextMetatable:draw()
    drawFunctions.default(self)
end

--- Parses a new string and sets the MarkedText to it
---@param str string
function markedTextMetatable:setText(str)
    local paramString, strippedString = stringToTagString(str)
    self.rawString = str
    self.strippedString = strippedString
    self.paramString = paramString
end

local defaultFont = love.graphics.newFont()
--- Creates a new MarkedText instance
---@param str? string The tagged string to parse and set the text to (Default is empty string)
---@param font? love.Font The font used to draw this text
---@param x? number The X location to place the text at (Default is 0)
---@param y? number The Y location to place the text at (Default is 0)
---@param maxWidth? number The maximum width the text can take up (Default is infinity)
---@param textAlign? textAlign The horizontal alignment of the text (Default is "left")
---@return MarkedText markedText
function marker.newMarkedText(str, font, x, y, maxWidth, textAlign)
    str = str or ""
    font = font or defaultFont
    x = x or 0
    y = y or 0
    maxWidth = maxWidth or math.huge
    textAlign = textAlign or "left"

    local paramString, strippedString = stringToTagString(str)

    ---@type MarkedText
    local markedText = {
        x = x,
        y = y,
        font = font,
        maxWidth = maxWidth,
        textAlign = textAlign,
        rawString = str,
        strippedString = strippedString,
        paramString = paramString,
    }

    setmetatable(markedText, markedTextMetatable)
    return markedText
end

return marker