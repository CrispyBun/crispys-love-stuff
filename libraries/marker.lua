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
---@field font Marker.Font The font used to generate and render the text
---@field inputString string The string used to generate the text
---@field effectChars Marker.EffectChar[] The generated EffectChars
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

-- MarkedText ---------------------------------------------------------------------------------------

--- Creates a new fancy MarkedText object
---@param str? string
---@param font? love.Font|Marker.Font
---@return Marker.MarkedText
function marker.newMarkedText(str, font)
    if type(font) == "userdata" then
        ---@diagnostic disable-next-line: param-type-mismatch
        font = marker.newWrappedLoveFont(font)
    end

    -- new Marker.MarkedText
    local markedText = {
        font = font or marker.getDefaultFont(),
        inputString = str or "",
        effectChars = {}
    }
    setmetatable(markedText, MarkedTextMT)

    markedText:generate()

    return markedText
end

--- Regenerates the entire MarkedText, optionally using a different input string
---@param str? string
function MarkedText:generate(str)
    str = str or self.inputString
    self.inputString = str

    local effectChars = {}
    self.effectChars = effectChars

    local font = self.font

    for pos, code in utf8.codes(str) do
        local charStr = utf8.char(code)

        local effectChar = marker.newEffectChar(charStr, 0, 0, font)
        effectChars[#effectChars+1] = effectChar
    end

    self:layout()
end

function MarkedText:draw()
    local chars = self.effectChars
    for charIndex = 1, #chars do
        local char = chars[charIndex]
        char:draw()
    end
end

--- Lays out the characters in the text to the correct position.
--- Called automatically by `MarkedText:generate()`.
function MarkedText:layout()
    local maxLineWidth, lineEndings = self:getWrap()
    local chars = self.effectChars

    local nextX = 0
    local nextY = 0

    for lineIndex = 1, #lineEndings do
        local lineStartIndex = (lineEndings[lineIndex-1] or 0) + 1
        local lineEndIndex = lineEndings[lineIndex]

        local tallestCharHeight = 0

        local charPrevious ---@type Marker.EffectChar?
        for charIndex = lineStartIndex, lineEndIndex do
            local char = chars[charIndex]
            local charWidth = char:getWidth()
            local charHeight = char:getHeight(true)

            local kerning = charPrevious and charPrevious:getKerning(char) or 0
            nextX = nextX + kerning

            char:setPlacement(nextX, nextY)

            nextX = nextX + charWidth
            tallestCharHeight = math.max(tallestCharHeight, charHeight)

            charPrevious = char
        end

        nextX = 0
        nextY = nextY + tallestCharHeight
    end
end

---@return number maxLineWidth
---@return integer[] lineEndingIndices
function MarkedText:getWrap()
    local chars = self.effectChars

    local lineEndings = {}
    local largestLineWidth = 0
    local currentLineWidth = 0
    local currentLineCharCount = 0

    local wrapLimit = math.huge

    local mustWrapNextIteration = false
    for charIndex = 1, #chars do
        local char = chars[charIndex]
        local charWidth = char:getWidth()

        if (not mustWrapNextIteration) and (currentLineWidth + charWidth <= wrapLimit or currentLineCharCount == 0) then
            currentLineCharCount = currentLineCharCount + 1
            currentLineWidth = currentLineWidth + charWidth
        else
            currentLineCharCount = 1
            currentLineWidth = charWidth

            lineEndings[#lineEndings+1] = charIndex-1
        end

        largestLineWidth = math.max(largestLineWidth, currentLineWidth)
        mustWrapNextIteration = char:isLineEnding()
    end

    lineEndings[#lineEndings+1] = #chars

    return largestLineWidth, lineEndings
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

---@param x number
---@param y number
function EffectChar:setPlacement(x, y)
    self.xPlacement = x
    self.yPlacement = y
end

function EffectChar:draw()
    local str = self.str
    local x = self.xPlacement + self.xOffset
    local y = self.yPlacement + self.yOffset
    self.font:draw(str, x, y)
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
    return self.font:getKerning(leftChar, rightChar)
end

---@param str string
---@param x number
---@param y number
function LoveFont:draw(str, x, y)
    love.graphics.print(str, self.font, x, y)
end

return marker