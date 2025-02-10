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

--- A function that can be implemented which is called for all newly created scenes. Useful for setting up scene variables.
---@type fun(scene: Obscene.Scene)
obscene.sceneSetup = nil

--- A function that can be implemented which is called for all newly created managers. Useful for setting up manager variables.
---@type fun(scene: Obscene.SceneManager)
obscene.managerSetup = nil

-- Types -------------------------------------------------------------------------------------------

--- Variables to be associated with scenes.
--- Inject fields into this class to annotate your own scene variables.
---@class Obscene.SceneVariables

--- Same as `Obscene.SceneVariables`, but for managers.
---@class Obscene.ManagerVariables

--- Events that can be called in the scene.  
--- There are some built-in ones, but other custom ones can be injected into the class.
--- The first argument must always be the scene itself, the rest can be anything.
---@class Obscene.SceneEvents
---@field register? fun(scene: Obscene.Scene, manager: Obscene.SceneManager) Called when the scene is registered into a manager (this is the only type of event that will trigger for inactive scenes)
---@field unregister? fun(scene: Obscene.Scene, manager: Obscene.SceneManager) Called when the scene is unregistered from a manager (this is the only type of event that will trigger for inactive scenes)
---@field init? fun(scene: Obscene.Scene) Called once when the scene is made active in a manager for the first time. Useful for setting up things in the scene that only ever need to be set up once.
---@field load? fun(scene: Obscene.Scene, ...) Called when the scene is selected to be active. Useful for setting up the scene and adding objects to it.
---@field unload? fun(scene: Obscene.Scene) Called when the active scene is switched from this one to a different one. Useful for destroying/resetting the scene and any objects inside it.

---@class Obscene.SceneManager
---@field currentScene? string The currently selected scene which will receive event callbacks
---@field scenes table<string, Obscene.Scene> All the named scenes in the manager
---@field callbacks Obscene.SceneEvents Callbacks to events that will trigger no matter which scene is active (will not trigger if no scene is active)
---@field variables Obscene.ManagerVariables Variables associated with the manager
local SceneManager = {}
local SceneManagerMT = {__index = SceneManager}

---@class Obscene.Scene
---@field variables Obscene.SceneVariables Variables associated with the scene
---@field callbacks Obscene.SceneEvents Callbacks to events for the scene
---@field initCalled boolean Boolean controlling whether the `init` event will be called for this scene the next time it's made active
local Scene = {}
local SceneMT = {__index = Scene}

-- Managers ----------------------------------------------------------------------------------------

--- Always returns the same scene manager.
---@return Obscene.SceneManager
function obscene.getGlobalManager()
    obscene.globalSceneManager = obscene.globalSceneManager or obscene.newSceneManager()
    return obscene.globalSceneManager
end

--- Creates a new scene manager.
---@return Obscene.SceneManager
function obscene.newSceneManager()
    -- new Obscene.SceneManager
    local manager = {
        currentScene = nil,
        scenes = {},
        callbacks = {},
        variables = {}
    }

    setmetatable(manager, SceneManagerMT)
    if obscene.managerSetup then obscene.managerSetup(manager) end
    return manager
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

--- Unregisters a previously registered scene from the manager.  
---@param name string
function SceneManager:unregisterScene(name)
    if not self.scenes[name] then error("Scene '" .. tostring(name) .. "' does not exist in this manager", 2) end
    local scene = self.scenes[name]

    if self.callbacks.unregister then self.callbacks.unregister(scene, self) end
    if scene.callbacks.unregister then scene.callbacks.unregister(scene, self) end

    self.scenes[name] = nil
end
SceneManager.removeScene = SceneManager.unregisterScene

--- Sets the current scene.  
--- The optional vararg will be passed into the `load` event callback of the scene, if there is one.
---@param sceneName string
function SceneManager:setScene(sceneName, ...)
    if not self.scenes[sceneName] then error("Scene '" .. tostring(sceneName) .. "' does not exist in this manager", 2) end

    self:announce('unload')
    self.currentScene = sceneName
    self:announce('load', ...)
end
SceneManager.switchScene = SceneManager.setScene

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
--- ```lua
--- function love.update(dt)
---     manager:announce('update', dt)
--- end
--- ```
---@param event string
---@param ... unknown
---@return unknown?
function SceneManager:announce(event, ...)
    local currentScene = self:getCurrentSceneObject()
    if not currentScene then return end

    if event == 'load' and not currentScene.initCalled then
        self:announce('init')
        currentScene.initCalled = true
    end

    if self.callbacks[event] then self.callbacks[event](currentScene, ...) end
    return currentScene:announce(event, ...)
end
SceneManager.callEvent = SceneManager.announce

--- Returns the variables table of the manager, to be read or edited.
---@return Obscene.ManagerVariables
function SceneManager:getVariables()
    return self.variables
end

-- Scenes ------------------------------------------------------------------------------------------

--- Creates a new scene.
---@return Obscene.Scene
function obscene.newScene()
    -- new Obscene.Scene
    local scene = {
        variables = {},
        callbacks = {},
        initCalled = false
    }

    setmetatable(scene, SceneMT)
    if obscene.sceneSetup then obscene.sceneSetup(scene) end
    return scene
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

--- Returns the variables table of the scene, to be read or edited.
---@return Obscene.SceneVariables
function Scene:getVariables()
    return self.variables
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

return obscene