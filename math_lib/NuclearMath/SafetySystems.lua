-- Module: SafetySystems
-- Description: Defines core functionality for NuclearMath (SafetySystems component)-- Copyright 2025 Terranova Incorporated
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations under the License.
local Utils = require(script.Parent.Utils)
local Constants = require(script.Parent.Constants)

local SafetySystems = {}

function SafetySystems.temperatureMargin(fuelTemp, limit)
	fuelTemp = Utils.coerceNumber(fuelTemp, Constants.ReferenceTemperature or 565.0)
	limit = Utils.coerceNumber(limit, 2200) -- K
	local margin = (limit - fuelTemp) / limit
	return Utils.clamp(margin, -1.0, 1.0)
end

function SafetySystems.dnbr(heatFlux, criticalHeatFlux)
	heatFlux = math.max(Utils.coerceNumber(heatFlux, 1.0e5), 1e-6)
	criticalHeatFlux = math.max(Utils.coerceNumber(criticalHeatFlux, 1.0e6), 1e-3)
	return criticalHeatFlux / heatFlux
end

function SafetySystems.containmentPressureRise(steamMass, freeVolume, temperature)
	steamMass = math.max(Utils.coerceNumber(steamMass, 0.0), 0.0)
	freeVolume = math.max(Utils.coerceNumber(freeVolume, 8000), 1.0)
	temperature = math.max(Utils.coerceNumber(temperature, 373.15), 273.15)
	local R = Constants.GasConstant / 0.018 -- steam gas constant
	return steamMass * R * temperature / freeVolume
end

function SafetySystems.emergencyCoreCooling(flowRate, injectionTemp, corePower)
	flowRate = math.max(Utils.coerceNumber(flowRate, 0.0), 0.0)
	injectionTemp = Utils.coerceNumber(injectionTemp, 300.0)
	corePower = math.max(Utils.coerceNumber(corePower, 0.0), 1e-3)
	local cp = Constants.WaterSpecificHeat
	local quenchRate = flowRate * cp * (Constants.CoolantBoilingPoint - injectionTemp)
	local coverage = Utils.clamp(quenchRate / corePower, 0.0, 2.0)
	return {
		quenchRate = quenchRate,
		coverage = coverage,
		minutesToFlood = 4.0 / math.max(coverage, 1e-3),
	}
end

function SafetySystems.coreDamageFrequency(eventsPerYear, mitigated)
	eventsPerYear = math.max(Utils.coerceNumber(eventsPerYear, 0.0), 0.0)
	mitigated = Utils.clamp(Utils.coerceNumber(mitigated, 0.9), 0.0, 1.0)
	return eventsPerYear * (1 - mitigated)
end

function SafetySystems.radiationDose(release, shielding)
	release = math.max(Utils.coerceNumber(release, 0.0), 0.0)
	shielding = math.max(Utils.coerceNumber(shielding, 0.0), 0.0)
	local base = release * 0.35
	local attenuation = math.exp(-shielding * 0.25)
	return base * attenuation
end

function SafetySystems.failureProbability(componentA, componentB, componentC)
	componentA = Utils.clamp(Utils.coerceNumber(componentA, 0.0), 0.0, 1.0)
	componentB = Utils.clamp(Utils.coerceNumber(componentB, 0.0), 0.0, 1.0)
	componentC = Utils.clamp(Utils.coerceNumber(componentC, 0.0), 0.0, 1.0)
	local independent = (1 - componentA) * (1 - componentB) * (1 - componentC)
	return 1 - independent
end

function SafetySystems.eventClassification(power, reactivity, coolantLoss)
	power = Utils.coerceNumber(power, 1.0)
	reactivity = Utils.coerceNumber(reactivity, 0.0)
	coolantLoss = Utils.coerceNumber(coolantLoss, 0.0)
	if coolantLoss > 0.2 or reactivity > 0.01 then
		return "AOA" -- abnormal occurrence
	end
	if math.abs(power - 1.0) > 0.1 then
		return "ABN"
	end
	return "NOM"
end

return SafetySystems


