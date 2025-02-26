----------------------------------------------------------------------------------------------------
-- A shrimple texture atlas packer for LÖVE,
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

local packing = {}

-- Packing algorithm based on: https://codeincomplete.com/articles/bin-packing/

-- Definitions -------------------------------------------------------------------------------------

---@alias Packing.InputTexturePaddingMode
---| '"none"' # The texture is not padded
---| '"grow"' # The sides of the texture are expanded by 1px

---@class Packing.InputTexture
---@field id string String ID to easily find the texture in the packed atlas later. Multiple textures can be grouped under the same ID, which is useful for animations (though make sure to define the order).
---@field order? number If grouping multiple textures by the same ID, this number determines their order. Nil is considered 0.
---@field texture love.Texture The texture to pack
---@field quad? love.Quad How to crop the texture before packing
---@field paddingMode Packing.InputTexturePaddingMode The way the texture is padded. Default is "grow" for all textures.
local InputTexture = {}
local InputTextureMT = {__index = InputTexture}

---@class Packing.PackedTexture
---@field atlas love.Texture The packed atlas the texture belongs to
---@field quad love.Quad The part of the packed atlas the texture is packed to

---@class Packing.PackingTree
---@field inputTextures Packing.InputTexture[] The textures to be packed into the atlas
---@field rootNode Packing.PackingTreeNode
local PackingTree = {}
local PackingTreeMT = {__index = PackingTree}

---@class Packing.PackingTreeNode
---@field x number
---@field y number
---@field width number
---@field height number
local PackingTreeNode = {}
local PackingTreeNodeMT = {__index = PackingTreeNode}

-- Input texture preparation -----------------------------------------------------------------------

--- Creates a new input texture to be used in a `PackingTree`.
---@param id string The ID to find the texture by later. Multiple textures can be associated with the same ID.
---@param texture love.Texture The texture to pack
---@param quad? love.Quad Optional quad to crop the texture before packing
---@param order? number Optional value to determine the order of the texture relative to other textures grouped by the same ID
---@return Packing.InputTexture
function packing.newInputTexture(id, texture, quad, order)
    -- new Packing.InputTexture
    local input = {
        id = id,
        texture = texture,
        quad = quad,
        order = order,
        paddingMode = "grow"
    }
    return setmetatable(input, InputTextureMT)
end

--- Creates a new array of input textures from a texture and an array of quads, setting the textures' order to be in the same order as the quads after packing.
---@param id string The ID to find the textures by later
---@param texture love.Texture The texture of the spritesheet
---@param quads love.Quad[] The quads defining the frames of the animation
---@return Packing.InputTexture[]
function packing.newInputSpritesheet(id, texture, quads)
    ---@type Packing.InputTexture[]
    local inputs = {}
    for quadIndex = 1, #quads do
        inputs[#inputs+1] = packing.newInputTexture(id, texture, quads[quadIndex], quadIndex)
    end
    return inputs
end

--- Returns the dimensions the texture will take up on the packed atlas. Takes into account the quad and padding.
---@return number width
---@return number height
function InputTexture:getDimensions()
    local width, height = self:getDimensionsPaddingless()

    local paddingMode = self.paddingMode

    if paddingMode == "none" then
        return width, height
    end

    if paddingMode == "grow" then
        return width+2, height+2
    end

    error("Unknown padding mode: " .. tostring(paddingMode))
end

--- Returns the width and height of the texture, without taking padding into account.
--- The optional quad *is* taken into account.
---@return number width
---@return number height
function InputTexture:getDimensionsPaddingless()
    local width, height = self.texture:getDimensions()
    if self.quad then _, _, width, height = self.quad:getViewport() end
    return width, height
end

--- Draws the input texture as it will be drawn onto the packed atlas.
---@param x number
---@param y number
function InputTexture:draw(x, y)
    local paddingMode = self.paddingMode

    if paddingMode == "none" then
        self:drawPaddingless(x, y)
        return
    end

    if paddingMode == "grow" then
        local width, height = self:getDimensionsPaddingless()
        local sx, sy, sw, sh = love.graphics.getScissor()

        -- Top-left corner pixel
        love.graphics.setScissor(x, y, 1, 1)
        self:drawPaddingless(x, y)

        -- Top-right corner pixel
        love.graphics.setScissor(x+width+1, y, 1, 1)
        self:drawPaddingless(x+2, y)

        -- Bottom-left corner pixel
        love.graphics.setScissor(x, y+height+1, 1, 1)
        self:drawPaddingless(x, y+2)

        -- Bottom-right corner pixel
        love.graphics.setScissor(x+width+1, y+height+1, 1, 1)
        self:drawPaddingless(x+2, y+2)

        -- Top pixel row
        love.graphics.setScissor(x+1, y, width, 1)
        self:drawPaddingless(x+1, y)

        -- Left pixel column
        love.graphics.setScissor(x, y+1, 1, height)
        self:drawPaddingless(x, y+1)

        -- Right pixel column
        love.graphics.setScissor(x+width+1, y+1, 1, height)
        self:drawPaddingless(x+2, y+1)

        -- Bottom pixel row
        love.graphics.setScissor(x+1, y+width+1, width, 1)
        self:drawPaddingless(x+1,y+2)

        -- Actual image in the middle
        love.graphics.setScissor(x+1, y+1, width, height)
        self:drawPaddingless(x+1, y+1)

        love.graphics.setScissor(sx, sy, sw, sh) -- reset scissor
        return
    end

    error("Unknown padding mode: " .. tostring(paddingMode))
end

--- Similar to `InputTexture:draw()`, but always draws as if the padding mode is set to `"none"`.
---@param x number
---@param y number
function InputTexture:drawPaddingless(x, y)
    if self.quad then
        love.graphics.draw(self.texture, self.quad, x, y)
    else
        love.graphics.draw(self.texture, x, y)
    end
end

-- The packing tree --------------------------------------------------------------------------------

--- Creates a new packing tree for creating a texture atlas.
---@return Packing.PackingTree
function packing.newPackingTree()
    -- new Packing.PackingTree
    local tree = {
        inputTextures = {}
    }
    return setmetatable(tree, PackingTreeMT)
end

--- Adds an input texture to the tree.
---@param inputTexture Packing.InputTexture
---@return self self
function PackingTree:addInputTexture(inputTexture)
    self.inputTextures[#self.inputTextures+1] = inputTexture
    return self
end

--- Creates and adds a new input texture to the tree.
---@param id string The ID to find the texture by later. Multiple textures can be associated with the same ID.
---@param texture love.Texture The texture to pack
---@param quad? love.Quad Optional quad to crop the texture before packing
---@param order? number Optional value to determine the order of the texture relative to other textures grouped by the same ID
---@return self self
function PackingTree:addNewInputTexture(id, texture, quad, order)
    local input = packing.newInputTexture(id, texture, quad, order)
    return self:addInputTexture(input)
end

--- Adds an array of input textures to the tree.
---@param inputTextures any
---@return Packing.PackingTree
function PackingTree:addInputTextures(inputTextures)
    for inputIndex = 1, #inputTextures do
        self:addInputTexture(inputTextures[inputIndex])
    end
    return self
end

return packing