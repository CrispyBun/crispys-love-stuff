----------------------------------------------------------------------------------------------------
-- A messy but functional LÖVE text rendering library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
----------------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2024-2025 Ava "CrispyBun" Špráchalů

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]
----------------------------------------------------------------------------------------------------

local utf8 = require("utf8")

local marker = {}

marker.colors = {
    default = {1, 1, 1}, -- A "default" should always exist
    red = {1, 0.1, 0.15},
    green = {0, 1, 0.1},
    blue = {0.2, 0.2, 1},
}

-- Add the names of emojis and the emojis they refer to
marker.emojiNames = {
    -- grinning = "😁"
    -- grinning = "\xF0\x9F\x98\x81"
}

-- Variables that can be referenced by the '[[var:*]]' tag
---@type table<string, any>
marker.textVariables = {}

-- Can be set to mouse position, used for mouseover callback
marker.cursorX = nil ---@type number?
marker.cursorY = nil ---@type number?
function marker.setCursor(x, y)
    if not x or not y then x, y = nil, nil end
    marker.cursorX = x
    marker.cursorY = y
end

--- Arbitrary callbacks triggered by some events from marker texts, you can add functions listening to them into this table
---@type table<string, fun(paramChar: Marker.ParamCharCollapsed)>
marker.callbacks = {}

-- Defined callbacks are:
-- 'typewriter' (triggers on each new character written by the typewriter text effect)
-- 'mouseover' (triggers each draw call where the mouse cursor is over a character)

-- Defined tag params are:
-- 'color'              - Sets the color of the text to a color defined in marker.colors
-- 'tint'               - Same as color, overrides it
-- 'wave'               - Characters sway up and down to the specified amount
-- 'harmonica'          - Characters sway left and right to the specified amount
-- 'shatter'            - Characters are displaced to random offsets by the specified amount
-- 'shake'              - Characters shake at the specified amount,speed
-- 'text'               - The text affected by the tag gets replaced by the specified string
-- 'var'                - The text affected by the tag gets replaced by the specified variable refering to a value in marker.textVariables
-- 'corrupt'            - The text affected by the tag changes to an ever-changing jumble of characters, changing at the specified speed
-- 'typewriter'         - The text affected by the tag appears character by character, appearing at the specified speed
-- 'typewriter-appear'  - The text affected by the tag fades in smoothly instead of character by character if also affected by the typewriter tag. Appears at specified speed (less than 1 for smooth fade).

local paramUnsetKeywords = {"none", "unset", "/"}

----------------------------------------------------------------------------------------------------
-- Class definitions -------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

---@class Marker.ParamDictionary
---@field [string] string|false

---@class Marker.ParamChar
---@field text string The string this character represents. Usually one character, but can actually be more, however, it will still act as one character and won't be able to be split.
---@field params Marker.ParamDictionary The parameters and their values for this char

---@alias Marker.TextAlign
---| '"default"' # A default alignment. Identical to "left" (but you should use "left" instead of "default")
---| '"left"' # Aligns text to the left horizontally
---| '"right"' # Aligns text to the right horizontally
---| '"center"' # Aligns text to the center horizontally
---| '"middle"' # Identical to "center"
---| '"justify"' # Spreads lines to use full container width
---| '"block"' # Identical to "justify"

---@alias Marker.VerticalAlign
---| '"top"' # Aligns to top (This is the default)
---| '"middle"' # Aligns to the middle
---| '"center"' # Identical to "middle"
---| '"bottom"' # Aligns to bottom

---@alias Marker.Font love.Font|table

---@class Marker.MarkedText
---@field x number The X location to draw the text at
---@field y number The Y location to draw the text at
---@field font Marker.Font The font used for drawing the text
---@field maxWidth number The maximum width the text can take up
---@field time number The accumulated elapsed deltatime
---@field timePrevious number The time value at the time of the previous update
---@field textAlign Marker.TextAlign
---@field verticalAlign Marker.VerticalAlign
---@field boxHeight number
---@field doRelativeXAlign boolean
---@field lineHeight number
---@field textVariables table<string, any>  Same as marker.textVariables but for this text only
---
---@field rawString string The string used in creation of this markedText, with no processing
---@field strippedString string The raw string stripped of its tags, leaving only plaintext
---@field paramString Marker.ParamChar[] The full paramString
---
---@field cachedWidth number?
---@field cachedHeight number?

---@class Marker.ParamCharCollapsed -- Collapsed by the draw function into clear instructions for how to draw it, instead of params
---@field text string
---@field xOffset number
---@field yOffset number
---@field color number[]
---@field paramsUsed Marker.ParamDictionary The params used in this char to collapse it
---@field x? number
---@field y? number

----------------------------------------------------------------------------------------------------
-- Text effects -----------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

-- Effects not added to the order will not be registered
marker.charEffectsOrder = {
    "color",
    "tint",

    "wave",
    "harmonica",
    "shatter",
    "shake",

    "text",
    "var",
    "corrupt"
}

-- Effects applied per character, most effects belong here
---@type table<string, fun(char: Marker.ParamCharCollapsed, arg: string, time: number, charIndex: integer, charPrevious?: Marker.ParamCharCollapsed): Marker.ParamCharCollapsed[]?>
marker.charEffects = {}

marker.charEffects.color = function (char, arg)
    char.color = marker.colors[arg] or marker.colors.default or {1,1,1}
end
marker.charEffects.tint = marker.charEffects.color -- Just a color on top of color

marker.charEffects.wave = function (char, arg, time, charIndex)
    if char.paramsUsed._GLUE then charIndex = 1 end

    local amount = tonumber(arg) or 1
    char.yOffset = char.yOffset + math.sin((time * 10) - (charIndex / 2)) * amount
end
marker.charEffects.harmonica = function (char, arg, time, charIndex)
    if char.paramsUsed._GLUE then charIndex = 1 end

    local amount = tonumber(arg)
    amount = amount or 1
    char.xOffset = char.xOffset + math.sin((time * 10) - (charIndex / 2)) * amount
end

marker.charEffects.text = function (char, arg, time, charIndex, charPrevious)
    return marker.charEffectHelpers.generateCollapsedCharsFromString(arg, char)
end

marker.charEffects.var = function (char, arg, time, charIndex, charPrevious)
    if marker.textVariables[arg] == nil then return end
    local replacementText = tostring(marker.textVariables[arg])

    return marker.charEffectHelpers.generateCollapsedCharsFromString(replacementText, char)
end

local corruptChars = {'#', '$', '%', '&', '@', '=', '?', '6', '<', '>'}
marker.charEffects.corrupt = function (char, arg, time, charIndex, charPrevious)
    if char.paramsUsed._GLUE then char.text = "a" end

    local speed = tonumber(arg) or 1
    local progress = math.floor(time * 20 * speed)

    local charSeed = utf8.codepoint(char.text) + progress
    marker.functions.setRandomSeed(charSeed)

    local pickedCharIndex = marker.functions.random(1, #corruptChars)

    char.text = corruptChars[pickedCharIndex]
    marker.functions.resetSeed()
end

marker.charEffects.shatter = function (char, arg, time, charIndex, charPrevious)
    local amount = (tonumber(arg) or 1) * 4

    local charSeed = utf8.codepoint(char.text) + charIndex
    marker.functions.setRandomSeed(charSeed)

    local xOffset = (marker.functions.random() - 0.5) * amount + 0.5
    local yOffset = (marker.functions.random() - 0.5) * amount + 0.5
    char.xOffset = char.xOffset + xOffset
    char.yOffset = char.yOffset + yOffset

    marker.functions.resetSeed()
end

marker.charEffects.shake = function (char, arg, time, charIndex, charPrevious)
    local args = marker.charEffectHelpers.splitArgs(arg)
    local amount = (tonumber(args[1]) or 1) * 4
    local speed = (tonumber(args[2]) or 1)

    local progress = math.floor(time * 15 * speed)

    local charSeed = charIndex + progress
    marker.functions.setRandomSeed(charSeed)

    local xOffset = (marker.functions.random() - 0.5) * amount + 0.5
    local yOffset = (marker.functions.random() - 0.5) * amount + 0.5
    char.xOffset = char.xOffset + xOffset
    char.yOffset = char.yOffset + yOffset

    marker.functions.resetSeed()
end

-- Text effects not added to the order will not be registered
marker.textEffectsOrder = {
    "typewriter"
}

-- Effects applied on the entire text as a whole, only a few effects need to see and modify the full text
---@type table<string, fun(collapsedParamString: Marker.ParamCharCollapsed[], time: number, timePrevious: number)>
marker.textEffects = {}

local typePauseChars = {
    ["."] = true,
    [","] = true,
    [":"] = true,
    [";"] = true
}
local typeSkipChars = {
    [""] = true,
    [" "] = true,
    ["\n"] = true
}
marker.textEffects.typewriter = function (collapsedParamString, time, timePrevious)
    local timeAccumulated = 0
    local typeInstant = false ---@type any
    for charIndex = 1, #collapsedParamString do
        local char = collapsedParamString[charIndex]
        local nextChar = collapsedParamString[charIndex+1]
        local paramsUsed = char.paramsUsed

        typeInstant = paramsUsed["typewriter-appear"]
        local speedMult = tonumber(typeInstant)

        if paramsUsed.typewriter then
            local arg = paramsUsed.typewriter
            local num = 1 / ((tonumber(arg) or 1) * 10)
            if speedMult then num = num / speedMult end
            if typeSkipChars[char.text] then num = 0 end
            if typePauseChars[char.text] then num = num * 2 end

            local appearProgress
            if typeInstant then
                appearProgress = (time - timeAccumulated) / num
                appearProgress = math.max(0, appearProgress)
                appearProgress = math.min(1, appearProgress)
                if typeInstant and not speedMult then
                    appearProgress = math.floor(appearProgress)
                end

                if nextChar and nextChar.paramsUsed["typewriter-appear"] then
                    num = 0
                end
            end

            if appearProgress then
                char.color = {char.color[1], char.color[2], char.color[3], appearProgress}
            end

            if timeAccumulated > time then
                char.text = ""
            else
                if timeAccumulated > timePrevious and num > 0 and not typeInstant then
                    if marker.callbacks.typewriter then marker.callbacks.typewriter(char) end
                end
            end
            timeAccumulated = timeAccumulated + num
        end
    end
end

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

---@param chars Marker.ParamCharCollapsed[]
---@param i? integer
---@param j? integer
---@return integer
local function countSpaces(chars, i, j)
    i = i or 1
    j = j or #chars

    i = math.max(i, 0)
    j = math.min(j, #chars)

    local count = 0
    for charIndex = i, j do
        local char = chars[charIndex]
        if char.text == " " then count = count + 1 end
    end

    return count
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
---@return Marker.ParamDictionary params Table of params (as keys) and their values as strings, or as false if the param has been unset
---@return boolean glueTagged
local function decodeTag(str)
    local glueTagged = false
    if string.sub(str, 1, 1) == "~" then
        str = string.sub(str, 2, -1)
        glueTagged = true
    end

    ---@type Marker.ParamDictionary
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
---@return table<integer, Marker.ParamDictionary> params A dictionary with character indices and the params that start there
local function stripStringOfTags(str)
    ---@type table<integer, Marker.ParamDictionary>
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
                currentTag._GLUE = glueTagged
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
---@param params table<integer, Marker.ParamDictionary>
---@return Marker.ParamChar[]
local function convertStrippedStringToParamString(strippedString, params)
    ---@type Marker.ParamChar[]
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

--- Converts the emojis known to it to their encoded UTF-8 values
---@param str string
---@return string
local function convertEmojis(str)
    for emojiName, emojiCode in pairs(marker.emojiNames) do
        local pattern = ":" .. emojiName .. ":"
        str = str:gsub(pattern, emojiCode)
    end
    return str
end

--- Converts a string to a paramString
---@param str string The input string
---@return Marker.ParamChar[] paramString The output paramString
---@return string strippedString The input string stripped of all of its tags
local function stringToTagString(str)
    str = convertEmojis(str)
    local strippedString, params = stripStringOfTags(str)
    local paramString = convertStrippedStringToParamString(strippedString, params)
    return paramString, strippedString
end

local function applyCharEffectsOnCollapsedParamChar(collapsedParamChar, time, stringIndex, collapsedCharPrevious, ignoreReplacementChars)
    local charParams = collapsedParamChar.paramsUsed
    local replacementChars

    for charEffectIndex = 1, #marker.charEffectsOrder do
        local charEffectName = marker.charEffectsOrder[charEffectIndex]
        local paramValue = charParams[charEffectName]

        if paramValue then
            local replacementCharOutput = marker.charEffects[charEffectName](collapsedParamChar, paramValue, time, stringIndex, collapsedCharPrevious)

            if collapsedCharPrevious and replacementCharOutput and collapsedCharPrevious.paramsUsed[charEffectName] then
                -- Replacement output is only applied to the first character, the rest of the characters must just get deleted
                replacementCharOutput = {}
            end
            replacementChars = replacementCharOutput or replacementChars
        end
    end

    -- Apply effects again on replacement characters
    local replacementCharPrevious = collapsedCharPrevious
    if replacementChars and not ignoreReplacementChars then
        for replacementCharIndex = 1, #replacementChars do
            local replacementChar = replacementChars[replacementCharIndex]
            applyCharEffectsOnCollapsedParamChar(replacementChar, time, stringIndex + replacementCharIndex - 1, replacementCharPrevious, true)
            replacementCharPrevious = replacementChar
        end
    end

    return replacementChars
end

---@param paramString Marker.ParamChar[]
---@return Marker.ParamCharCollapsed[]
---@return Marker.ParamDictionary
local function collapseParamString(paramString, time)
    ---@type Marker.ParamCharCollapsed[]
    local collapsedParamString = {}
    local stringIndex = 1
    local charsEncountered = 0
    local collapsedCharPrevious
    local effectsEncountered = {}
    while stringIndex <= #paramString do
        charsEncountered = charsEncountered + 1

        local paramChar = paramString[stringIndex]
        local charParams = paramChar.params

        for eff, value in pairs(charParams) do
            effectsEncountered[eff] = value
        end

        local collapsedParamChar = {
            text = paramChar.text,
            xOffset = 0,
            yOffset = 0,
            color = {1, 1, 1},
            paramsUsed = charParams
        }

        local replacementChars = applyCharEffectsOnCollapsedParamChar(collapsedParamChar, time, charsEncountered, collapsedCharPrevious)

        if replacementChars then
            for replacementCharIndex = 1, #replacementChars do
                collapsedParamString[#collapsedParamString+1] = replacementChars[replacementCharIndex]
            end
            charsEncountered = charsEncountered + #replacementChars - 1
        else
            collapsedParamString[#collapsedParamString+1] = collapsedParamChar
        end

        stringIndex = stringIndex + 1
        collapsedCharPrevious = collapsedParamChar
    end
    return collapsedParamString, effectsEncountered
end

----------------------------------------------------------------------------------------------------
-- Text effect helpers -----------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

marker.charEffectHelpers = {}

---@param str string args
---@return string[]
marker.charEffectHelpers.splitArgs = function (str)
    local parsedArgs = {}
    for arg in str:gmatch("[^,]+") do
        parsedArgs[#parsedArgs+1] = arg
    end

    if #parsedArgs == 0 then
        parsedArgs[1] = ""
    end

    return parsedArgs
end

---@param str string
---@param originalChar Marker.ParamCharCollapsed
---@return Marker.ParamCharCollapsed[]
marker.charEffectHelpers.generateCollapsedCharsFromString = function (str, originalChar)
    local replacementChars = {}
    for pos, charCode in utf8.codes(str) do
        local nextChar = utf8.char(charCode)
        replacementChars[#replacementChars+1] = {
            text = nextChar,
            xOffset = 0,
            yOffset = 0,
            color = {1, 1, 1},
            paramsUsed = originalChar.paramsUsed
        }
    end

    return replacementChars
end

----------------------------------------------------------------------------------------------------
-- Mild abstraction from LÖVE ----------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

local love = love

---@type table<string, function>
marker.functions = {}

local randomizer
if love then randomizer = love.math.newRandomGenerator() end

if love then
    marker.functions.setRandomSeed = function (seed)
        randomizer:setSeed(seed)
    end
    marker.functions.resetSeed = function ()
        -- no seet resetting necessary
    end
    marker.functions.random = function (min, max)
        return randomizer:random(min, max)
    end

    marker.functions.getFont = love.graphics.getFont
    marker.functions.setFont = love.graphics.setFont
    marker.functions.getColor = love.graphics.getColor
    marker.functions.setColor = love.graphics.setColor

    marker.functions.newFont = love.graphics.newFont

    marker.functions.getCharWidth = function (font, text) return font:getWidth(text) end
    marker.functions.getCharHeight = function (font) return font:getHeight() end
    marker.functions.drawChar = function (font, text, x, y) return love.graphics.print(text, x, y) end -- font discarded, it was already set in setFont()
else
    local currentFont = {}
    local currentColor = {1, 1, 1, 1}

    marker.functions.setRandomSeed = function (seed)
        math.randomseed(seed)
    end
    marker.functions.resetSeed = function ()
        math.randomseed(os.time() + os.clock())
    end
    marker.functions.random = math.random

    marker.functions.getFont = function () return currentFont end
    marker.functions.setFont = function (font) currentFont = font end
    marker.functions.getColor = function () return currentColor[1], currentColor[2], currentColor[3], currentColor[4] end
    marker.functions.setColor = function (...) -- accepts both r, g, b, a and {r, g, b, a}
        local colors = {...}
        if type(colors[1]) == "table" then
            local color = colors[1]
            currentColor[1] = color[1] or 1
            currentColor[2] = color[2] or 1
            currentColor[3] = color[3] or 1
            currentColor[4] = color[4] or 1
            return
        end
        currentColor[1] = colors[1] or 1
        currentColor[2] = colors[2] or 1
        currentColor[3] = colors[3] or 1
        currentColor[4] = colors[4] or 1
    end

    -- Platform specific:

    marker.functions.newFont = function () return {} end

    marker.functions.getCharWidth = function (font, text) return 1 end
    marker.functions.getCharHeight = function (font) return 1 end
    marker.functions.drawChar = function (font, text, x, y) end -- usually draws just a glyph, but can draw full strings of text
end

----------------------------------------------------------------------------------------------------
-- The markedText class ----------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

-- Holds different functions for drawing the text differently based on the textAlign property
local drawFunctions = {}

---Assumes the x and y of the characters have been set
---@param collapsedParamString Marker.ParamCharCollapsed[]
---@param boxHeight number
---@param textHeight number
---@param verticalAlign number
---@param font Marker.Font
local function renderCollapsedParamString(collapsedParamString, boxHeight, textHeight, verticalAlign, font)
    local textUnusedSpace = boxHeight - textHeight
    local verticalAlignOffset = (textUnusedSpace + textUnusedSpace * verticalAlign)/2

    local fontPrevious = marker.functions.getFont()
    local cr, cg, cb, ca = marker.functions.getColor()
    marker.functions.setFont(font)
    for paramCharIndex = 1, #collapsedParamString do
        local paramChar = collapsedParamString[paramCharIndex]
        local charX = paramChar.x
        local charY = paramChar.y
        local charText = paramChar.text
        local charColor = paramChar.color
        local charXOffset = paramChar.xOffset
        local charYOffset = paramChar.yOffset

        charX = math.floor(charX + charXOffset)
        charY = math.floor(charY + charYOffset + verticalAlignOffset)

        marker.functions.setColor(charColor)
        marker.functions.drawChar(font, charText, charX, charY)
    end
    marker.functions.setFont(fontPrevious)
    marker.functions.setColor(cr, cg, cb, ca)
end

local function extractLine(collapsedParamString, lineCharacterIndex, font, maxWidth)
    local lineCharacterCount = 0
    local lineWidth = 0
    local lineWidthUntilLastWhitespace
    local lineOverflowed = false
    local stringEndFound = false
    local lastWhitespaceAtCount
    while true do
        local currentCharIndex = lineCharacterIndex + lineCharacterCount
        local paramChar = collapsedParamString[currentCharIndex]
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
            lineWidthUntilLastWhitespace = lineWidth
        end

        local charWidth = marker.functions.getCharWidth(font, paramChar.text)
        if lineWidth + charWidth > maxWidth and lineCharacterCount > 0 then
            -- We've reached max width, + one character per line minimum to avoid an infinite loop
            lineOverflowed = true

            -- Only split at spaces if possible
            lineCharacterCount = lastWhitespaceAtCount or lineCharacterCount
            lineWidth = lineWidthUntilLastWhitespace or lineWidth
            break
        end

        -- We're safe to add this character to the current line
        lineCharacterCount = lineCharacterCount + 1
        lineWidth = lineWidth + charWidth
    end
    return lineCharacterCount, lineWidth, lineOverflowed, stringEndFound
end

local verticalAlignEnum = {
    top = -1,
    middle = 0,
    center = 0,
    bottom = 1
}

function drawFunctions.invalid(markedText)
    local x = markedText.x
    local y = markedText.y
    local fontPrevious = marker.functions.getFont()
    marker.functions.setFont(markedText.font)
    marker.functions.drawChar(markedText.font, "Invalid text align property: '" .. tostring(markedText.textAlign) .. "'", x, y)
    marker.functions.setFont(fontPrevious)
end

---@param markedText Marker.MarkedText
---@param alignment? number
---@param justify? boolean
function drawFunctions.default(markedText, alignment, justify)
    alignment = alignment or -1
    justify = justify or false

    local x = markedText.x
    local y = markedText.y
    local maxWidth = markedText.maxWidth
    local paramString = markedText.paramString
    local font = markedText.font
    local lineHeight = marker.functions.getCharHeight(font) + markedText.lineHeight

    local cursorX, cursorY = marker.cursorX, marker.cursorY

    -- Hack the markedText's textVariables into the global ones before the collapsed chars generate
    local textVariablesPrevious = marker.textVariables
    marker.textVariables = markedText.textVariables

    local collapsedParamString, effectsEncountered = collapseParamString(paramString, markedText.time)

    marker.textVariables = textVariablesPrevious

    if maxWidth == math.huge then
        local width = 0
        local maxLineWidthFound = 0
        for charIndex = 1, #collapsedParamString do
            local char = collapsedParamString[charIndex].text
            width = width + marker.functions.getCharWidth(font, char)
            if char == "\n" or charIndex == #collapsedParamString then
                maxLineWidthFound = math.max(maxLineWidthFound, width)
                width = 0
            end
        end
        maxWidth = maxLineWidthFound
    end

    local stringEndFound = false
    local lineCharacterIndex = 1
    local lineIndex = 1
    while not stringEndFound do
        local lineCharacterCount, lineWidth, lineOverflowed
        lineCharacterCount, lineWidth, lineOverflowed, stringEndFound = extractLine(collapsedParamString, lineCharacterIndex, font, maxWidth)

        local textBlockOffset = 0
        if markedText.doRelativeXAlign then
            textBlockOffset = -(maxWidth + maxWidth * alignment)/2
        end
        local lineUnusedSpace = maxWidth - lineWidth
        local alignmentOffset = (lineUnusedSpace + lineUnusedSpace * alignment)/2
        local lineWidthProgress = 0
        local spaceCount = 0

        local justifyGapGrow
        if justify then justifyGapGrow = lineUnusedSpace / (countSpaces(collapsedParamString, lineCharacterIndex, lineCharacterIndex + lineCharacterCount) - 1) end
        if justifyGapGrow == math.huge then justifyGapGrow = 0 end
        if justify and lineOverflowed then alignmentOffset = 0 end

        for charIndex = lineCharacterIndex, lineCharacterIndex + lineCharacterCount - 1 do
            local paramChar = collapsedParamString[charIndex]
            local charText = paramChar.text

            local charX = x + lineWidthProgress + alignmentOffset + textBlockOffset
            local charY = y + (lineIndex - 1) * lineHeight
            local charWidth = marker.functions.getCharWidth(font, charText)

            if justifyGapGrow and lineOverflowed then
                charX = charX + justifyGapGrow * spaceCount
            end

            paramChar.x = charX
            paramChar.y = charY

            if paramChar.text == " " then spaceCount = spaceCount + 1 end

            lineWidthProgress = lineWidthProgress + charWidth

            if cursorX and cursorY then
                if cursorX >= charX and cursorY >= charY and cursorX < charX + charWidth and cursorY < charY + lineHeight then
                    if marker.callbacks.mouseover then marker.callbacks.mouseover(paramChar) end
                end
            end
        end

        lineCharacterIndex = lineCharacterIndex + lineCharacterCount
        lineIndex = lineIndex + 1
    end

    local textHeight = lineHeight * (lineIndex - 1)
    local verticalAlign = verticalAlignEnum[markedText.verticalAlign]

    -- Apply text effects
    for textEffectIndex = 1, #marker.textEffectsOrder do
        local textEffectName = marker.textEffectsOrder[textEffectIndex]
        if effectsEncountered[textEffectName] then
            marker.textEffects[textEffectName](collapsedParamString, markedText.time, markedText.timePrevious)
        end
    end

    renderCollapsedParamString(collapsedParamString, markedText.boxHeight, textHeight, verticalAlign, font)
end

drawFunctions.left = function (markedText) return drawFunctions.default(markedText, -1) end
drawFunctions.right = function (markedText) return drawFunctions.default(markedText, 1) end
drawFunctions.center = function (markedText) return drawFunctions.default(markedText, 0) end
drawFunctions.middle = drawFunctions.center
drawFunctions.justify = function (markedText) return drawFunctions.default(markedText, -1, true) end
drawFunctions.block = drawFunctions.justify

---@class Marker.MarkedText
local markedTextMetatable = {}
markedTextMetatable.__index = markedTextMetatable

--- Draws the text
function markedTextMetatable:draw()
    local drawFunction = drawFunctions[self.textAlign] or drawFunctions.invalid
    drawFunction(self)
end

-- Updates the text to animate
---@param dt number
function markedTextMetatable:update(dt)
    self.timePrevious = self.time
    self.time = self.time + dt
end

--- Returns the X and Y coordinates of the text
---@return number
---@return number
function markedTextMetatable:getPosition()
    return self.x, self.y
end

--- Calculates and returns the width and height the text takes up
---@return number
---@return number
function markedTextMetatable:getSize()
    if self.cachedWidth and self.cachedHeight then return self.cachedWidth, self.cachedHeight end

    local lineHeight = marker.functions.getCharHeight(self.font) + self.lineHeight

    local width = 0
    local height = 0
    local collapsedParamString = collapseParamString(self.paramString, self.time)
    local lineCharacterIndex = 1
    local stringEndFound = false
    local lineBreakFound = false
    while not stringEndFound do
        local lineCharacterCount, lineWidth, lineOverflowed
        lineCharacterCount, lineWidth, lineOverflowed, stringEndFound = extractLine(collapsedParamString, lineCharacterIndex, self.font, self.maxWidth)
        lineCharacterIndex = lineCharacterIndex + lineCharacterCount
        width = math.max(width, lineWidth)
        height = height + lineHeight

        if lineOverflowed then
            lineBreakFound = true
        end
    end

    if lineBreakFound and (self.textAlign == "justify" or self.textAlign == "block") then
        width = self.maxWidth
    end
    self.cachedWidth = width
    self.cachedHeight = height
    return width, height
end

--- Changes the text's position
---@param x number? The X coordinate (Default is 0)
---@param y number? The Y coordinate (Default is x)
function markedTextMetatable:setPosition(x, y)
    self.x = x or 0
    self.y = y or self.x
end

--- Parses a new string and sets the MarkedText to it
---@param str string
function markedTextMetatable:setText(str)
    local paramString, strippedString = stringToTagString(str)
    self.rawString = str
    self.strippedString = strippedString
    self.paramString = paramString
    self.cachedWidth = nil
    self.cachedHeight = nil
end

local textVariablesMt = {__index = marker.textVariables}

local defaultFont = marker.functions.newFont()
--- Creates a new MarkedText instance
---@param str? string The tagged string to parse and set the text to (Default is empty string)
---@param font? Marker.Font The font used to draw this text
---@param x? number The X location to place the text at (Default is 0)
---@param y? number The Y location to place the text at (Default is 0)
---@param maxWidth? number The maximum width the text can take up (Default is infinity)
---@param textAlign? Marker.TextAlign The horizontal alignment of the text (Default is "left")
---@param verticalAlign? Marker.VerticalAlign The vertical alignment of the text (Default is "top")
---@param boxHeight? number The reference height of a box this text lays in, used for vertical alignment. (Default is 0 - aligns relatively to the Y coordinate)
---@param doRelativeXAlign? boolean If the alignment in the X axis should be done relatively to the X coordinate
---@param lineHeight? number A change in the line height of the text (Default is 0)
---@return Marker.MarkedText markedText
function marker.newMarkedText(str, font, x, y, maxWidth, textAlign, verticalAlign, boxHeight, doRelativeXAlign, lineHeight)
    str = str or ""
    font = font or defaultFont
    x = x or 0
    y = y or 0
    maxWidth = maxWidth or math.huge
    textAlign = textAlign or "left"
    verticalAlign = verticalAlign or "top"
    boxHeight = boxHeight or 0
    doRelativeXAlign = doRelativeXAlign or false
    lineHeight = lineHeight or 0

    local paramString, strippedString = stringToTagString(str)

    -- new Marker.MarkedText
    local markedText = {
        x = x,
        y = y,
        font = font,
        maxWidth = maxWidth,
        time = 0,
        timePrevious = 0,
        textAlign = textAlign,
        verticalAlign = verticalAlign,
        boxHeight = boxHeight,
        doRelativeXAlign = doRelativeXAlign,
        rawString = str,
        strippedString = strippedString,
        paramString = paramString,
        lineHeight = lineHeight,
        textVariables = setmetatable({}, textVariablesMt)
    }

    setmetatable(markedText, markedTextMetatable)
    return markedText
end

return marker