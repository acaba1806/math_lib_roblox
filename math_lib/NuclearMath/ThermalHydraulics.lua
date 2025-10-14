local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)

local ThermalHydraulics = {}

function ThermalHydraulics.defaultLoop()
	return {
		massFlowRate = 16800, -- kg/s loop
		primaryVolume = 110.0, -- m^3
		heatTransferArea = 6500, -- m^2 steam generator
		primaryPressure = Constants.CoolantPressure,
		pumpHead = 6.5e6, -- Pa
		coreHeight = 4.0, -- m
		fuelArea = 450.0, -- m^2
		hotLegLength = 20.0,
		coldLegLength = 25.0,
		hydraulicDiameter = 0.5,
		frictionFactor = 0.018,
	}
end

local function reynoldsNumber(massFlowRate, hydraulicDiameter, area, viscosity)
	local velocity = massFlowRate / (Constants.WaterDensity * area)
	return Constants.WaterDensity * velocity * hydraulicDiameter / viscosity
end

function ThermalHydraulics.heatRemoval(power, inletTemp, loop)
	loop = loop or ThermalHydraulics.defaultLoop()
	local cp = Constants.WaterSpecificHeat
	local massFlow = math.max(Utils.coerceNumber(loop.massFlowRate, ThermalHydraulics.defaultLoop().massFlowRate), 1.0)
	local powerSafe = Utils.coerceNumber(power, 0.0)
	local inletSafe = Utils.coerceNumber(inletTemp, Constants.ReferenceTemperature or 565.0)
	local deltaT = powerSafe / (massFlow * cp)
	local outletTemp = inletSafe + deltaT
	return outletTemp, deltaT
end

function ThermalHydraulics.logMeanTempDiff(T_hot_in, T_hot_out, T_cold_in, T_cold_out)
	local delta1 = T_hot_in - T_cold_out
	local delta2 = T_hot_out - T_cold_in
	if math.abs(delta1 - delta2) < 1e-6 then
		return delta1
	end
	return (delta1 - delta2) / math.log(delta1 / delta2)
end

function ThermalHydraulics.steamGenerator(power, primaryInlet, secondaryInlet, loop)
	loop = loop or ThermalHydraulics.defaultLoop()
	local U = 4800 -- W/(m^2*K)
	local area = math.max(Utils.coerceNumber(loop.heatTransferArea, 1.0), 1.0)
	local massFlow = math.max(Utils.coerceNumber(loop.massFlowRate, ThermalHydraulics.defaultLoop().massFlowRate), 1.0)
	local safePower = Utils.coerceNumber(power, 0.0)
	local primaryHotIn = Utils.coerceNumber(primaryInlet, Constants.ReferenceTemperature or 565.0)
	local secondaryColdIn = Utils.coerceNumber(secondaryInlet, 480.0)
	local T_hot_out = primaryHotIn - safePower / (massFlow * Constants.WaterSpecificHeat)
	local secondaryOutlet = secondaryColdIn + 20
	local LMTD = ThermalHydraulics.logMeanTempDiff(primaryHotIn, T_hot_out, secondaryColdIn, secondaryOutlet)
	local qMax = math.max(U * area * math.max(LMTD, 1.0), 1.0)
	local effectiveness = Utils.clamp(safePower / qMax, 0.0, 1.0)
	local actualPower = effectiveness * qMax
	local primaryOutlet = primaryHotIn - actualPower / (massFlow * Constants.WaterSpecificHeat)
	return {
		primaryOutlet = primaryOutlet,
		heatRemoved = actualPower,
		effectiveness = effectiveness,
	}
end

function ThermalHydraulics.pressureDrop(massFlowRate, loop)
	loop = loop or ThermalHydraulics.defaultLoop()
	local density = Constants.WaterDensity
	local diameter = math.max(Utils.coerceNumber(loop.hydraulicDiameter, 0.5), 0.05)
	local area = math.pi * (diameter / 2) ^ 2
	local flow = math.max(Utils.coerceNumber(massFlowRate, loop.massFlowRate or ThermalHydraulics.defaultLoop().massFlowRate), 0.0)
	local velocity = flow / math.max(density * area, 1e-3)
	local totalLength = math.max(Utils.coerceNumber(loop.hotLegLength, 20.0) + Utils.coerceNumber(loop.coldLegLength, 25.0) + Utils.coerceNumber(loop.coreHeight, 4.0), 1.0)
	local frictionFactor = Utils.coerceNumber(loop.frictionFactor, 0.018)
	local friction = frictionFactor * (totalLength / diameter) * 0.5 * density * velocity ^ 2
	local static = density * Constants.Gravity * math.max(Utils.coerceNumber(loop.coreHeight, 4.0), 0.0)
	return friction + static
end

function ThermalHydraulics.pumpTorque(speed, loop)
	loop = loop or ThermalHydraulics.defaultLoop()
	local ratedSpeed = 3600 -- RPM synch
	local speedSafe = math.max(Utils.coerceNumber(speed, ratedSpeed), 0.0)
	local relativeSpeed = speedSafe / ratedSpeed
	local head = Utils.coerceNumber(loop.pumpHead, ThermalHydraulics.defaultLoop().pumpHead) * relativeSpeed ^ 2
	local flow = Utils.coerceNumber(loop.massFlowRate, ThermalHydraulics.defaultLoop().massFlowRate) * relativeSpeed
	local hydraulicPower = head * flow / math.max(Constants.WaterDensity, 1.0)
	local omega = speed * 2 * math.pi / 60
	return hydraulicPower / math.max(omega, 1e-3)
end

function ThermalHydraulics.updatePumpState(state, dt, torqueInput, loop)
	loop = loop or ThermalHydraulics.defaultLoop()
	state = state or { speed = 3600, torque = 0.0 }
	dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
	state.speed = Utils.coerceNumber(state.speed, 3600)
	state.torque = Utils.coerceNumber(state.torque, 0.0)
	local inertia = Constants.PumpInertia
	local damping = Constants.PumpDamping
	local hydraulicTorque = ThermalHydraulics.pumpTorque(state.speed, loop)
	local commanded = Utils.coerceNumber(torqueInput, hydraulicTorque)
	local acceleration = (commanded - hydraulicTorque - damping * state.speed) / inertia
	local nextSpeed = math.max(state.speed + acceleration * dt, 0.0)
	return {
		speed = nextSpeed,
		torque = commanded,
	}
end

function ThermalHydraulics.twoPhaseVoidFraction(quality, slipRatio)
	slipRatio = slipRatio or 1.1
	if quality <= 0 then
		return 0.0
	elseif quality >= 1 then
		return 1.0
	end
	return 1 / (1 + (1 - quality) / (quality * slipRatio))
end

function ThermalHydraulics.density(temperature, pressure)
	local beta = 3.5e-4
	temperature = Utils.coerceNumber(temperature, Constants.ReferenceTemperature or 565.0)
	pressure = math.max(Utils.coerceNumber(pressure, Constants.CoolantPressure), 1.0)
	return math.max(Constants.WaterDensity * (1 - beta * (temperature - 298.15)) * (pressure / Constants.CoolantPressure), 1.0)
end

function ThermalHydraulics.criticalHeatFlux(pressure, massFlux)
	pressure = math.max(Utils.coerceNumber(pressure, Constants.CoolantPressure), 1.0)
	massFlux = math.max(Utils.coerceNumber(massFlux, 3500), 1.0) -- kg/(m^2*s)
	local A = 1.5e6
	local B = 0.2
	return A * (pressure / Constants.CoolantPressure) ^ 0.5 * (massFlux / 3500) ^ B
end

function ThermalHydraulics.subcooling(temperature, pressure)
	temperature = Utils.coerceNumber(temperature, Constants.ReferenceTemperature or 565.0)
	local saturation = Constants.CoolantBoilingPoint * (math.max(Utils.coerceNumber(pressure, Constants.CoolantPressure), 1.0) / Constants.CoolantPressure) ^ 0.12
	return saturation - temperature
end

function ThermalHydraulics.flowImbalance(primaryFlow, secondaryFlow)
	primaryFlow = math.max(Utils.coerceNumber(primaryFlow, ThermalHydraulics.defaultLoop().massFlowRate), 1.0)
	secondaryFlow = Utils.coerceNumber(secondaryFlow, primaryFlow)
	local relative = (primaryFlow - secondaryFlow) / math.max(primaryFlow, 1e-3)
	return {
		relative = relative,
		severity = Utils.clamp(math.abs(relative) * 5, 0.0, 1.0),
	}
end

return ThermalHydraulics



