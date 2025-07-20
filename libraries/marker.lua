----------------------------------------------------------------------------------------------------
-- A messy but featureful LÖVE text rendering library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
----------------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2025 Ava "CrispyBun" Špráchalů

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

local utf8 = require 'utf8'

local marker = {}

-- Types --------------------------------------------------------------------------------------------

--- The object capable of generating and drawing an animated text with effects
---@class Marker.MarkedText
---@field x number The X coordinate of the text
---@field y number The Y coordinate of the text
---@field wrapLimit number How wide the text is allowed to be before it must wrap
---@field textAlign Marker.TextAlign The horizontal alignment of the text
---@field verticalAlign Marker.VerticalAlign The vertical alignment of the text
---@field alignBox [number, number] The reference textbox size ([x, y]) the text is aligned in
---@field font Marker.Font The font used to generate and render the text
---@field inputString string The string used to generate the text
---@field effectChars Marker.EffectChar[] The generated EffectChars
---@field ignoreStretchOnLastLine boolean True by default, makes alignments like "justify" look much better on paragraph ending lines.
local MarkedText = {}
local MarkedTextMT = {__index = MarkedText}

--- A single char of a MarkedText
---@class Marker.EffectChar
---@field str string The string the char wants to render
---@field font Marker.Font The font of the char
---@field xPlacement number The X coordinate of the char
---@field yPlacement number The Y coordinate of the char
---@field xOffset number Offset from the X coordinate (resets to 0 at the start of each update)
---@field yOffset number Offset from the Y coordinate (resets to 0 at the start of each update)
---@field disabled boolean May be set to true when getting laid out by the MarkedText (won't render and should be ignored for most purposes)
---@field effects table<string, table<string, string?>> The effects applied to this char (the key is the effect name) and all the attributes set for them
local EffectChar = {}
local EffectChatMT = {__index = EffectChar}

--- An abstract font class for drawing characters in some way
---@class Marker.Font
local AbstractFont = {}
local AbstractFontMT = {__index = AbstractFont}

--- An implementation for Marker.Font, mapping its functionality to regular love fonts
---@class Marker.LoveFont : Marker.Font
---@field font love.Font
local LoveFont = {}
local LoveFontMT = {__index = LoveFont}

---@class Marker.WrapInfo
---@field lineIndices number[] Alternating start and end indices of each line (line1start, line1end, line2start, line2end, ...)
---@field lineWidths number[] The width of each line
---@field textHeight number The height of the whole text
---@field spaceCounts number[] The amount of space chars in each line

---@alias Marker.TextAlign
---| '"start"' # Aligns to the left
---| '"center"' # Aligns to the center
---| '"end"' # Aligns to the right
---| '"middle"' # Same as "center"
---| '"left"' # Same as "start"
---| '"right"' # Same as "end"
---| '"justify"' # Spreads out the words in each line to span the entire alignBox width
---| '"letterspace"' # Adjusts letter spacing in each line to span the entire alignBox width

---@alias Marker.VerticalAlign
---| '"start"' # Aligns to the top
---| '"center"' # Aligns to the center
---| '"end"' # Aligns to the bottom
---| '"middle"' # Same as "center"
---| '"top"' # Same as "start"
---| '"bottom"' # Same as "end"

---@class Marker.Parser.TagStackEntry
---@field name string
---@field attributes table<string, string>
---@field wasAppliedToChar boolean

-- MarkedText ---------------------------------------------------------------------------------------

--- Creates a new fancy MarkedText object
---@param str? string
---@param font? love.Font|Marker.Font
---@param x? number
---@param y? number
---@param wrapLimit? number
---@param textAlign? Marker.TextAlign
---@return Marker.MarkedText
function marker.newMarkedText(str, font, x, y, wrapLimit, textAlign)
    if type(font) == "userdata" then
        ---@diagnostic disable-next-line: param-type-mismatch
        font = marker.newWrappedLoveFont(font)
    end

    local alignBoxWidth = (wrapLimit and wrapLimit ~= math.huge) and wrapLimit or 0

    -- new Marker.MarkedText
    local markedText = {
        x = x or 0,
        y = y or 0,
        wrapLimit = wrapLimit or math.huge,
        textAlign = textAlign or "start",
        verticalAlign = "start",
        alignBox = {alignBoxWidth, 0},
        font = font or marker.getDefaultFont(),
        inputString = str or "",
        effectChars = {},
        ignoreStretchOnLastLine = true
    }
    setmetatable(markedText, MarkedTextMT)

    markedText:generate()

    return markedText
end

--- Sets the text's position. The layout does not need to be updated.
---@param x number
---@param y number
function MarkedText:setPosition(x, y)
    self.x = x
    self.y = y
end

--- Sets the text's wrap limit. The layout must be updated for this to take effect.
---@param wrapLimit number
function MarkedText:setWrapLimit(wrapLimit)
    self.wrapLimit = wrapLimit
end

--- Sets the alignment of the text. The layout must be updated for this to take effect.
---@param textAlign Marker.TextAlign
---@param verticalAlign? Marker.VerticalAlign
function MarkedText:setAlign(textAlign, verticalAlign)
    self.textAlign = textAlign
    self.verticalAlign = verticalAlign or self.verticalAlign
end

--- Sets the reference textbox size the text is aligned in.
--- If a wrapLimit was specified in the constructor, the alignBox
--- width will have been set to the wrapLimit automatically.
--- 
--- The layout must be updated for this to take effect.
---@param x number
---@param y? number
function MarkedText:setAlignBox(x, y)
    self.alignBox[1] = x
    self.alignBox[2] = y or 0
end

--- Regenerates the entire MarkedText, optionally using a different input string.
--- If the input string is unchanged, it might be better to call `layout()` instead.
---@param str? string
function MarkedText:generate(str)
    str = str or self.inputString
    self.inputString = str

    local effectChars = {}

    local font = self.font

    for pos, code in utf8.codes(str) do
        local charStr = utf8.char(code)

        local effectChar = marker.newEffectChar(charStr, 0, 0, font)
        effectChars[#effectChars+1] = effectChar
    end

    self.effectChars = marker.parser.parse(effectChars)

    self:layout()
end

---@param x? number
---@param y? number
function MarkedText:draw(x, y)
    x = x or self.x
    y = y or self.y

    local chars = self.effectChars
    for charIndex = 1, #chars do
        local char = chars[charIndex]
        char:draw(x, y)
    end
end

--- Lays out the characters in the text to the correct position.
--- Called automatically by `MarkedText:generate()`.
function MarkedText:layout()
    local wrapInfo = self:getWrap()
    local chars = self.effectChars

    local lineIndices = wrapInfo.lineIndices
    local lineWidths = wrapInfo.lineWidths
    local textHeight = wrapInfo.textHeight
    local spaceCounts = wrapInfo.spaceCounts

    local alignBoxX = self.alignBox[1]
    local alignBoxY = self.alignBox[2]

    local rowShiftFactor = 0
    local textAlign = self.textAlign
    if textAlign == "center" or textAlign == "middle" then rowShiftFactor = 0.5
    elseif textAlign == "end" or textAlign == "right" then rowShiftFactor = 1 end

    local columnShiftFactor = 0
    local verticalAlign = self.verticalAlign
    if verticalAlign == "center" or verticalAlign == "middle" then columnShiftFactor = 0.5
    elseif verticalAlign == "end" or verticalAlign == "bottom" then columnShiftFactor = 1 end

    local nextX = 0
    local nextY = 0

    nextY = nextY - columnShiftFactor * textHeight + columnShiftFactor * alignBoxY

    for lineIndex = 1, #lineWidths do
        local lineStartCharIndex = lineIndices[lineIndex*2-1]
        local lineEndCharIndex = lineIndices[lineIndex*2]

        local lineWidth = lineWidths[lineIndex]
        local spaceCount = spaceCounts[lineIndex]
        local lastCharIsLineEnd = chars[lineEndCharIndex]:isLineEnding()

        -- TODO: 0-width chars shouldn't count as letters.
        -- a symbolCount should instead be counted in the getWrap method
        -- like the spaces (and spaces should be excluded from the count there).
        local letterCount = lineEndCharIndex - lineStartCharIndex + 1

        local horizontalWiggleRoom = alignBoxX - lineWidth

        -- proper justify alignment should also adjust letter spacing to an extent,
        -- as well as maybe have the ability to shrink spaces too, but the simple enough
        -- space stretching approach is good enough for now.
        local spaceStretch = (textAlign == "justify" and spaceCount > 0) and (horizontalWiggleRoom / spaceCount) or 0
        local letterStretch = (textAlign == "letterspace" and letterCount >= 2) and (horizontalWiggleRoom / (letterCount-1)) or 0
        spaceStretch = math.max(spaceStretch, 0)

        if self.ignoreStretchOnLastLine and (lineIndex == #lineWidths or lastCharIsLineEnd) then
            spaceStretch = 0
            letterStretch = 0
        end

        local tallestCharHeight = 0

        nextX = nextX - rowShiftFactor * lineWidth + rowShiftFactor * alignBoxX

        local charPrevious ---@type Marker.EffectChar?
        for charIndex = lineStartCharIndex, lineEndCharIndex do
            local char = chars[charIndex]
            local charWidth = char:getWidth()
            local charHeight = char:getHeight(true)
            local charIsSpace = char:isSpace()

            local extraSpacingLeft = 0
            local extraSpacingRight = 0

            extraSpacingLeft = extraSpacingLeft + (charIsSpace and spaceStretch or 0) / 2
            extraSpacingRight = extraSpacingRight + (charIsSpace and spaceStretch or 0) / 2

            extraSpacingLeft = extraSpacingLeft + ((charIndex == lineStartCharIndex) and (0) or (letterStretch/2))
            extraSpacingRight = extraSpacingRight + ((charIndex == lineEndCharIndex) and (0) or (letterStretch/2))

            local kerning = charPrevious and charPrevious:getKerning(char) or 0
            nextX = nextX + kerning
            nextX = nextX + extraSpacingLeft

            char:setPlacement(nextX, nextY)

            nextX = nextX + charWidth
            nextX = nextX + extraSpacingRight
            tallestCharHeight = math.max(tallestCharHeight, charHeight)

            charPrevious = char
        end

        nextX = 0
        nextY = nextY + tallestCharHeight
    end
end

---@return Marker.WrapInfo
function MarkedText:getWrap()
    local chars = self.effectChars

    local lineIndices = { 1 }
    local lineWidths = {}
    local spaceCounts = {}
    local textHeight = 0
    local currentLineWidth = 0
    local lineWidthSinceLastWrapPoint = 0
    local tallestLineChar = 0
    local tallestPreWrapPointLineChar = 0
    local currentSpaceCount = 0
    local lineSpaceCountSinceLastWrapPoint = 0

    local wrapLimit = self.wrapLimit

    local idealLineEnd ---@type integer?
    local charPrevious ---@type Marker.EffectChar?
    local shouldWrapOnNextChar = false

    local charIndex = 1
    local charsLength = #chars
    while charIndex <= charsLength do
        local char = chars[charIndex]
        local charWidth = char:getWidth()

        local kerning = charPrevious and charPrevious:getKerning(char) or 0
        local charWidthKerned = charWidth + kerning

        local charHeight = char:getHeight(true)
        local charIsSpace = char:isSpace()

        if ((currentLineWidth + charWidthKerned <= wrapLimit) and (not shouldWrapOnNextChar)) or (not charPrevious) then
            currentLineWidth = currentLineWidth + charWidthKerned
            lineWidthSinceLastWrapPoint = lineWidthSinceLastWrapPoint + charWidthKerned

            if charIsSpace then
                currentSpaceCount = currentSpaceCount + 1
                lineSpaceCountSinceLastWrapPoint = lineSpaceCountSinceLastWrapPoint + 1
            end

            if char:isIdealWrapPoint() then
                idealLineEnd = charIndex
                lineWidthSinceLastWrapPoint = 0
                lineSpaceCountSinceLastWrapPoint = 0
                tallestPreWrapPointLineChar = tallestLineChar -- this is for the previous char
            end

            tallestLineChar = math.max(tallestLineChar, charHeight)

            charPrevious = char
            shouldWrapOnNextChar = char:isLineEnding()

            charIndex = charIndex + 1
        else
            -- Wrap on current char instead of last idealLineEnd for these cases:
            if shouldWrapOnNextChar then idealLineEnd = nil end
            if char:isIdealWrapPoint() and char:isInvisibleInWrap() then idealLineEnd = nil end

            local lastLineEnd = idealLineEnd or (charIndex-1)
            charIndex = lastLineEnd+1

            local lastLineWidth = currentLineWidth - (idealLineEnd and lineWidthSinceLastWrapPoint or 0)
            local lastLineHeight = idealLineEnd and tallestPreWrapPointLineChar or tallestLineChar
            local lastLineSpaceCount = currentSpaceCount - (idealLineEnd and lineSpaceCountSinceLastWrapPoint or 0)

            local lastLineEndChar = chars[lastLineEnd]
            if lastLineEndChar:isInvisibleInWrap() and lineIndices[#lineIndices] < lastLineEnd then
                local lastLineEndCharWidth = lastLineEndChar:getWidth() + chars[lastLineEnd-1]:getKerning(lastLineEndChar)
                lastLineWidth = lastLineWidth - lastLineEndCharWidth
                lastLineSpaceCount = lastLineSpaceCount - (lastLineEndChar:isSpace() and 1 or 0)

                lastLineEndChar.disabled = true
                lastLineEnd = lastLineEnd - 1
            else
                lastLineHeight = math.max(lastLineHeight, lastLineEndChar:getHeight(true))
            end

            local nextLineStartChar = chars[charIndex]
            if nextLineStartChar:isInvisibleInWrap() then
                nextLineStartChar.disabled = true
                charIndex = charIndex + 1
            end

            charPrevious = nil
            idealLineEnd = nil
            shouldWrapOnNextChar = false
            currentLineWidth = 0
            lineWidthSinceLastWrapPoint = 0
            tallestLineChar = 0
            tallestPreWrapPointLineChar = 0
            currentSpaceCount = 0
            lineSpaceCountSinceLastWrapPoint = 0

            -- Mark ending of last line and start of next line
            lineIndices[#lineIndices+1] = lastLineEnd
            lineIndices[#lineIndices+1] = charIndex
            lineWidths[#lineWidths+1] = lastLineWidth
            spaceCounts[#spaceCounts+1] = lastLineSpaceCount
            textHeight = textHeight + lastLineHeight
        end
    end

    lineIndices[#lineIndices+1] = #chars
    lineWidths[#lineWidths+1] = currentLineWidth
    spaceCounts[#spaceCounts+1] = currentSpaceCount
    textHeight = textHeight + tallestLineChar

    -- Edge case where the last line shouldn't exist at all
    -- (line is trying to start after the last character of the string)
    if lineIndices[#lineIndices-1] > lineIndices[#lineIndices] then
        lineIndices[#lineIndices] = nil
        lineIndices[#lineIndices] = nil
        lineWidths[#lineWidths] = nil
        spaceCounts[#spaceCounts] = nil
        textHeight = textHeight - tallestLineChar
    end

    ---@type Marker.WrapInfo
    local out = {
        lineIndices = lineIndices,
        lineWidths = lineWidths,
        textHeight = textHeight,
        spaceCounts = spaceCounts
    }

    return out
end

-- EffectChar --------------------------------------------------------------------------------------

--- Creates a new special EffectChar
---@param str? string
---@param x? number
---@param y? number
---@param font? Marker.Font
---@return Marker.EffectChar
function marker.newEffectChar(str, x, y, font)
    -- new Marker.EffectChar
    local effectChar = {
        str = str or "",
        xPlacement = x or 0,
        yPlacement = y or 0,
        font = font or marker.getDefaultFont(),
        xOffset = 0,
        yOffset = 0,
        disabled = false,
        effects = {},
    }
    return setmetatable(effectChar, EffectChatMT)
end

---@return number
function EffectChar:getWidth()
    return self.font:getWidth(self.str)
end

---@param includeLineHeight? boolean
---@return number
function EffectChar:getHeight(includeLineHeight)
    return self.font:getHeight(includeLineHeight)
end

---@param nextChar Marker.EffectChar
function EffectChar:getKerning(nextChar)
    local fontA = self.font
    local fontB = nextChar.font
    local strA = self.str
    local strB = nextChar.str

    -- It's possible the fonts look identical (could be the same love font in there) or just have compatible kerning,
    -- but it's unlikely that a situation like that would even happen (why switch the font when it looks the same).
    if fontA ~= fontB then return 0 end

    return fontA:getKerning(strA, strB)
end

---@return boolean
function EffectChar:isLineEnding()
    return self.str == "\n"
end

function EffectChar:isSpace()
    local str = self.str
    if str == " " then return true end -- just a regular space for now, will add nbsp and whatnot if it becomes necessary
    return false
end

---@return boolean
function EffectChar:isIdealWrapPoint()
    local str = self.str
    if str == " " then return true end
    return false
end

---@return boolean
function EffectChar:isInvisibleInWrap()
    local str = self.str
    if str == " " then return true end
    return false
end

---@return boolean
function EffectChar:isDisabled()
    return self.disabled
end

---@param x number
---@param y number
function EffectChar:setPlacement(x, y)
    self.xPlacement = x
    self.yPlacement = y
end

---@param x? number
---@param y? number
function EffectChar:draw(x, y)
    if self:isDisabled() then return end

    x = x or 0
    y = y or 0

    local str = self.str

    local drawnX = math.floor(x + self.xPlacement + self.xOffset)
    local drawnY = math.floor(y + self.yPlacement + self.yOffset)

    self.font:draw(str, drawnX, drawnY)
end

-- Font stuff --------------------------------------------------------------------------------------

---@param str string
---@return integer
function AbstractFont:getWidth(str)
    return 0
end

---@param includeLineHeight? boolean
---@return number
function AbstractFont:getHeight(includeLineHeight)
    return 0
end

---@param leftChar string
---@param rightChar string
---@return number
function AbstractFont:getKerning(leftChar, rightChar)
    return 0
end

---@param str string
---@param x number
---@param y number
function AbstractFont:draw(str, x, y)
    return
end

for key, value in pairs(AbstractFont) do
    LoveFont[key] = value
end

----------

---@param font love.Font
function marker.newWrappedLoveFont(font)
    -- new Marker.LoveFont
    local markerLoveFont = {
        font = font
    }
    return setmetatable(markerLoveFont, LoveFontMT)
end

local defaultFont
---@return Marker.Font
function marker.getDefaultFont()
    defaultFont = defaultFont or marker.newWrappedLoveFont(love.graphics.getFont())
    return defaultFont
end

---@param str string
---@return number
function LoveFont:getWidth(str)
    return self.font:getWidth(str)
end

---@param includeLineHeight? boolean
---@return number
function LoveFont:getHeight(includeLineHeight)
    if includeLineHeight then return self.font:getHeight() * self.font:getLineHeight() end
    return self.font:getHeight()
end

---@param leftChar string
---@param rightChar string
---@return number
function LoveFont:getKerning(leftChar, rightChar)
    if leftChar == "" or rightChar == "" then return 0 end
    return self.font:getKerning(leftChar, rightChar)
end

---@param str string
---@param x number
---@param y number
function LoveFont:draw(str, x, y)
    love.graphics.print(str, self.font, x, y)
end

-- Parser ------------------------------------------------------------------------------------------

marker.parser = {}

marker.parser.allowedTagStartChars = {
    A = true, B = true, C = true, D = true,
    E = true, F = true, G = true, H = true,
    I = true, J = true, K = true, L = true,
    M = true, N = true, O = true, P = true,
    Q = true, R = true, S = true, T = true,
    U = true, V = true, W = true, X = true,
    Y = true, Z = true, a = true, b = true,
    c = true, d = true, e = true, f = true,
    g = true, h = true, i = true, j = true,
    k = true, l = true, m = true, n = true,
    o = true, p = true, q = true, r = true,
    s = true, t = true, u = true, v = true,
    w = true, x = true, y = true, z = true,
    ["_"] = true
}

marker.parser.allowedTagChars = {
    ["0"] = true,
    ["1"] = true,
    ["2"] = true,
    ["3"] = true,
    ["4"] = true,
    ["5"] = true,
    ["6"] = true,
    ["7"] = true,
    ["8"] = true,
    ["9"] = true,
    ["-"] = true,
    ["."] = true,
}
for key, value in pairs(marker.parser.allowedTagStartChars) do
    marker.parser.allowedTagChars[key] = marker.parser.allowedTagChars[key] or value
end

--- Parses and processes all tags in the given sequence of EffectChars
---@param effectChars Marker.EffectChar[]
---@return Marker.EffectChar[]
function marker.parser.parse(effectChars)
    return marker.parser.parse_text(effectChars, 1, {}, {})
end

---@param effectChar Marker.EffectChar
---@param tagStack Marker.Parser.TagStackEntry[]
local function applyTagStackToEffectChar(effectChar, tagStack)
    for tagIndex = 1, #tagStack do
        local tag = tagStack[tagIndex]
        local tagName = tag.name
        local tagAttributes = tag.attributes
        local copiedAttributes = effectChar.effects[tagName] or {}
        for attributeName, attributeValue in pairs(tagAttributes) do
            copiedAttributes[attributeName] = attributeValue
        end
        effectChar.effects[tagName] = copiedAttributes
        tag.wasAppliedToChar = true
    end
end

---@param charStr string
---@param effectChars Marker.EffectChar[]
---@param effectCharsNew Marker.EffectChar[]
---@param tagStack Marker.Parser.TagStackEntry[]
local function appendNewCharToCharOutput(charStr, effectChars, effectCharsNew, tagStack)
    if not effectChars[1] then error("effectChars can't be empty") end
    local fillerChar = marker.newEffectChar(charStr, 0, 0, effectChars[1].font)
    applyTagStackToEffectChar(fillerChar, tagStack)
    effectCharsNew[#effectCharsNew+1] = fillerChar
end

---@param effectChars Marker.EffectChar[]
---@param i integer
---@param effectCharsNew Marker.EffectChar[]
---@param tagStack Marker.Parser.TagStackEntry[]
---@return Marker.EffectChar[]
function marker.parser.parse_text(effectChars, i, effectCharsNew, tagStack)
    while i <= #effectChars do
        local char = effectChars[i]
        local charStr = char.str

        if charStr == "<" then
            return marker.parser.parse_potentialTagStart(effectChars, i, effectCharsNew, tagStack)
        end

        if charStr == "&" then
            return marker.parser.parse_potentialCharacterEntity(effectChars, i, effectCharsNew, tagStack)
        end

        applyTagStackToEffectChar(char, tagStack)
        effectCharsNew[#effectCharsNew+1] = char

        i = i + 1
    end
    return effectCharsNew
end

local definedCharacterEntities = {
    amp = "&",
    lt = "<",
    gt = ">",
    apos = "'",
    quot = '"',
}

---@param effectChars Marker.EffectChar[]
---@param i integer
---@return integer i
---@return string? parsedEntity
local function parsePotentialCharacterEntity(effectChars, i)
    if i > #effectChars then return i end
    if effectChars[i].str ~= "&" then return i end

    local j = i + 1
    local entityCode = ""
    local formatIsValid = true
    while true do
        local char = effectChars[j]
        if not char then
            formatIsValid = false
            break
        end

        local charStr = char.str
        if charStr == " " or charStr == "\n" then
            formatIsValid = false
            break
        end

        if charStr == ";" then break end
        entityCode = entityCode .. charStr
        j = j + 1
    end

    if formatIsValid and definedCharacterEntities[entityCode] then
        return j+1, definedCharacterEntities[entityCode]
    end

    return i
end

---@param effectChars Marker.EffectChar[]
---@param i integer
---@param effectCharsNew Marker.EffectChar[]
---@param tagStack Marker.Parser.TagStackEntry[]
---@return Marker.EffectChar[]
function marker.parser.parse_potentialCharacterEntity(effectChars, i, effectCharsNew, tagStack)
    local parsedEntity
    i, parsedEntity = parsePotentialCharacterEntity(effectChars, i)

    if parsedEntity then
        appendNewCharToCharOutput(parsedEntity, effectChars, effectCharsNew, tagStack)
        return marker.parser.parse_text(effectChars, i, effectCharsNew, tagStack)
    end

    -- Not a valid character entity, ignore it
    applyTagStackToEffectChar(effectChars[i], tagStack)
    effectCharsNew[#effectCharsNew+1] = effectChars[i]
    return marker.parser.parse_text(effectChars, i+1, effectCharsNew, tagStack)
end

---@param effectChars Marker.EffectChar[]
---@param i integer
---@param effectCharsNew Marker.EffectChar[]
---@param tagStack Marker.Parser.TagStackEntry[]
---@return Marker.EffectChar[]
function marker.parser.parse_potentialTagStart(effectChars, i, effectCharsNew, tagStack)
    if effectChars[i].str ~= "<" then error("Invalid tag opener") end

    if i >= #effectChars then
        effectCharsNew[#effectCharsNew+1] = effectChars[i]
        return effectCharsNew
    end

    i = i + 1

    local tagStart = effectChars[i].str
    if marker.parser.allowedTagStartChars[tagStart] then
        return marker.parser.parse_tag(effectChars, i, effectCharsNew, tagStack)
    end
    if tagStart == "/" then
        return marker.parser.parse_closingTag(effectChars, i, effectCharsNew, tagStack)
    end

    -- Not a tag, false alarm
    applyTagStackToEffectChar(effectChars[i-1], tagStack)
    effectCharsNew[#effectCharsNew+1] = effectChars[i-1]
    return marker.parser.parse_text(effectChars, i, effectCharsNew, tagStack)
end

---@param effectChars Marker.EffectChar[]
---@param i integer
---@return integer i
---@return string name
local function parseTagNameOrAttributeName(effectChars, i)
    local name = ""
    while true do
        local char = effectChars[i]
        if not char then break end

        local charStr = char.str
        if not marker.parser.allowedTagChars[charStr] then break end

        name = name .. charStr
        i = i + 1
    end
    return i, name
end

---@param effectChars Marker.EffectChar[]
---@param i integer
---@return integer i
---@return string value
local function parseTagAttributeValue(effectChars, i)
    if i > #effectChars then return i, "" end

    local quoteChar = effectChars[i].str
    if not (quoteChar == "'" or quoteChar == '"') then return i, "" end

    i = i + 1

    local value = ""
    while true do
        local foundReplacementChar = false

        local char = effectChars[i]
        if not char then break end

        local charStr = char.str
        if charStr == quoteChar then break end

        if charStr == "&" then
            local parsedEntity
            i, parsedEntity = parsePotentialCharacterEntity(effectChars, i)
            if parsedEntity then
                value = value .. parsedEntity
                foundReplacementChar = true
            end
        end

        if not foundReplacementChar then
            value = value .. charStr
            i = i + 1
        end
    end

    return i, value
end

---@param effectChars Marker.EffectChar[]
---@param i integer
---@return integer i
---@return string attributeName
---@return string attributeValue
local function parseTagAttribute(effectChars, i)
    local attributeName
    i, attributeName = parseTagNameOrAttributeName(effectChars, i)

    local equalsFound = false
    while true do
        local char = effectChars[i]
        if not char then break end

        local charStr = char.str

        if marker.parser.allowedTagStartChars[charStr] then break end
        if charStr == "/" or charStr == ">" then break end
        if charStr == "=" then equalsFound = true end

        if equalsFound and (charStr == "'" or charStr == '"') then
            local attributeValue
            i, attributeValue = parseTagAttributeValue(effectChars, i)

            return i, attributeName, attributeValue
        end

        i = i + 1
    end

    return i, attributeName, ""
end

---@param effectChars Marker.EffectChar[]
---@param i integer
---@return integer i
---@return table<string, string> attributes
---@return boolean isSelfClosing
local function parseTagBody(effectChars, i)
    local attributes = {}
    local isSelfClosing = false
    while true do
        local char = effectChars[i]
        if not char then break end

        local charStr = char.str

        if charStr == "/" then isSelfClosing = true end
        if charStr == ">" then
            i = i + 1
            break
        end

        if marker.parser.allowedTagStartChars[charStr] then
            isSelfClosing = false

            local attributeName, attributeValue
            i, attributeName, attributeValue = parseTagAttribute(effectChars, i)
            attributes[attributeName] = attributeValue
        else
            i = i + 1
        end
    end
    return i, attributes, isSelfClosing
end

---@param effectChars Marker.EffectChar[]
---@param i integer
---@param effectCharsNew Marker.EffectChar[]
---@param tagStack Marker.Parser.TagStackEntry[]
---@return Marker.EffectChar[]
function marker.parser.parse_tag(effectChars, i, effectCharsNew, tagStack)
    if not marker.parser.allowedTagStartChars[effectChars[i].str] then error("Invalid tag start") end

    local tagName, tagAttributes, tagIsSelfClosing
    i, tagName = parseTagNameOrAttributeName(effectChars, i)
    i, tagAttributes, tagIsSelfClosing = parseTagBody(effectChars, i)

    tagStack[#tagStack+1] = {
        name = tagName,
        attributes = tagAttributes,
        wasAppliedToChar = false
    }

    if tagIsSelfClosing then
        appendNewCharToCharOutput("", effectChars, effectCharsNew, tagStack)
        tagStack[#tagStack] = nil
    end

    return marker.parser.parse_text(effectChars, i, effectCharsNew, tagStack)
end

---@param effectChars Marker.EffectChar[]
---@param i integer
---@param effectCharsNew Marker.EffectChar[]
---@param tagStack Marker.Parser.TagStackEntry[]
---@return Marker.EffectChar[]
function marker.parser.parse_closingTag(effectChars, i, effectCharsNew, tagStack)
    if effectChars[i].str ~= "/" then error("Invalid closing tag start") end

    local tagName
    i, tagName = parseTagNameOrAttributeName(effectChars, i+1)

    local tagStackTop = tagStack[#tagStack]
    if tagStackTop and tagStackTop.name == tagName then
        if not tagStackTop.wasAppliedToChar then
            appendNewCharToCharOutput("", effectChars, effectCharsNew, tagStack)
        end
        tagStack[#tagStack] = nil
    end

    while true do
        local char = effectChars[i]
        if not char then break end

        local charStr = char.str
        if charStr == ">" then
            i = i + 1
            break
        end

        i = i + 1
    end

    return marker.parser.parse_text(effectChars, i, effectCharsNew, tagStack)
end

return marker