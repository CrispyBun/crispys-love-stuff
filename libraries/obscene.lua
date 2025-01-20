----------------------------------------------------------------------------------------------------
-- An objectively usable game scene library
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

local obscene = {}

-- Types -------------------------------------------------------------------------------------------

--- Variables to be associated with scenes.
--- Inject fields into this class to annotate your own scene variables.
---@class Obscene.SceneVariables

---@class Obscene.SceneManager
---@field currentScene? string The currently selected scene which will receive callbacks
---@field scenes table<string, Obscene.SceneMaker> All the scenes in this manager, named
local SceneManager = {}
local SceneManagerMT = {__index = SceneManager}

---@class Obscene.SceneMaker
---@field init? fun(self: Obscene.Scene, ...) Constructor for the scene object
---@field variables Obscene.SceneVariables Variables to be shallow copied into the scene's `variables` table
---@field instancedScene? Obscene.Scene The last scene that was instanced using this scene maker
local SceneMaker = {}
local SceneMakerMT = {__index = SceneMaker}

---@class Obscene.Scene
---@field variables Obscene.SceneVariables Variables associated with the scene
local Scene = {}
local SceneMT = {__index = Scene}

-- Managers ----------------------------------------------------------------------------------------

--- Creates a new scene manager.
---@return Obscene.SceneManager
function obscene.newSceneManager()
    -- new Obscene.SceneManager
    local manager = {
        currentScene = nil,
        scenes = {}
    }
    return setmetatable(manager, SceneManagerMT)
end

--- Always returns the same scene manager.
---@return Obscene.SceneManager
function obscene.getGlobalManager()
    return obscene.globalSceneManager
end

--- Sets the current scene.
---@param scene string
function SceneManager:setScene(scene)
    if not self.scenes[scene] then error("Scene '" .. tostring(scene) .. "' does not exist in this manager", 2) end
    self.currentScene = scene
end

--- Makes no scene currently selected (all callbacks will simply be voided on an unselected scene).  
--- This is the state a new scene manager is in before a scene is selected.
function SceneManager:unsetScene()
    self.currentScene = nil
end

obscene.globalSceneManager = obscene.newSceneManager()

return obscene