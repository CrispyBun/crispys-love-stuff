----------------------------------------------------------------------------------------------------
-- A simple (yet very messy) LÖVE 9-slicing
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
----------------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2026 Ava "CrispyBun" Špráchalů

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

local slice = {}

---@class Slice.SlicedTexture
---@field texture love.Texture
---@field quadTL love.Quad
---@field quadT love.Quad
---@field quadTR love.Quad
---@field quadR love.Quad
---@field quadBR love.Quad
---@field quadB love.Quad
---@field quadBL love.Quad
---@field quadL love.Quad
---@field quadC love.Quad
local SlicedTexture = {}
local SlicedTextureMT = {__index = SlicedTexture}

--- Creates a new sliced texture from 1 texture (where the full texture is the rectangle to be 9-sliced)
--- and the sizes of the top-left and bottom-right corners (the sizes of the other slices will be inferred from those).
---@param texture love.Texture
---@param topLeftWidth number
---@param topLeftHeight number
---@param bottomRightWidth number
---@param bottomRightHeight number
---@return Slice.SlicedTexture
function slice.newSlicedTexture(texture, topLeftWidth, topLeftHeight, bottomRightWidth, bottomRightHeight)
    local textureWidth, textureHeight = texture:getDimensions()

    local centerWidth = textureWidth - topLeftWidth - bottomRightWidth
    local centerHeight = textureHeight - topLeftHeight - bottomRightHeight

    local quadTL = love.graphics.newQuad(0, 0, topLeftWidth, topLeftHeight, texture)
    local quadT = love.graphics.newQuad(topLeftWidth, 0, centerWidth, topLeftHeight, texture)
    local quadTR = love.graphics.newQuad(topLeftWidth + centerWidth, 0, bottomRightWidth, topLeftHeight, texture)
    local quadR = love.graphics.newQuad(topLeftWidth + centerWidth, topLeftHeight, bottomRightWidth, centerHeight, texture)
    local quadBR = love.graphics.newQuad(topLeftWidth + centerWidth, topLeftHeight + centerHeight, bottomRightWidth, bottomRightHeight, texture)
    local quadB = love.graphics.newQuad(topLeftWidth, topLeftHeight + centerHeight, centerWidth, bottomRightHeight, texture)
    local quadBL = love.graphics.newQuad(0, topLeftHeight + centerHeight, topLeftWidth, bottomRightHeight, texture)
    local quadL = love.graphics.newQuad(0, topLeftHeight, topLeftWidth, centerHeight, texture)
    local quadC = love.graphics.newQuad(topLeftWidth, topLeftHeight, centerWidth, centerHeight, texture)

    return slice.newSlicedTextureFromQuads(texture, quadTL, quadT, quadTR, quadR, quadBR, quadB, quadBL, quadL, quadC)
end

--- Creates a new sliced texture from a texture (can be a texture atlas)
--- and each of the 9 slices given as quads (in clockwise order, with the center one being last).
---@param texture love.Texture
---@param topLeftQuad love.Quad
---@param topQuad love.Quad
---@param topRightQuad love.Quad
---@param rightQuad love.Quad
---@param bottomRightQuad love.Quad
---@param bottomQuad love.Quad
---@param bottomLeftQuad love.Quad
---@param leftQuad love.Quad
---@param centerQuad love.Quad
---@return Slice.SlicedTexture
function slice.newSlicedTextureFromQuads(texture, topLeftQuad, topQuad, topRightQuad, rightQuad, bottomRightQuad, bottomQuad, bottomLeftQuad, leftQuad, centerQuad)
    ---@type Slice.SlicedTexture
    local sliced = {
        texture = texture,
        quadTL = topLeftQuad,
        quadT = topQuad,
        quadTR = topRightQuad,
        quadR = rightQuad,
        quadBR = bottomRightQuad,
        quadB = bottomQuad,
        quadBL = bottomLeftQuad,
        quadL = leftQuad,
        quadC = centerQuad,
    }
    return setmetatable(sliced, SlicedTextureMT)
end

--------------------------------

---@param x number
---@param y number
---@param width number
---@param height number
---@param textureScale? number
function SlicedTexture:draw(x, y, width, height, textureScale)
    textureScale = textureScale or 1

    local _, _, topLeftWidth, topLeftHeight = self.quadTL:getViewport()
    local _, _, bottomRightWidth, bottomRightHeight = self.quadBR:getViewport()
    topLeftWidth = topLeftWidth * textureScale
    topLeftHeight = topLeftHeight * textureScale
    bottomRightWidth = bottomRightWidth * textureScale
    bottomRightHeight = bottomRightHeight * textureScale

    local _, _, centerWidth, centerHeight = self.quadC:getViewport()
    centerWidth = centerWidth * textureScale
    centerHeight = centerHeight * textureScale

    local minWidth = topLeftWidth + bottomRightWidth
    local minHeight = topLeftHeight + bottomRightHeight
    if width < minWidth then x = x - math.floor((minWidth - width) / 2 + 0.5) end
    if height < minHeight then y = y - math.floor((minHeight - height) / 2 + 0.5) end
    width = math.max(width, minWidth)
    height = math.max(height, minHeight)

    -- TODO:
    -- this whole thing should be spritebatched,
    -- but that won't be compatible with the current trimming i do with scissor,
    -- so a special class that holds a spritebatch and extra quads will prolly be necessary for that.

    local texture = self.texture

    -- excuse how awfully ugly this is lol

    -- Corners
    love.graphics.draw(texture, self.quadTL, x, y, 0, textureScale, textureScale)
    love.graphics.draw(texture, self.quadTR, x + width - bottomRightWidth, y, 0, textureScale, textureScale)
    love.graphics.draw(texture, self.quadBR, x + width - bottomRightWidth, y + height - bottomRightHeight, 0, textureScale, textureScale)
    love.graphics.draw(texture, self.quadBL, x, y + height - bottomRightHeight, 0, textureScale, textureScale)

    -- Top + bottom
    local horizontalProgress = x + topLeftWidth
    local horizontalRemaining = width - topLeftWidth - bottomRightWidth
    while horizontalRemaining > 0 do
        local sx, sy, sw, sh = love.graphics.getScissor()
        if centerWidth > horizontalRemaining then love.graphics.setScissor(horizontalProgress, y, horizontalRemaining, height) end

        love.graphics.draw(texture, self.quadT, horizontalProgress, y, 0, textureScale, textureScale)
        love.graphics.draw(texture, self.quadB, horizontalProgress, y + height - bottomRightHeight, 0, textureScale, textureScale)
        horizontalProgress = horizontalProgress + centerWidth
        horizontalRemaining = horizontalRemaining - centerWidth

        love.graphics.setScissor(sx, sy, sw, sh)
    end

    -- Left + right
    local verticalProgress = y + topLeftHeight
    local verticalRemaining = height - topLeftHeight - bottomRightHeight
    while verticalRemaining > 0 do
        local sx, sy, sw, sh = love.graphics.getScissor()
        if centerHeight > verticalRemaining then love.graphics.setScissor(x, verticalProgress, width, verticalRemaining) end

        love.graphics.draw(texture, self.quadL, x, verticalProgress, 0, textureScale, textureScale)
        love.graphics.draw(texture, self.quadR, x + width - bottomRightWidth, verticalProgress, 0, textureScale, textureScale)
        verticalProgress = verticalProgress + centerHeight
        verticalRemaining = verticalRemaining - centerHeight

        love.graphics.setScissor(sx, sy, sw, sh)
    end

    -- Center
    horizontalProgress = x + topLeftWidth
    horizontalRemaining = width - topLeftWidth - bottomRightWidth
    while horizontalRemaining > 0 do
        verticalProgress = y + topLeftHeight
        verticalRemaining = height - topLeftHeight - bottomRightHeight
        while verticalRemaining > 0 do
            local sx, sy, sw, sh = love.graphics.getScissor()
            love.graphics.setScissor(horizontalProgress, verticalProgress, horizontalRemaining, verticalRemaining)

            love.graphics.draw(texture, self.quadC, horizontalProgress, verticalProgress, 0, textureScale, textureScale)
            verticalProgress = verticalProgress + centerHeight
            verticalRemaining = verticalRemaining - centerHeight

            love.graphics.setScissor(sx, sy, sw, sh)
        end
        horizontalProgress = horizontalProgress + centerWidth
        horizontalRemaining = horizontalRemaining - centerWidth
    end
end

return slice