local Utils = require(script.Parent.Utils)

local ControlSystems = {}

function ControlSystems.pidController(gains)
	gains = Utils.ensureTable(gains)
	gains.kp = Utils.coerceNumber(gains.kp, 0.0)
	gains.ki = Utils.coerceNumber(gains.ki, 0.0)
	gains.kd = Utils.coerceNumber(gains.kd, 0.0)
	gains.integralClamp = math.abs(Utils.coerceNumber(gains.integralClamp, 1.0))

	local state = {
		integral = 0.0,
		previousError = 0.0,
	}

	return function(setpoint, measurement, dt)
		setpoint = Utils.coerceNumber(setpoint, 0.0)
		measurement = Utils.coerceNumber(measurement, 0.0)
		dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)

		local error = setpoint - measurement
		local nextIntegral = state.integral + error * dt
		if math.abs(nextIntegral) > gains.integralClamp then
			nextIntegral = Utils.clamp(nextIntegral, -gains.integralClamp, gains.integralClamp)
		end
		state.integral = nextIntegral

		state.integral = Utils.clamp(state.integral, -gains.integralClamp, gains.integralClamp)
		local derivative = (error - state.previousError) / math.max(dt, 1e-6)
		state.previousError = error
		return gains.kp * error + gains.ki * state.integral + gains.kd * derivative
	end
end

function ControlSystems.reactivityController(targetPower, params)
	params = params or {}
	local gains = {
		kp = Utils.coerceNumber(params.kp, -3.5e-5),
		ki = Utils.coerceNumber(params.ki, -1.2e-6),
		kd = Utils.coerceNumber(params.kd, -1.8e-5),
		integralClamp = math.abs(Utils.coerceNumber(params.integralClamp, 200.0)),
	}
	local pid = ControlSystems.pidController(gains)

	return function(actualPower, dt, thermalMargin)
		thermalMargin = thermalMargin or 1.0
		actualPower = Utils.coerceNumber(actualPower, targetPower)
		dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
		thermalMargin = Utils.clamp(Utils.coerceNumber(thermalMargin, 1.0), 0.1, 2.0)
		local output = pid(targetPower, actualPower, dt)
		local insertion = Utils.clamp(output * thermalMargin, -0.2, 0.2)
		return insertion
	end
end

function ControlSystems.feedwaterController(targetSteamPressure)
	targetSteamPressure = Utils.coerceNumber(targetSteamPressure, 6.0e6)
	local gains = {
		kp = 2.5e-3,
		ki = 4.0e-4,
		kd = 1.0e-4,
		integralClamp = 10.0,
	}
	local pid = ControlSystems.pidController(gains)
	return function(actualPressure, dt)
		actualPressure = Utils.coerceNumber(actualPressure, targetSteamPressure)
		dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
		local control = pid(targetSteamPressure, actualPressure, dt)
		return Utils.clamp(control, -0.2, 0.2)
	end
end

function ControlSystems.temperatureCompensation(fuelTemp, coolantTemp)
	local delta = fuelTemp - coolantTemp
	if delta > 50 then
		return 0.9
	elseif delta < 20 then
		return 1.1
	end
	return 1.0
end

function ControlSystems.scramLogic(power, reactivity, coolantLevel, params)
	params = params or {}
	local powerLimit = params.powerLimit or 1.15
	local rhoLimit = params.reactivityLimit or 0.007
	local levelLimit = params.coolantLevelLimit or 0.85

	power = Utils.coerceNumber(power, 0.0)
	reactivity = Utils.coerceNumber(reactivity, 0.0)
	coolantLevel = Utils.coerceNumber(coolantLevel, 1.0)

	local scram = false
	local reason = {}

	if power > powerLimit then
		scram = true
		table.insert(reason, "Power excursion beyond limit")
	end
	if math.abs(reactivity) > rhoLimit then
		scram = true
		table.insert(reason, "Reactivity outside safe band")
	end
	if coolantLevel < levelLimit then
		scram = true
		table.insert(reason, "Coolant level below threshold")
	end

	return scram, reason
end

function ControlSystems.differentialBoronControl(targetReactivity)
	local currentBoron = 1500 -- ppm
	return function(reactivity, dt)
		reactivity = Utils.coerceNumber(reactivity, targetReactivity)
		dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
		local error = reactivity - targetReactivity
		currentBoron = currentBoron + error * dt * 5.0
		currentBoron = Utils.clamp(currentBoron, 500, 2500)
		return currentBoron
	end
end

function ControlSystems.axialOffsetControl(targetAO)
	local gains = {
		kp = -0.8,
		ki = -0.02,
		kd = -0.05,
		integralClamp = 10,
	}
	local pid = ControlSystems.pidController(gains)
	return function(actualAO, dt)
		actualAO = Utils.coerceNumber(actualAO, targetAO)
		dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
		local adjustment = pid(targetAO, actualAO, dt)
		return Utils.clamp(adjustment, -0.1, 0.1)
	end
end

function ControlSystems.pressurizerSprayControl(targetPressure)
	targetPressure = Utils.coerceNumber(targetPressure, 15.5e6)
	local gains = {
		kp = 3.0e-6,
		ki = 2.5e-7,
		kd = 1.1e-6,
		integralClamp = 5.0,
	}
	local pid = ControlSystems.pidController(gains)
	return function(actualPressure, dt)
		actualPressure = Utils.coerceNumber(actualPressure, targetPressure)
		dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
		local sprayValve = pid(targetPressure, actualPressure, dt)
		return Utils.clamp(sprayValve, 0.0, 1.0)
	end
end

function ControlSystems.pressurizerHeaterControl(targetPressure)
	targetPressure = Utils.coerceNumber(targetPressure, 15.5e6)
	local gains = {
		kp = 1.4e-6,
		ki = 5.0e-8,
		kd = 1.3e-6,
		integralClamp = 5.0,
	}
	local pid = ControlSystems.pidController(gains)
	return function(actualPressure, dt)
		actualPressure = Utils.coerceNumber(actualPressure, targetPressure)
		dt = math.max(Utils.coerceNumber(dt, 0.0), 1e-3)
		local heaterFraction = pid(targetPressure, actualPressure, dt)
		return Utils.clamp(heaterFraction, 0.0, 1.0)
	end
end

return ControlSystems



