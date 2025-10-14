-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations under the License.
local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)
local CoreKinetics = require(script.Parent.CoreKinetics)
local ThermalHydraulics = require(script.Parent.ThermalHydraulics)
local ThermalStructures = require(script.Parent.ThermalStructures)
local ControlSystems = require(script.Parent.ControlSystems)
local TurbineGenerator = require(script.Parent.TurbineGenerator)
local CoolantChemistry = require(script.Parent.CoolantChemistry)
local SafetySystems = require(script.Parent.SafetySystems)

local Simulation = {}

function Simulation.defaultParameters()
	local loop = ThermalHydraulics.defaultLoop()
	return {
		core = CoreKinetics.defaultParameters(),
		loop = loop,
		fuelRod = ThermalStructures.defaultFuelRod(),
		targetPower = 1.0,
		steamPressure = 6.2e6,
		feedwaterTemperature = 510.0,
		electricalLoad = 1000e6,
		pressurizerPressure = Constants.CoolantPressure,
	}
end

local function sanitizeParams(rawParams)
	local defaults = Simulation.defaultParameters()
	if type(rawParams) ~= "table" then
		return defaults
	end

	local params = Utils.deepCopy(defaults)

	if rawParams.core then
		params.core = CoreKinetics.defaultParameters()
		for key, value in pairs(rawParams.core) do
			params.core[key] = value
		end
	end

	if rawParams.loop then
		local loopDefaults = ThermalHydraulics.defaultLoop()
		params.loop = {}
		for key, value in pairs(loopDefaults) do
			params.loop[key] = rawParams.loop[key] or value
		end
	end

	if rawParams.fuelRod then
		local rodDefaults = ThermalStructures.defaultFuelRod()
		params.fuelRod = {}
		for key, value in pairs(rodDefaults) do
			params.fuelRod[key] = rawParams.fuelRod[key] or value
		end
	end

	params.targetPower = Utils.coerceNumber(rawParams.targetPower, defaults.targetPower)
	params.steamPressure = Utils.coerceNumber(rawParams.steamPressure, defaults.steamPressure)
	params.feedwaterTemperature = Utils.coerceNumber(rawParams.feedwaterTemperature, defaults.feedwaterTemperature)
	params.electricalLoad = Utils.coerceNumber(rawParams.electricalLoad, defaults.electricalLoad)
	params.pressurizerPressure = Utils.coerceNumber(rawParams.pressurizerPressure, defaults.pressurizerPressure)

	return params
end

function Simulation.initialState(params)
	params = sanitizeParams(params)
	local loop = params.loop
	return {
		core = CoreKinetics.initialState(params.core),
		coolant = {
			inletTemp = params.core.referenceCoolantTemp,
			outletTemp = params.core.referenceCoolantTemp + 25,
			massFlow = loop.massFlowRate,
			pressure = loop.primaryPressure,
			level = 1.0,
			deltaT = 25.0,
		},
		pump = {
			speed = 3600,
			torque = ThermalHydraulics.pumpTorque(3600, loop),
		},
		turbine = TurbineGenerator.defaultState(),
		pressurizer = {
			pressure = params.pressurizerPressure,
			heaterFraction = 0.1,
			sprayValve = 0.0,
		},
		control = {
			controlRodInsertion = 0.3,
			boronPpm = CoolantChemistry.defaultBoronConcentration(),
			axialOffset = 0.0,
		},
		safety = {
			dnbr = 1.5,
			temperatureMargin = 0.2,
		},
		feedwaterFlow = loop.massFlowRate * 0.55,
		steamPressure = params.steamPressure,
		time = 0.0,
	}
end

local function createControllers(params)
	local controllers = {}
	controllers.rod = ControlSystems.reactivityController(params.targetPower * params.core.referencePower)
	controllers.feedwater = ControlSystems.feedwaterController(params.steamPressure)
	controllers.boron = ControlSystems.differentialBoronControl(0.0)
	controllers.pressurizerSpray = ControlSystems.pressurizerSprayControl(params.pressurizerPressure)
	controllers.pressurizerHeater = ControlSystems.pressurizerHeaterControl(params.pressurizerPressure)
	controllers.axialOffset = ControlSystems.axialOffsetControl(0.0)
	return controllers
end

function Simulation.newPlant(customParams)
	local params = sanitizeParams(customParams)
	local plant = {
		params = params,
		state = Simulation.initialState(params),
		controllers = createControllers(params),
	}
	return plant
end

local function applyControl(plant, dt, inputs)
	inputs = Utils.ensureTable(inputs)
	dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)

	local state = plant.state
	local params = plant.params
	local controllers = plant.controllers

	local actualPower = state.core.power
	local margin = state.safety.temperatureMargin or 0.2

	local insertionRate = controllers.rod(actualPower, dt, margin)
	state.control.controlRodInsertion = Utils.clamp(
		state.control.controlRodInsertion + insertionRate * dt,
		0.0,
		1.0
	)

	if inputs.controlRodOverride then
		state.control.controlRodInsertion = Utils.clamp(inputs.controlRodOverride, 0.0, 1.0)
	end

	local spray = controllers.pressurizerSpray(state.pressurizer.pressure, dt)
	local heater = controllers.pressurizerHeater(state.pressurizer.pressure, dt)

	state.pressurizer.sprayValve = Utils.clamp(spray, 0.0, 1.0)
	state.pressurizer.heaterFraction = Utils.clamp(heater, 0.0, 1.0)

	state.control.boronPpm = controllers.boron(state.core.reactivity, dt)
	state.control.axialOffset = state.control.axialOffset + controllers.axialOffset(state.control.axialOffset, dt) * dt

	local measuredSteam = Utils.coerceNumber(state.steamPressure or inputs.steamPressure or plant.params.steamPressure, plant.params.steamPressure)
	local feedwaterAdjustment = controllers.feedwater(measuredSteam, dt)
	local baseFeedwater = Utils.coerceNumber(inputs.feedwaterFlow, plant.params.loop.massFlowRate * 0.55)
	state.feedwaterFlow = baseFeedwater * (1 + feedwaterAdjustment)
end

local function updateCoolant(state, params, dt)
	dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
	local loop = Utils.deepCopy(params.loop)
	loop.massFlowRate = state.coolant.massFlow
	local outletTemp, deltaT = ThermalHydraulics.heatRemoval(state.core.power, state.coolant.inletTemp, loop)
	state.coolant.outletTemp = outletTemp
	state.coolant.inletTemp = state.coolant.inletTemp + (outletTemp - state.coolant.inletTemp) * dt * 0.1

	local flowRatio = state.coolant.massFlow / params.loop.massFlowRate
	state.coolant.pressure = params.loop.primaryPressure - ThermalHydraulics.pressureDrop(state.coolant.massFlow, loop) * 1e-6
	state.coolant.level = Utils.clamp(state.coolant.level + (0.98 - state.coolant.level) * dt * 0.05, 0.7, 1.05)
	state.coolant.flowRatio = flowRatio

	return deltaT, flowRatio
end

local function updatePump(state, params, dt, inputs)
	inputs = Utils.ensureTable(inputs)
	dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
	local ratedTorque = ThermalHydraulics.pumpTorque(3600, params.loop)
	local torqueFactor = Utils.coerceNumber(inputs.pumpTorqueFactor, 1.0)
	local commandedTorque = ratedTorque * torqueFactor
	state.pump = ThermalHydraulics.updatePumpState(state.pump, dt, commandedTorque, params.loop)
	local speedRatio = state.pump.speed / 3600
	state.coolant.massFlow = params.loop.massFlowRate * Utils.clamp(speedRatio, 0.4, 1.2)
end

local function updateCore(state, params, dt)
	local coolantTempAvg = 0.5 * (state.coolant.inletTemp + state.coolant.outletTemp)
	local fuelTemp = ThermalStructures.hotSpotTemperature(state.core.power, coolantTempAvg, params.fuelRod)
	local thermalMargin = SafetySystems.temperatureMargin(fuelTemp, 2250)
	state.safety.temperatureMargin = thermalMargin

	local boronWorth, corepH = CoolantChemistry.boronWorth(state.control.boronPpm, coolantTempAvg)
	local coolantInputs = {
		coolantTemp = coolantTempAvg,
		fuelTemp = fuelTemp,
		controlRodInsertion = state.control.controlRodInsertion,
		externalReactivity = boronWorth,
	}

	state.core = CoreKinetics.step(state.core, dt, coolantInputs, params.core)
	state.fuelTemperature = fuelTemp
	state.coolant.pH = corepH
	return thermalMargin
end

local function updateSecondary(state, params, dt, inputs)
	inputs = Utils.ensureTable(inputs)
	dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
	local feedwaterTemp = Utils.coerceNumber(inputs.feedwaterTemperature, params.feedwaterTemperature)
	local steam = TurbineGenerator.steamConditions(feedwaterTemp, params.steamPressure, state.feedwaterFlow)
	local condenserPressure = Utils.coerceNumber(inputs.condenserPressure, 8.0e3)
	local turbinePower = TurbineGenerator.turbinePower(steam, condenserPressure)
	local electricalDemand = Utils.coerceNumber(inputs.electricalDemand, params.electricalLoad)
	local generator = TurbineGenerator.generatorOutput(turbinePower, electricalDemand)
	local omega = state.turbine.speed * 2 * math.pi / 60
	local torqueInput = turbinePower / math.max(omega, 1e-3)
	local loadTorque = generator.electrical / math.max(omega, 1e-3)
	state.turbine = TurbineGenerator.updateRotor(state.turbine, dt, torqueInput, loadTorque)
	state.electrical = generator.electrical
	state.gridMismatch = generator.loadMismatch
	state.steam = steam
	state.steamPressure = params.steamPressure + generator.loadMismatch * 1e-5
end

local function updatePressurizer(state, params, dt)
	local pressure = state.pressurizer.pressure
	local heaterEffect = 3.8e6 * state.pressurizer.heaterFraction
	local sprayEffect = -4.2e6 * state.pressurizer.sprayValve
	local levelEffect = (state.coolant.level - 1.0) * 2.5e6
	local dp = (heaterEffect + sprayEffect + levelEffect) * 1e-8
	state.pressurizer.pressure = pressure + dp * dt
	state.coolant.pressure = state.pressurizer.pressure
end

local function updateSafety(state, params)
	local loop = params.loop
	local heatFlux = state.core.power / loop.fuelArea
	local critical = ThermalHydraulics.criticalHeatFlux(loop.primaryPressure, state.coolant.massFlow / loop.fuelArea)
	state.safety.dnbr = SafetySystems.dnbr(heatFlux, critical)
	state.safety.containmentPressure = SafetySystems.containmentPressureRise(0.01 * state.core.power, 8000, state.coolant.outletTemp)
	state.safety.pressurizerMargin = (state.pressurizer.pressure - params.pressurizerPressure) / params.pressurizerPressure
	state.safety.scram, state.safety.scramReasons = ControlSystems.scramLogic(
		state.core.power / params.core.referencePower,
		state.core.reactivity,
		state.coolant.level,
		{
			powerLimit = 1.2,
			reactivityLimit = params.core.betaEffective * 0.9,
		}
	)
end

function Simulation.stepPlant(plant, dt, inputs)
	if type(plant) ~= "table" or type(plant.state) ~= "table" or type(plant.params) ~= "table" then
		error("[Simulation.stepPlant] Plant is not initialised. Use Simulation.newPlant first.")
	end

	local state = plant.state
	local params = plant.params
	inputs = Utils.ensureTable(inputs)
	dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)

	updatePump(state, params, dt, inputs)
	local deltaT = select(1, updateCoolant(state, params, dt))
	local thermalMargin = updateCore(state, params, dt)

	applyControl(plant, dt, inputs)
	updatePressurizer(state, params, dt)
	updateSecondary(state, params, dt, inputs)
	updateSafety(state, params)

	state.time = state.time + dt
	state.coolant.deltaT = deltaT
	state.thermalMargin = thermalMargin

	return Utils.deepCopy(state)
end

function Simulation.runSeries(plant, steps, dt, stimulusFn)
	if type(steps) ~= "number" or steps <= 0 then
		error("[Simulation.runSeries] steps must be a positive integer")
	end
	dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)

	local history = {}
	for i = 1, steps do
		local inputs
		if stimulusFn then
			local ok, result = pcall(stimulusFn, i, plant.state.time)
			if ok then
				inputs = result
			else
				warn("[Simulation.runSeries] stimulusFn error at step " .. i .. ": " .. tostring(result))
			end
		end
		local snapshot = Simulation.stepPlant(plant, dt, inputs)
		history[i] = snapshot
	end
	return history
end

return Simulation



