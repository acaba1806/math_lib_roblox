-- Module: ThermalStructures
-- Description: Defines core functionality for NuclearMath (ThermalStructures component)-- Copyright 2025 Terranova Incorporated
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations under the License.
local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)

local ThermalStructures = {}

function ThermalStructures.defaultFuelRod()
	return {
		radius = 0.0045, -- m fuel pellet radius
		claddingOuterRadius = 0.00475, -- m
		gapConductance = 12000, -- W/(m^2*K)
		fuelConductivity = Constants.FuelThermalConductivity,
		claddingConductivity = Constants.CladdingConductivity,
		fuelDensity = Constants.FuelDensity,
		fuelHeatCapacity = Constants.FuelHeatCapacity,
		linearHeatRate = 18e3, -- W/m
		activeLength = 3.66, -- m
	}
end

local function sanitizeRod(rod)
	local defaults = ThermalStructures.defaultFuelRod()
	if type(rod) ~= "table" then
		return defaults
	end

	local sanitized = {}
	for key, value in pairs(defaults) do
		sanitized[key] = Utils.coerceNumber(rod[key], value)
	end
	return sanitized
end

local function logMeanTemperatureDifference(surface1, surface2, radius1, radius2)
	local ratio = radius2 / radius1
	if math.abs(surface1 - surface2) < 1e-6 then
		return surface1 -- isothermal case
	end
	local numerator = surface1 - surface2
	local denominator = math.log(ratio)
	return numerator / denominator
end

function ThermalStructures.radialConductance(rod)
	rod = sanitizeRod(rod)

	local fuelResistance = math.log(rod.claddingOuterRadius / rod.radius) / (2 * math.pi * rod.fuelConductivity * rod.activeLength)
	local gapResistance = 1 / (rod.gapConductance * 2 * math.pi * rod.radius * rod.activeLength)
	local claddingResistance = math.log(rod.claddingOuterRadius / (rod.claddingOuterRadius - Constants.CladdingThickness))
	claddingResistance = claddingResistance / (2 * math.pi * rod.claddingConductivity * rod.activeLength)

	return 1 / (fuelResistance + gapResistance + claddingResistance)
end

function ThermalStructures.heatCapacity(rod)
	rod = sanitizeRod(rod)
	local volume = math.pi * rod.radius ^ 2 * rod.activeLength
	return volume * rod.fuelDensity * rod.fuelHeatCapacity
end

function ThermalStructures.fuelTemperature(power, coolantBulkTemp, rod)
	rod = sanitizeRod(rod)
	power = Utils.coerceNumber(power, rod.linearHeatRate * rod.activeLength)
	coolantBulkTemp = Utils.coerceNumber(coolantBulkTemp, Constants.ReferenceTemperature or 565.0)
	local hm = ThermalStructures.radialConductance(rod)
	local mRate = rod.linearHeatRate * rod.activeLength
	local deltaT = mRate / (hm * 2 * math.pi * rod.radius * rod.activeLength)

	return coolantBulkTemp + deltaT * Utils.clamp(power / (rod.linearHeatRate * rod.activeLength), 0.0, 2.0)
end

function ThermalStructures.hotSpotTemperature(power, coolantTemp, rod)
	rod = sanitizeRod(rod)
	power = Utils.coerceNumber(power, rod.linearHeatRate * rod.activeLength)
	coolantTemp = Utils.coerceNumber(coolantTemp, Constants.ReferenceTemperature or 565.0)
	local base = ThermalStructures.fuelTemperature(power, coolantTemp, rod)
	return base + 30.0 -- empirical peaking factor margin
end

function ThermalStructures.axialTemperatureProfile(power, coolantInlet, coolantOutlet, rod)
	rod = sanitizeRod(rod)
	power = Utils.coerceNumber(power, rod.linearHeatRate * rod.activeLength)
	coolantInlet = Utils.coerceNumber(coolantInlet, Constants.ReferenceTemperature or 565.0)
	coolantOutlet = Utils.coerceNumber(coolantOutlet, coolantInlet + 25)
	local segments = 20
	local profile = {}
	for i = 0, segments do
		local axialFraction = i / segments
		local localCoolant = coolantInlet + (coolantOutlet - coolantInlet) * axialFraction
		local localPower = power * (1 + 0.1 * math.sin(math.pi * axialFraction)) -- cosine axial peaking
		profile[i + 1] = ThermalStructures.fuelTemperature(localPower, localCoolant, rod)
	end
	return profile
end

function ThermalStructures.pitchToDiameterRatio(pinPitch, rod)
	rod = sanitizeRod(rod)
	pinPitch = Utils.coerceNumber(pinPitch, 0.0125)
	return pinPitch / (2 * rod.claddingOuterRadius)
end

function ThermalStructures.burnup(powerHistory, timeStep, rod)
	rod = sanitizeRod(rod)
	powerHistory = Utils.ensureTable(powerHistory)
	timeStep = math.max(Utils.coerceNumber(timeStep, 0.0), 1e-3)
	local energy = 0.0
	for _, power in ipairs(powerHistory) do
		energy = energy + Utils.coerceNumber(power, 0.0) * timeStep
	end
	local totalMass = ThermalStructures.heatCapacity(rod) / rod.fuelHeatCapacity
	return energy / (totalMass * 1e3 * 24 * 3600) -- MWd/tU approximation
end

return ThermalStructures


