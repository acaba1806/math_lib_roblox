local Utils = {}

local function describeType(value)
	if typeof then
		local ok, result = pcall(typeof, value)
		if ok and result then
			return result
		end
	end
	return type(value)
end

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validateVector(vector, name)
	if type(vector) ~= "table" then
		warn(string.format("[Utils] Expected table vector for %s, got %s", name, describeType(vector)))
		return false
	end

	for index = 1, #vector do
		if not isFiniteNumber(vector[index]) then
			warn(string.format("[Utils] Non-finite component detected in %s at index %d", name, index))
			return false
		end
	end

	return true
end

-- Fourth-order Runge-Kutta integrator for systems of ODEs represented as vectors.
function Utils.rungeKutta4(state, dt, derivativeFn)
	if type(derivativeFn) ~= "function" then
		warn("[Utils.rungeKutta4] derivativeFn must be a function")
		return Utils.deepCopy(state)
	end

	if type(state) ~= "table" then
		warn("[Utils.rungeKutta4] state must be an array-like table")
		return Utils.deepCopy(state)
	end

	if not isFiniteNumber(dt) or dt <= 0 then
		warn("[Utils.rungeKutta4] dt must be a positive finite number")
		dt = math.max(dt or 0.0, 1e-3)
	end

	local function safeDerivative(input, label)
		local ok, result = pcall(derivativeFn, input)
		if not ok then
			warn(string.format("[Utils.rungeKutta4] Derivative function error during %s: %s", label, tostring(result)))
			return nil
		end
		if not validateVector(result, label) then
			return nil
		end
		if #result ~= #state then
			warn(string.format("[Utils.rungeKutta4] Derivative result length mismatch during %s (expected %d, got %d)", label, #state, #result))
			return nil
		end
		return result
	end

	local k1 = safeDerivative(state, "k1")
	if not k1 then
		return Utils.deepCopy(state)
	end

	local nextState = {}
	for i = 1, #state do
		nextState[i] = state[i] + 0.5 * dt * k1[i]
	end

	local k2 = safeDerivative(nextState, "k2")
	if not k2 then
		return Utils.deepCopy(state)
	end

	for i = 1, #state do
		nextState[i] = state[i] + 0.5 * dt * k2[i]
	end

	local k3 = safeDerivative(nextState, "k3")
	if not k3 then
		return Utils.deepCopy(state)
	end

	for i = 1, #state do
		nextState[i] = state[i] + dt * k3[i]
	end

	local k4 = safeDerivative(nextState, "k4")
	if not k4 then
		return Utils.deepCopy(state)
	end

	local output = {}
	for i = 1, #state do
		output[i] = state[i] + dt / 6.0 * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i])
	end

	return output
end

function Utils.clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	elseif value > maxValue then
		return maxValue
	end
	return value
end

function Utils.deepCopy(tbl)
	local copy = {}
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			copy[key] = Utils.deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

function Utils.vectorAdd(a, b)
	if not validateVector(a, "vectorAdd:a") or not validateVector(b, "vectorAdd:b") then
		return {}
	end
	if #a ~= #b then
		warn(string.format("[Utils.vectorAdd] Mismatched vector lengths (%d vs %d)", #a, #b))
		return {}
	end

	local result = {}
	for i = 1, #a do
		result[i] = a[i] + b[i]
	end
	return result
end

function Utils.vectorScale(a, scalar)
	if not validateVector(a, "vectorScale:a") then
		return {}
	end
	if not isFiniteNumber(scalar) then
		warn(string.format("[Utils.vectorScale] Scalar must be finite, got %s", tostring(scalar)))
		return {}
	end

	local result = {}
	for i = 1, #a do
		result[i] = a[i] * scalar
	end
	return result
end

-- Numerically integrate scalar function using trapezoidal rule.
function Utils.trapezoidalIntegral(y0, y1, dt)
	return 0.5 * (y0 + y1) * dt
end

function Utils.coerceNumber(value, defaultValue)
	if isFiniteNumber(value) then
		return value
	end
	return defaultValue
end

function Utils.isFiniteNumber(value)
	return isFiniteNumber(value)
end

function Utils.ensureTable(value)
	if type(value) == "table" then
		return value
	end
	return {}
end

return Utils



