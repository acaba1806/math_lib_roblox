local Utils = require(script.Parent.Utils)

local TurbineGenerator = {}

local STEAM_LATENT_HEAT = 2.257e6 -- J/kg
local WATER_CP = 4217 -- J/(kg*K)
local RANKINE_EFFICIENCY = 0.33
local GENERATOR_EFFICIENCY = 0.98
local TURBINE_INERTIA = 8500 -- kg*m^2
local TURBINE_DAMPING = 12000

function TurbineGenerator.defaultState()
	return {
		speed = 1800, -- RPM
		power = 0.0,
	}
end

function TurbineGenerator.steamConditions(feedwaterTemp, steamPressure, massFlow)
	feedwaterTemp = Utils.coerceNumber(feedwaterTemp, 500.0)
	steamPressure = math.max(Utils.coerceNumber(steamPressure, 6.0e6), 1.0)
	massFlow = math.max(Utils.coerceNumber(massFlow, 0.0), 0.0)
	local saturationTemp = 505 + 3.8 * math.log(steamPressure / 6.0e6)
	local energyToSat = WATER_CP * (saturationTemp - feedwaterTemp)
	local requiredHeat = energyToSat + STEAM_LATENT_HEAT
	local steamQuality = math.max(0, math.min(requiredHeat / (STEAM_LATENT_HEAT + 1e-3), 1))
	local enthalpy = feedwaterTemp * WATER_CP + steamQuality * STEAM_LATENT_HEAT
	return {
		saturationTemperature = saturationTemp,
		quality = steamQuality,
		specificEnthalpy = enthalpy,
		massFlow = massFlow,
	}
end

function TurbineGenerator.turbinePower(steam, condenserPressure)
	condenserPressure = math.max(Utils.coerceNumber(condenserPressure, 8.0e3), 1.0)
	if type(steam) ~= "table" then
		return 0.0
	end
	local massFlow = math.max(Utils.coerceNumber(steam.massFlow, 0.0), 0.0)
	local enthalpy = Utils.coerceNumber(steam.specificEnthalpy, 2.6e6)
	local expansionRatio = massFlow * math.max(enthalpy - 2.5e6, 0)
	local isentropic = expansionRatio * RANKINE_EFFICIENCY
	local backPressureFactor = math.max(0.0, 1.0 - (condenserPressure - 8.0e3) / 4.0e3)
	return isentropic * backPressureFactor
end

function TurbineGenerator.generatorOutput(turbinePower, electricalLoad)
	turbinePower = Utils.coerceNumber(turbinePower, 0.0)
	electricalLoad = Utils.coerceNumber(electricalLoad, 0.0)
	local electrical = turbinePower * GENERATOR_EFFICIENCY
	local mismatch = electrical - electricalLoad
	return {
		electrical = electrical,
		loadMismatch = mismatch,
	}
end

function TurbineGenerator.updateRotor(state, dt, torqueInput, loadTorque)
	state = state or TurbineGenerator.defaultState()
	state.speed = Utils.coerceNumber(state.speed, 1800)
	state.power = Utils.coerceNumber(state.power, 0.0)
	dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
	torqueInput = Utils.coerceNumber(torqueInput, 0.0)
	loadTorque = Utils.coerceNumber(loadTorque, torqueInput * 0.95)
	local omega = state.speed * 2 * math.pi / 60
	local acceleration = (torqueInput - loadTorque - TURBINE_DAMPING * omega) / TURBINE_INERTIA
	local nextOmega = math.max(omega + acceleration * dt, 0.0)
	return {
		speed = nextOmega * 60 / (2 * math.pi),
		power = torqueInput * nextOmega,
	}
end

return TurbineGenerator
