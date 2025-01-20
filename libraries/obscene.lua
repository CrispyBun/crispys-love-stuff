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

--- Events that can be called in the scene.  
--- There are some built-in ones, but other custom ones can be injected into the class.
--- The first argument must always be the scene itself, the rest can be anything.
---@class Obscene.SceneEvents
---@field register? fun(scene: Obscene.Scene, manager: Obscene.SceneManager) Called when the scene is registered into a manager (this is the only type of event that will trigger for inactive scenes)
---@field load? fun(scene: Obscene.Scene, ...) Called when the scene is selected to be active. Useful for setting up the scene and adding objects to it.
---@field unload? fun(scene: Obscene.Scene) Called when the active scene is switched from this one to a different one. Useful for destroying/resetting the scene and any objects inside it.

---@class Obscene.SceneManager
---@field currentScene? string The currently selected scene which will receive event callbacks
---@field scenes table<string, Obscene.Scene> All the named scenes in the manager
---@field callbacks Obscene.SceneEvents Callbacks to events that will trigger no matter which scene is active (will not trigger if no scene is active)
local SceneManager = {}
local SceneManagerMT = {__index = SceneManager}

---@class Obscene.Scene
---@field variables Obscene.SceneVariables Variables associated with the scene
---@field callbacks Obscene.SceneEvents Callbacks to events for the scene
local Scene = {}
local SceneMT = {__index = Scene}

-- Managers ----------------------------------------------------------------------------------------

--- Always returns the same scene manager.
---@return Obscene.SceneManager
function obscene.getGlobalManager()
    return obscene.globalSceneManager
end

--- Creates a new scene manager.
---@return Obscene.SceneManager
function obscene.newSceneManager()
    -- new Obscene.SceneManager
    local manager = {
        currentScene = nil,
        scenes = {},
        callbacks = {}
    }
    return setmetatable(manager, SceneManagerMT)
end

--- Registers a new scene to the manager's scenes.
---@param name string
---@param scene Obscene.Scene
function SceneManager:registerScene(name, scene)
    if self.scenes[name] then error("A scene is already registered under the name '" .. tostring(scene) .. "'", 2) end
    self.scenes[name] = scene

    if self.callbacks.register then self.callbacks.register(scene, self) end
    if scene.callbacks.register then scene.callbacks.register(scene, self) end
end
SceneManager.addScene = SceneManager.registerScene

--- Sets the current scene.  
--- The optional vararg will be passed into the `load` event callback of the scene, if there is one.
---@param sceneName string
function SceneManager:setScene(sceneName, ...)
    if not self.scenes[sceneName] then error("Scene '" .. tostring(sceneName) .. "' does not exist in this manager", 2) end

    self:announce('unload')
    self.currentScene = sceneName
    self:announce('load', ...)
end

--- Makes no scene currently selected (all callbacks will simply be voided on an unselected scene).  
--- This is the state a new scene manager is in before a scene is selected.
function SceneManager:unsetScene()
    self:announce('unload')
    self.currentScene = nil
end

--- If a scene is selected, returns the currently selected scene (string), as well as the scene object itself.
---@return string?
---@return Obscene.Scene?
function SceneManager:getCurrentScene()
    local current = self.currentScene
    if current == nil then return nil, nil end
    return current, self.scenes[current]
end

--- Returns the currently active scene object, or `nil` if no scene is active.
---@return Obscene.Scene?
function SceneManager:getCurrentSceneObject()
    local current = self.currentScene
    if current == nil then return nil end
    return self.scenes[current]
end

--- Sets (or overwrites) the callback for the given event in the manager.  
--- The callbacks can also be set directly, like so:
--- ```lua
--- manager.callbacks.load = function(scene, ...)
---     -- ...
--- end
--- ```
---@param event string
---@param callback function
function SceneManager:setEventCallback(event, callback)
    self.callbacks[event] = callback
end

--- Triggers the callbacks for the given event in the currently active scene (if one is active).
---@param event string
---@param ... unknown
---@return unknown?
function SceneManager:announce(event, ...)
    local currentScene = self:getCurrentSceneObject()
    if not currentScene then return end

    if self.callbacks[event] then self.callbacks[event](currentScene, ...) end
    return currentScene:announce(event, ...)
end
SceneManager.callEvent = SceneManager.announce

-- Scenes ------------------------------------------------------------------------------------------

--- Creates a new scene.
---@return Obscene.Scene
function obscene.newScene()
    -- new Obscene.Scene
    local scene = {
        variables = {},
        callbacks = {}
    }
    return setmetatable(scene, SceneMT)
end

--- Sets (or overwrites) the callback for the given event in the scene.  
--- The callbacks can also be set directly, like so:
--- ```lua
--- scene.callbacks.load = function(scene, ...)
---     -- ...
--- end
--- ```
---@param event string
---@param callback function
function Scene:setEventCallback(event, callback)
    self.callbacks[event] = callback
end

--- Triggers the callback for the given event in the scene.
---@param event string
---@param ... unknown
---@return unknown?
function Scene:announce(event, ...)
    local callback = self.callbacks[event]
    if not callback then return end
    return callback(self, ...)
end
Scene.callEvent = Scene.announce

obscene.globalSceneManager = obscene.newSceneManager()
return obscene