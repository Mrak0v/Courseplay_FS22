--[[
This file is part of Courseplay (https://github.com/Courseplay/courseplay)
Copyright (C) 2018 Peter Vajko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

---@class Waypoint
Waypoint = CpObject()
Waypoint.xmlKey = ".wp"

-- Waypoint is a friend class for the Course, so it can access the private members without
-- getters. The Waypoint has getters only for other classes.
-- constructor from another waypoint
---@param wp Waypoint
function Waypoint:init(wp)
	-- we initialize explicitly, no table copy as we want to have
	-- full control over what is used in this object
	self.x = wp.x or 0
	self.z = wp.z or 0
	self.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, self.x, 0, self.z)
	-- keep a copy of the generated attributes.
	---@type CourseGenerator.WaypointAttributes
	self.attributes = wp.attributes and wp.attributes:clone() or CourseGenerator.WaypointAttributes()
	self.angle = wp.angle or nil
	self.radius = wp.radius or nil
	self.rev = wp.rev or wp.reverse or false
	self.rev = self.rev or wp.gear and wp.gear == Gear.Backward
	-- dynamically added/calculated properties
	self.useTightTurnOffset = wp.useTightTurnOffset
	self.turnControls = table.copy(wp.turnControls)
	self.dToNext = wp.dToNext
	self.yRot = wp.yRot
	--- Set, when generated for a multi tool course
	self.originalMultiToolReference = wp.originalMultiToolReference
	self.usePathfinderToThisWaypoint = wp.usePathfinderToThisWaypoint
	self.usePathfinderToNextWaypoint = wp.usePathfinderToNextWaypoint
	self.headlandTransition = wp.headlandTransition
end

--- Set from a generated waypoint (output of the course generator)
---@param wp Vertex
function Waypoint.initFromGeneratedWp(wp)
	local waypoint = Waypoint({})
	waypoint.x = wp.x
	waypoint.z = -wp.y
	waypoint.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, waypoint.x, 0, waypoint.z)
	---@type CourseGenerator.WaypointAttributes
	self.attributes = wp:getAttributes():clone()
	return waypoint
end

function Waypoint.registerXmlSchema(schema, baseKey)
	local key = baseKey .. Waypoint.xmlKey .. "(?)"
	schema:register(XMLValueType.VECTOR_3, key .. "#position", "Position")
	schema:register(XMLValueType.BOOL, key .. "#rev", "Reverse")
	CourseGenerator.WaypointAttributes.registerXmlSchema(schema, key)
end

function Waypoint:setXmlValue(xmlFile, baseKey, i)
	local key = string.format("%s%s(%d)", baseKey, Waypoint.xmlKey, i - 1)
	xmlFile:setValue(key .. "#position", self.x, self.y, self.z)
	xmlFile:setValue(key .. "#rev", self.rev)
	self.attributes:setXmlValue(xmlFile, key)
end

--- Set from a saved waypoint in a xml file.
function Waypoint.initFromXmlFile(xmlFile, key)
	local waypoint = Waypoint({})
	waypoint.x, waypoint.y, waypoint.z = xmlFile:getValue(key .. '#position')
	waypoint.rev = xmlFile:getValue(key .. '#rev')
	waypoint.attributes = CourseGenerator.WaypointAttributes.initFromXmlFile(xmlFile, key)
	return waypoint
end

--- Gets the data to saves this waypoint in a xml file.
--- New attributes can be added at the bottom and shouldn't break old courses.
--- To remove attributes, they should be filled with a zero otherwise old course might be broken.
--- Every attribute needs to be a number.
function Waypoint:getXmlString()
	local v = {
		MathUtil.round(self.x,2),
		MathUtil.round(self.z,2),
		self.rowEnd or "-",
		self.rowStart or "-",
		self.isConnectingPath or "-",
		self.headlandNumber or "-",
		self.rowNumber or "-",
		self.ridgeMarker or "-",
		self.rev or "-",
		self.headlandTurn or "-",
		self.usePathfinderToNextWaypoint or "-",
		self.usePathfinderToThisWaypoint or "-",
		self.headlandTransition or "-"
	}
	return CpUtil.getXmlVectorString(v)
end

--- Get the (original, non-offset) position of a waypoint
---@return number, number, number x, y, z
function Waypoint:getPosition()
	return self.x, self.y, self.z
end

--- Get the offset position of a waypoint
---@param offsetX number left/right offset (right +, left -)
---@param offsetZ number forward/backward offset (forward +)
---@param dx number delta x to use (dx to the next waypoint by default)
---@param dz number delta z to use (dz to the next waypoint by default)
---@return number, number, number x, y, z
function Waypoint:getOffsetPosition(offsetX, offsetZ, dx, dz)
	local x, y, z = self:getPosition()
	local deltaX = dx or self.dx
	local deltaZ = dz or self.dz
	-- check for NaN
	if deltaX and deltaZ and deltaX == deltaX and deltaZ == deltaZ then
		-- X offset should be inverted if we drive reverse here (left is always left regardless of the driving direction)
		local reverse = self.reverseOffset and -1 or 1
		x = x - deltaZ * reverse * offsetX + deltaX * offsetZ
		z = z + deltaX * reverse * offsetX + deltaZ * offsetZ
	end
	return x, y, z
end

function Waypoint:setOffsetPosition(offsetX, offsetZ, dx, dz)
	self.x, self.y, self.z = self:getOffsetPosition(offsetX, offsetZ, dx, dz)
end

function Waypoint:getDistanceFromPoint(x, z)
	return MathUtil.getPointPointDistance(x, z, self.x, self.z)
end

function Waypoint:getDistanceFromVehicle(vehicle)
	local vx, _, vz = getWorldTranslation(vehicle:getAIDirectionNode() or vehicle.rootNode)
	return self:getDistanceFromPoint(vx, vz)
end

function Waypoint:getDistanceFromNode(node)
	local x, _, z = getWorldTranslation(node)
	return self:getDistanceFromPoint(x, z)
end

function Waypoint:setPosition(x, z, y)
	self.x = x 
	self.z = z 
	if y then 
		self.y = y 
	else 
		self.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
	end
end

function Waypoint:setReverseOffset()
	self.reverseOffset = true
end

function Waypoint:translate(dx, dz)
	self.x = self.x + dx
	self.z = self.z + dz
	self.y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, self.x, 0, self.z)
end

function Waypoint:clone()
	return Waypoint(self)
end

function Waypoint:getIsReverse()
	return self.rev
end

function Waypoint:isRowEnd()
	return self.attributes:isRowEnd()
end

function Waypoint:isRowStart()
	return self.attributes:isRowStart()
end

function Waypoint:isHeadlandTurn()
	return self.attributes:isHeadlandTurn()
end

function Waypoint:isHeadlandTransition()
	return self.attributes:isHeadlandTransition()
end

function Waypoint:isOnConnectingPath()
	return self.attributes:isOnConnectingPath()
end

function Waypoint:shouldUsePathfinderToNextWaypoint()
	return self.attributes:shouldUsePathfinderToNextWaypoint()
end

function Waypoint:shouldUsePathfinderToThisWaypoint()
	return self.attributes:shouldUsePathfinderToThisWaypoint()
end

function Waypoint:getRowNumber()
	return self.attributes:getRowNumber()
end

function Waypoint:setRowNumber(rowNumber)
	self.attributes:setRowNumber(rowNumber)
end

function Waypoint:setRowEnd(rowEnd)
	self.attributes:setRowEnd(rowEnd)
end

function Waypoint:setRowStart(rowStart)
	self.attributes:setRowStart(rowStart)
end

function Waypoint:resetRowStartEnd()
	self.attributes:setRowStart(false)
	self.attributes:setRowEnd(false)
end

function Waypoint:setHeadlandNumber(n)
	self.attributes:setHeadlandPassNumber(n)
end

function Waypoint:setOnConnectingPath(onConnectingPath)
	self.attributes:setOnConnectingPath(onConnectingPath)
end

function Waypoint:setOriginalMultiToolReference(ix)
	self.originalMultiToolReference = ix
end

--- Get's the reference waypoint of the original fieldwork course,
--- if the waypoint is part of a multi tool course.
---@return number|nil
function Waypoint:getOriginalMultiToolReference()
	return self.originalMultiToolReference
end

--- Makes sure the original fieldwork course waypoints are referenced here for multi tool course.
--- The multi tool course might have more or less waypoints then the original.
--- For a given section the closest reference point is linear interpolated.
---@param wps table Waypoint section
---@param sIx number First original field work course waypoint, that gets changed by this section
---@param deltaIx number Number of waypoints of the original field work course section
function Waypoint.applyOriginalMultiToolReference(wps, sIx, deltaIx)
	local factor, dIx = deltaIx / #wps, 0
	for ix=1, #wps do 
		dIx = math.floor(ix * factor)
		wps[ix]:setOriginalMultiToolReference(math.max(1, dIx) + sIx-1)
	end
end

-- a node related to a waypoint
---@class WaypointNode
WaypointNode = CpObject()
WaypointNode.MODE_NORMAL = 1
WaypointNode.MODE_LAST_WP = 2
WaypointNode.MODE_SWITCH_DIRECTION = 3
WaypointNode.MODE_SWITCH_TO_FORWARD = 4

function WaypointNode:init(name, logChanges)
	self.logChanges = logChanges
	self.node = CpUtil.createNode(name, 0, 0, 0)
end

function WaypointNode:destroy()
	CpUtil.destroyNode(self.node)
end

---@param course Course
function WaypointNode:setToWaypoint(course, ix, suppressLog)
	local newIx = math.min(ix, course:getNumberOfWaypoints())
	if newIx ~= self.ix and self.logChanges and not suppressLog then
		CpUtil.debugVehicle(CpDebug.DBG_PPC, course.vehicle, 'PPC: %s waypoint index %d', getName(self.node), ix)
	end
	self.ix = newIx
	local x, y, z = course:getWaypointPosition(self.ix)
	setTranslation(self.node, x, y, z)
	setRotation(self.node, 0, course:getWaypointYRotation(self.ix), 0)
end

-- Allow ix > #Waypoints, in that case move the node lookAheadDistance beyond the last WP
function WaypointNode:setToWaypointOrBeyond(course, ix, distance)
	--if self.ix and self.ix > ix then return end
	if ix > course:getNumberOfWaypoints() then
		-- beyond the last, so put it on the last for now
		-- but use the direction of the one before the last as the last one's is bogus
		self:setToWaypoint(course, course:getNumberOfWaypoints())
		setRotation(self.node, 0, course:getWaypointYRotation(course:getNumberOfWaypoints() - 1), 0)
		-- And now, move ahead a bit.
		local nx, ny, nz = localToWorld(self.node, 0, 0, distance)
		setTranslation(self.node, nx, ny, nz)
		if self.logChanges and self.mode and self.mode ~= WaypointNode.MODE_LAST_WP then
			CpUtil.debugVehicle(CpDebug.DBG_PPC, course.vehicle, 'PPC: last waypoint reached, moving node beyond last: %s', getName(self.node))
		end
		
		self.mode = WaypointNode.MODE_LAST_WP
	elseif course:switchingToReverseAt(ix) or course:switchingToForwardAt(ix) then
		-- just like at the last waypoint, if there's a direction switch, we want to drive up
		-- to the waypoint so we move the goal point beyond it
		-- the angle of ix is already pointing to reverse here
		self:setToWaypoint(course, ix)
		-- turn node back as this is the one before the first reverse, already pointing to the reverse direction.
		local _, yRot, _ = getRotation(self.node)
		setRotation(self.node, 0, yRot + math.pi, 0)
		-- And now, move ahead a bit.
		local nx, ny, nz = localToWorld(self.node, 0, 0, distance)
		setTranslation(self.node, nx, ny, nz)
		if self.logChanges and self.mode and self.mode ~= WaypointNode.MODE_SWITCH_DIRECTION then
			CpUtil.debugVehicle(CpDebug.DBG_PPC, course.vehicle, 'PPC: switching direction at %d, moving node beyond it: %s', ix, getName(self.node))
		end
		self.mode = WaypointNode.MODE_SWITCH_DIRECTION
	else
		if self.logChanges and self.mode and self.mode ~= WaypointNode.MODE_NORMAL then
			CpUtil.debugVehicle(CpDebug.DBG_PPC, course.vehicle, 'PPC: normal waypoint (not last, no direction change: %s', getName(self.node))
		end
		self.mode = WaypointNode.MODE_NORMAL
		self:setToWaypoint(course, ix)
	end
end

