----------------------------------------------------------------------------------------------------
-- A wrapper for LÖVE's random generators
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

local roll = {}

-- Types -------------------------------------------------------------------------------------------

---@class Roll.RandomGenerator
---@field generator love.RandomGenerator The actual love generator to use for random functions
local RandomGenerator = {}
local RandomGeneratorMT = {__index = RandomGenerator}

-- Generators yipee --------------------------------------------------------------------------------

--- Creates a new random generator
---@return Roll.RandomGenerator
function roll.newRandomGenerator()
    -- new Roll.RandomGenerator
    local generator = {
        generator = love.math.newRandomGenerator()
    }
    return setmetatable(generator, RandomGeneratorMT)
end

--- Returns a random number with the same arguments as `love.math.random()`.
---@param min integer
---@param max integer
---@return number
---@overload fun(max: integer): number
---@overload fun(): number
function RandomGenerator:random(min, max)
    return self.generator:random(min, max)
end

RandomGeneratorMT.__call = function (self, min, max)
    return self:random(min, max)
end

return roll