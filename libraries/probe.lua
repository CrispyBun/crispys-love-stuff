----------------------------------------------------------------------------------------------------
-- A decent Lua performance profiler
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

local probe = {}

--- The function the library uses to get the current time when measuring how long things take.
--- In LÖVE for example, you might want to change this to `love.timer.getTime`.
---@fun(): number
probe.getTime = os.clock

--------------------------------------------------

---@class Probe.TreeNode
---@field sectionName string The name of the code section this node represents
---@field children Probe.TreeNode[] The nested measurements of this node
---@field totalTime number How much time in total was spent with this section active
---@field lastTime number How much time was spent on this section the last time it was measured
---@field measurements number How many times in total this section was pushed
local TreeNode = {}
local TreeNodeMT = {__index = TreeNode}

---@class Probe.MeasuredSection
---@field name string
---@field pushTime number

--------------------------------------------------

local enabled = false
local stack = {} ---@type Probe.MeasuredSection[]
local trees = {} ---@type Probe.TreeNode[]

local snapshotsEnabled = true
local snapshots = {} ---@type Probe.TreeNode[]

local queuedStart ---@type string?

--- Turns on profiling.
--- 
--- This must be called before the top-level section gets pushed
--- as any pushes or pops are only registered if profiling is enabled.
function probe.start()
    enabled = true
    queuedStart = nil
end

--- Queues it so that the next time `sectionName` tries to be pushed, profiling will start.
---@param sectionName string
function probe.queueStart(sectionName)
    queuedStart = sectionName
end

--- Stops profiling.
--- 
--- This can be called any time, but any unpopped sections will be discarded.
function probe.stop(clearMeasurements)
    enabled = false

    for i = 1, #stack do
        stack[i] = nil
    end
end

---@return boolean
function probe.isActive()
    return enabled
end

--- Sets whether or not a snapshot of all measurements (stored as probe trees) should be made each time their root node pops.
--- True by default.
---@param enable boolean
function probe.setSnapshotsEnabled(enable)
    snapshotsEnabled = enable
end

--- Returns the last snapshots of the measurements taken (may be empty if snapshots are disabled).
--- 
--- These always contain the last full measurements taken and can be constantly read in real time (or any time) to get accurate data.
---@return Probe.TreeNode[]
function probe.getSnapshots()
    return snapshots
end

--- Destroys the measurements Probe has made so far,
--- letting you start measuring again with a clean slate.
function probe.clearMeasurements()
    for i = 1, #trees do
        trees[i] = nil
    end
    for i = 1, #snapshots do
        snapshots[i] = nil
    end
end

--- Pushes a new section of code that should have its time measured.
--- 
--- This must be paired with an accompanying pop.
--- If another section was pushed before this section was popped, that section must be popped first.
--- 
--- The root-level push defines a new tree of nested measurements.
--- You can have multiple trees as long as their pushes and pops never overlap.
---@param sectionName string The name (and identifier) of the section of code that's being measured
function probe.push(sectionName)
    if sectionName == queuedStart then probe.start() end
    if not enabled then return end

    stack[#stack+1] = {
        name = sectionName,
        pushTime = probe.getTime()
    }
end

--- Pops (and finishes measuring) the last pushed section of code.
--- 
--- If the section name is provided, then this will error if the section being popped doesn't match the name.
--- This can make it easier to catch accidental forgotten pops in the code.
---@param sectionName? string
function probe.pop(sectionName)
    if not enabled then return end

    local popTime = probe.getTime()

    local section = stack[#stack]
    if not section then error("Trying to pop a section, but the stack of pushed sections is empty", 2) end
    if sectionName and section.name ~= sectionName then error(string.format("Trying to pop section '%s', but the current section at the top of the stack is '%s'", sectionName, section.name), 2) end

    ---@type Probe.TreeNode
    local rootNode
    for treeIndex = 1, #trees do
        if trees[treeIndex].sectionName == stack[1].name then
            rootNode = trees[treeIndex]
            break
        end
    end
    if not rootNode then
        rootNode = probe.newTreeNode(stack[1].name)
        trees[#trees+1] = rootNode
    end

    local currentNode = rootNode
    for stackIndex = 2, #stack do
        local name = stack[stackIndex].name
        local child = currentNode:getChildFromName(name)

        if not child then
            child = probe.newTreeNode(name)
            currentNode.children[#currentNode.children+1] = child
        end

        currentNode = child
    end

    local currentSection = stack[#stack]
    stack[#stack] = nil

    local timeSpent = popTime - currentSection.pushTime

    currentNode.lastTime = timeSpent
    currentNode.totalTime = currentNode.totalTime + timeSpent
    currentNode.measurements = currentNode.measurements + 1

    if snapshotsEnabled and #stack == 0 then
        probe.queryTrees(snapshots)
    end
end

--- Returns clones of the current measurement data (stored in probe trees), which are safe to be viewed and edited.
--- May insert them into an existing table if supplied.
---
--- Note that calling this while some code sections still haven't been popped will
--- cause the data to be slightly inaccurate, as some of the child nodes may have spent more time being measured than their parents.
---@param receivingTable table?
---@return Probe.TreeNode[]
function probe.queryTrees(receivingTable)
    if receivingTable then
        for i = 1, #receivingTable do
            receivingTable[i] = nil
        end
    end
    local out = receivingTable or {}

    for treeIndex = 1, #trees do
        out[treeIndex] = trees[treeIndex]:clone()
    end

    return out
end

--------------------------------------------------

--- Returns a new probe tree node which can hold profiling measurement data.
--- Used internally.
---@param sectionName? string
---@return Probe.TreeNode
function probe.newTreeNode(sectionName)
    ---@type Probe.TreeNode
    local node = {
        sectionName = sectionName or "Unknown Section",
        children = {},
        totalTime = 0,
        lastTime = 0,
        measurements = 0
    }
    return setmetatable(node, TreeNodeMT)
end

--- Returns a string showing the most important data from the tree in a hierarchical way (with an optional max depth).
---@param maxDepth? number
---@param _currentDepth? number
---@param _parentTime? number
---@return string
function TreeNode:stringifySimpleHierarchy(maxDepth, _currentDepth, _parentTime)
    _currentDepth = _currentDepth or 0
    maxDepth = maxDepth or math.huge

    if _currentDepth > maxDepth then return "" end

    local chunks = {}

    chunks[#chunks+1] = string.rep("  ", _currentDepth)
    chunks[#chunks+1] = self.sectionName
    chunks[#chunks+1] = string.rep(" ", 15 - #self.sectionName)
    chunks[#chunks+1] = "[Total time: "
    chunks[#chunks+1] = string.format("%.2f", self.totalTime)
    chunks[#chunks+1] = "; Avg. time: "
    chunks[#chunks+1] = string.format("%.4f", self.totalTime / self.measurements)
    chunks[#chunks+1] = "]"

    if _parentTime then
        local percent = (self.totalTime / _parentTime) * 100

        chunks[#chunks+1] = " ("
        chunks[#chunks+1] = string.format("%.2f", percent)
        chunks[#chunks+1] = "% of parent's time)"
    end

    chunks[#chunks+1] = "\n"

    for childIndex = 1, #self.children do
        chunks[#chunks+1] = self.children[childIndex]:stringifySimpleHierarchy(maxDepth, _currentDepth + 1, self.totalTime)
    end

    return table.concat(chunks)
end

--- Creates an identical clone of this node and all its children
function TreeNode:clone()
    ---@type Probe.TreeNode
    local clone = {
        sectionName = self.sectionName,
        children = {},
        totalTime = self.totalTime,
        lastTime = self.lastTime,
        measurements = self.measurements
    }

    for childIndex = 1, #self.children do
        clone.children[childIndex]  = self.children[childIndex]:clone()
    end

    return setmetatable(clone, TreeNodeMT)
end

--- Returns the node's immediate child with the given section name,
--- or `nil` if such child isn't found
---@param sectionName string
---@return Probe.TreeNode?
function TreeNode:getChildFromName(sectionName)
    local children = self.children
    for childIndex = 1, #children do
        if children[childIndex].sectionName == sectionName then return children[childIndex] end
    end
    return nil
end

--------------------------------------------------

-- Set `PROBE_DISABLE_PROFILING` to `true` before
-- requiring the library to make it fully dead
-- so it never profiles anything.

---@type unknown
local function emptyFn() end

---@diagnostic disable-next-line: undefined-global
if PROBE_DISABLE_PROFILING then
    probe.start = emptyFn
    probe.stop = emptyFn
    probe.clearMeasurements = emptyFn
    probe.push = emptyFn
    probe.pop = emptyFn
end

return probe