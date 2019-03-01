AddCSLuaFile()

print("LOADING HERE!")

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.Category = "nZombies Unlimited"
ENT.Author = "Zet0r"
ENT.Spawnable = true

--------------
-- Callable: Functions you can call, but really shouldn't overwrite
-- Overridables: These can be overridden to make your own implementation and are called internally by the base. They all have a default (as seen here).
--------------

--[[-------------------------------------------------------------------------
Localization/optimization
---------------------------------------------------------------------------]]
local nzu = nzu
local getalltargetableplayers = nzu.GetAllTargetablePlayers
local CurTime = CurTime

local function validtarget(ent)
	return IsValid(ent) and ent:IsTargetable()
end

--[[-------------------------------------------------------------------------
Initialization
---------------------------------------------------------------------------]]

------- Overridables -------

-- Lets you determine what class of model this zombie is, along with a default
-- if it cannot be chosen by the gamemode's Model Packs settings
function ENT:SelectModel()
	return "zombie", "models/nzombies/nzombie_honorguard.mdl"
end

-- Called after each event to determine its base movement animation
-- This should be dependent on the zombie's speed
-- It can be cached in the OnSpawn or in the
function ENT:SelectMovementSequence()
	return "nz_walk_ad1"
end

-- Called by the round when the Zombie spawns
-- It is given the curve-based speed from Round as an argument
-- but it can manage its own modifications if needed
function ENT:SelectMovementSpeed(speed)
	return 100
end

-- Called as the zombie spawns before it starts its Spawning event
-- Also called on respawns, so it's not always on initial creation!
function ENT:OnSpawn() end

--[[-------------------------------------------------------------------------
Targeting
---------------------------------------------------------------------------]]

------- Callables -------
function ENT:GetTarget() return self.Target end -- Get the current target
function ENT:SetTarget(t) if self:AcceptTarget(t) then self.Target = t end end -- Sets the target for the next path update
function ENT:SetTargetLocked(b) self.TargetLocked = b end -- Stops the Zombie from retargetting and keeps this target while it is valid and targetable
function ENT:SetNextRetarget(time) self.NextRetarget = CurTime() + time end -- Sets the next time the Zombie will repath to its target
function ENT:Retarget() -- Causes a retarget
	if self.TargetLocked and validtarget(ent) then return end
	self.Target = self:SelectTarget()
end

------- Overridables -------

-- Lets you determine what targets this Zombie can go for
-- Allows immunity to specific SetTargets, such as Monkey Bombs or Gersch Devices
function ENT:AcceptTarget(t)
	return t:IsTargetable()
end

-- Lets your determine what target to go for next upon retargeting
function ENT:SelectTarget()
	local mindist = math.huge
	local target
	for k,v in pairs(getalltargetableplayers()) do
		local d = self:GetRangeTo(v)
		if d < mindist and self:AcceptTarget(v) then
			target = v
			mindist = d
		end
	end

	return target, mindist
end

-- Lets you determine how long until the next retarget
-- This is called after the path is computed; NOT after retarget
function ENT:CalculateNextRetarget(dist)
	return 5
end

--[[-------------------------------------------------------------------------
Pathing
---------------------------------------------------------------------------]]

------- Callables -------
function ENT:ForceRepath() self.NextRepath = 0 end -- Forces the Zombie to recompute its path next tick
function ENT:SetNextRepath(time) self.NextRepath = time end -- Sets how long until the next time the bot will repath. Relative to current path's age

------- Overridables -------
-- function ENT.ComputePath() end -- This is commented out as the default is 'nil' (default path generator)

function ENT:OnStuck() -- Called when the zombie is stuck
	self:Respawn()
end

-- Called after a repath. This lets you determine how long before the bath should be recomputed
-- It is a good optimization idea to base this off of the prior path's length
function ENT:CalculateNextRepath()
	return 2
end

-- When a path ends. Either when the goal is reached, or when no path could be found
-- This is where you should trigger your attack event or idle
function ENT:OnPathEnd()
	if IsValid(self.Target) and not self.PreventAttack then
		self:TriggerEvent("Attack", self.Target)
	else
		self:Timeout(2)
	end
end

--[[-------------------------------------------------------------------------
Attacking
---------------------------------------------------------------------------]]

------- Callables -------

-- Perform an attack
-- It selects an attack animation and plays it, dealing damage during its moments of impact
-- A damage info can be passed, otherwise a default is created
function ENT:AttackTarget(target, dmg)
	if IsValid(target) then
		local dmg = dmg
		if not dmg then
			dmg = DamageInfo()
			dmg:SetDamage(self.Damage)
			dmg:SetDamageType(DMG_SLASH)
			dmg:SetAttacker(self)
			--dmg:SetDamageForce()
		end

		-- Perform the attack with the function of hurting the target!
		self:DoAttackFunction(target, function(self, target)
			if self:GetRangeTo(target) <= self.AttackRange then target:TakeDamageInfo(dmg) end
		end, true)
	end
end

-- Plays an attack animation and at the moment of impact, executes the function
-- This should only be called in an event handler (or otherwise in the bot's coroutine)
function ENT:DoAttackFunction(target, func, multihit)
	local attack = self:SelectAttack(target)
	self.loco:FaceTowards(target)

	self:ResetSequence(attack.Sequence)
	local seqdur = self:SequenceDuration(self:LookupSequence(attack.Sequence))

	if multihit then
		-- Support using multiple hit times
		local lasttime = 0
		for i = 1,#attack.Impacts do
			local delay = seqdur*attack.Impacts[i]
			coroutine.wait(delay - lasttime)
			func(self, target) -- Call the function
			lasttime = delay
		end
	else
		-- Only execute with the first hit
		coroutine.wait(seqdur*attack.Impacts[1])		
		func(self, target)
	end
end

------- Overridables -------

-- Select which attack sequence table to use for an upcoming attack
-- This can be dependant on the target, but could also be anything
-- We just pick a random in the AttackSequences table here
function ENT:SelectAttack(target)
	return self.AttackSequences[math.random(#self.AttackSequences)]
end

-- List of different attack sequences, and the cycle at which they impact
-- Impacts are in cycle (0-1), the percentage through the sequence
-- It may contain multiple entries, at which point the Zombie will hit multiple times
-- They must be sequential.
-- These are also used for ENT:DoAttackFunction(), only first if 'multihit' is not true
ENT.AttackSequences = {
	{Sequence = "swing", Impacts = {0.5}}
}

--[[-------------------------------------------------------------------------
Events
---------------------------------------------------------------------------]]

------- Callables -------
function ENT:GetCurrentEvent() return self.ActiveEvent end -- Returns the string ID of the currently played event, if any

------- Overridables -------
ENT.Events = {} -- A table of events that this zombie supports

-- Play a basic spawn animation before moving on
ENT.Events.Spawn = function(self)
	if self.SpawnSequence then
		self:PlaySequenceAndWait(self.SpawnSequence)
	end
end

-- Perform a basic attack on the given target
ENT.Events.Attack = function(self, target)
	self:AttackTarget(target or self.Target)
end

function ENT.Events.BarricadeTear = function(self, barricade)
	if not barricade:HasAvailablePlanks() then
		self:Timeout(2) -- Do nothing for 2 seconds
	return end

	local pos = barricade:GetAvailableTearPosition(self)
	if not pos then
		self:Timeout(2) -- Do nothing for 2 seconds
	return end

	-- We got a barricade position, move towards it
	local result = self:MoveToPos(pos, {lookahead = 20, tolerance = 20, maxage = 3})
	if result == "ok" then
		-- We're in position
		self.loco:FaceTowards(barricade:GetPos())
		while barricade:HasAvailablePlanks() do
			local attack = self:SelectAttack(barricade)
			local impact = attack.Impacts[1]
			local seqdur = self:SequenceDuration(self:LookupSequence(attack.Sequence))
			local time = seqdur*impact

			local plank = barricade:ReservePlank(self)
			self:Timeout(barricade:GetTearTime(plank) - time) -- We wait as long so that the attack matches the tear time
			self:ResetSequence(attack.Sequence)

			coroutine.wait(time)
			barricade:TearPlank(plank, self)
			coroutine.wait(seqdur - time)
		end
	else
		self:Timeout(2)
	end
end

-- Gets the Event Table from an ID. This can be used to randomly pick
-- or to parse values based on other factors such as movement speed
-- It can also generate events if need to be
-- If it returns nil, the event triggered will use the caller's fallback (if any)
function ENT:GetEvent(id)
	local event = self.Events[id]
	if event[1] then return event[math.random(#event)] -- Pick a random if a subtable
	return event
end

--[[-------------------------------------------------------------------------
Core
Below here is the base code that you shouldn't override
(but you still can if you really want to)
---------------------------------------------------------------------------]]
function ENT:Initialize()
	local m,fallback = self:SelectModel()
	self:SetModel(fallback)

	self.Path = Path("Chase")
	self.Path:SetMinLookAheadDistance(200)
	self.Path:SetGoalTolerance(32)

	self:SetNextPathUpdate(0)
	self:SetNextRetarget(0)

	self:TriggerEvent("Spawn")
end

function ENT:RunBehaviour()
	while true do
		if self.ActiveEvent then
			self:EventHandler(self.EventData) -- This handler should be holding the routine until it is done

			self.ActiveEvent = nil
			self.EventData = nil
		else
			local ct = CurTime()
			if ct >= self.NextRetarget then
				self.Target, dist = self:SelectTarget()
				self:SetNextRetarget(self:CalculateNextRetarget(dist))
			end

			local path = self.Path
			if self.EventEnded then -- After an event has ended, do a repath if needed
				if not path:IsValid() then
					path:Compute(self, self.Target:GetPos(), self.ComputePath)
					self:SetNextRepath(self:CalculateNextRepath())
				end
				self.EventEnded = nil
				self:SetSequence(self:SelectMovementSequence())
			end

			if not path:IsValid() then -- We reached the goal, or path terminated for another reason
				self:OnPathEnd()
			else
				if path:GetAge() >= self.NextRepath then
					path:Compute(self, self.Target:GetPos(), self.ComputePath)
					self:SetNextRepath(self:CalculateNextRepath())
				end
				path:Chase(self)
			end
		end
	end
end

function ENT:Timeout(time)
	coroutine.wait(time)
end

--[[-------------------------------------------------------------------------
Events System
Attach custom handler functions to the Zombie's current behaviour
Each Zombie class may override the handler given they have an event of the same ID
Pass potential data as the third argument rather than directly in the handler
---------------------------------------------------------------------------]]
function ENT:TriggerEvent(id, handler, data)
	if self.ActiveEvent then return end
	
	self.EventHandler = self.Events[id] or handler
	self.EventData = data
end
 
function ENT:RequestTerminateEvent()
	if self.ActiveEvent then
		self.Event_Terminate = true
	end
end
-- Build event handlers respecting this flag if possible
function ENT:ShouldEventTerminate() return self.Event_Terminate end