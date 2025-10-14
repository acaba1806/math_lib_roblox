-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations under the License.
local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)

local CoolantChemistry = {}

function CoolantChemistry.defaultBoronConcentration()
	return 1500 -- ppm
end

function CoolantChemistry.phFromBoron(ppm, temperature)
	ppm = math.max(Utils.coerceNumber(ppm, CoolantChemistry.defaultBoronConcentration()), 0.0)
	temperature = math.max(Utils.coerceNumber(temperature, Constants.ReferenceTemperature or 565.0), 273.15)
	local dissociationConstant = 1.77e-9 * math.exp(4200 * (1 / 298.15 - 1 / temperature))
	local hydrogen = math.sqrt(math.abs(dissociationConstant) * (ppm / 1e6))
	hydrogen = math.max(hydrogen, 1e-12)
	local pH = -math.log(hydrogen) / math.log(10)
	return pH
end

function CoolantChemistry.boronWorth(ppm, temperature)
	ppm = math.max(Utils.coerceNumber(ppm, CoolantChemistry.defaultBoronConcentration()), 0.0)
	temperature = math.max(Utils.coerceNumber(temperature, Constants.ReferenceTemperature or 565.0), 273.15)
	local referencepH = CoolantChemistry.phFromBoron(ppm, temperature)
	local deltaRho = -6.0e-6 * (ppm - CoolantChemistry.defaultBoronConcentration())
	return deltaRho, referencepH
end

function CoolantChemistry.lithiumConcentration(pH, temperature)
	pH = Utils.coerceNumber(pH, 7.2)
	temperature = math.max(Utils.coerceNumber(temperature, Constants.ReferenceTemperature or 565.0), 273.15)
	local Kw = 1.0e-14 * math.exp(4000 * (1 / 298.15 - 1 / temperature))
	local hydrogen = 10 ^ (-pH)
	return Kw / math.max(hydrogen, 1e-12)
end

function CoolantChemistry.corrosionRate(temperature, ppm)
	temperature = math.max(Utils.coerceNumber(temperature, Constants.ReferenceTemperature or 565.0), 273.15)
	ppm = math.max(Utils.coerceNumber(ppm, CoolantChemistry.defaultBoronConcentration()), 0.0)
	local baseRate = 5.0e-7 -- m/year
	local tempFactor = math.exp(0.015 * (temperature - Constants.ReferenceTemperature))
	local chemistryFactor = 1 + 0.0003 * math.abs(ppm - CoolantChemistry.defaultBoronConcentration())
	return baseRate * tempFactor * chemistryFactor
end

function CoolantChemistry.activityCoefficient(temperature, boron, lithium)
	temperature = math.max(Utils.coerceNumber(temperature, Constants.ReferenceTemperature or 565.0), 273.15)
	boron = math.max(Utils.coerceNumber(boron, CoolantChemistry.defaultBoronConcentration()), 0.0)
	lithium = math.max(Utils.coerceNumber(lithium, 1.0), 0.0)
	local ionicStrength = 0.5 * ((boron / 1e6) ^ 2 + (lithium / 1e6) ^ 2)
	local A = 0.51
	local B = 0.33
	local denominator = 1 + B * math.sqrt(ionicStrength)
	if denominator <= 0 then
		return 1.0
	end
	return math.exp(-A * ionicStrength / denominator)
end

return CoolantChemistry



