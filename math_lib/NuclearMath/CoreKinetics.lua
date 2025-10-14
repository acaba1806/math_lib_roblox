-- Module: CoreKinetics
-- Description: Defines core functionality for NuclearMath (CoreKinetics component)-- Copyright 2025 Terranova Incorporated
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
-- an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations under the License.
local Constants = require(script.Parent.Constants)
local Utils = require(script.Parent.Utils)

local arrayUnpack = table.unpack or unpack

local CoreKinetics = {}

function CoreKinetics.defaultParameters()
	local delayedFractions = Constants.DelayedGroupFractions or {}
	local decayConstants = Constants.DecayConstants or {}
	local size = math.min(#delayedFractions, #decayConstants)
	return {
		betaEffective = Constants.DelayedNeutronFraction,
		promptLifetime = Constants.NeutronGenerationTime,
		delayedFractions = { arrayUnpack(delayedFractions, 1, size) },
		decayConstants = { arrayUnpack(decayConstants, 1, size) },
		referencePower = 3000e6, -- 3000 MW thermal
		referenceFuelTemp = Constants.ReferenceTemperature or 565.0,
		referenceCoolantTemp = (Constants.ReferenceTemperature or 565.0) - 30,
		tempFeedbackCoeff = Constants.TemperatureFeedbackCoeff,
		powerFeedbackCoeff = Constants.PowerCoefficient,
		xenonFeedbackCoeff = -2.7e-3,
		samariumFeedbackCoeff = -7.0e-4,
		controlRodWorth = 0.009,
	}
end

local function ensureVector(input)
	if type(input) ~= "table" then
		return {}
	end
	local vector = {}
	for i = 1, #input do
		vector[i] = Utils.coerceNumber(input[i], 0.0)
	end
	return vector
end

local function sanitizeParams(params)
	if type(params) ~= "table" then
		return CoreKinetics.defaultParameters()
	end

	local defaults = CoreKinetics.defaultParameters()
	params.delayedFractions = params.delayedFractions or defaults.delayedFractions
	params.decayConstants = params.decayConstants or defaults.decayConstants

	local size = math.min(#params.delayedFractions, #params.decayConstants)
	if size == 0 then
		params.delayedFractions = defaults.delayedFractions
		params.decayConstants = defaults.decayConstants
		size = #defaults.delayedFractions
	end

	params.betaEffective = Utils.coerceNumber(params.betaEffective, defaults.betaEffective)
	params.promptLifetime = Utils.coerceNumber(params.promptLifetime, defaults.promptLifetime)
	params.referencePower = Utils.coerceNumber(params.referencePower, defaults.referencePower)
	params.referenceFuelTemp = Utils.coerceNumber(params.referenceFuelTemp, defaults.referenceFuelTemp)
	params.referenceCoolantTemp = Utils.coerceNumber(params.referenceCoolantTemp, defaults.referenceCoolantTemp)
	params.tempFeedbackCoeff = Utils.coerceNumber(params.tempFeedbackCoeff, defaults.tempFeedbackCoeff)
	params.powerFeedbackCoeff = Utils.coerceNumber(params.powerFeedbackCoeff, defaults.powerFeedbackCoeff)
	params.xenonFeedbackCoeff = Utils.coerceNumber(params.xenonFeedbackCoeff, defaults.xenonFeedbackCoeff)
	params.samariumFeedbackCoeff = Utils.coerceNumber(params.samariumFeedbackCoeff, defaults.samariumFeedbackCoeff)
	params.controlRodWorth = Utils.coerceNumber(params.controlRodWorth, defaults.controlRodWorth)

	params.delayedFractions = { arrayUnpack(params.delayedFractions, 1, size) }
	params.decayConstants = { arrayUnpack(params.decayConstants, 1, size) }

	return params
end

function CoreKinetics.initialState(params)
	params = sanitizeParams(params)
	local delayed = {}
	for i = 1, #params.delayedFractions do
		delayed[i] = params.referencePower * params.delayedFractions[i] / params.decayConstants[i]
	end
	return {
		power = params.referencePower,
		delayedNeutrons = delayed,
		reactivity = 0.0,
		xenon = 0.0,
		samarium = 0.0,
	}
end

function CoreKinetics.calculateReactivity(power, fuelTemp, coolantTemp, controlRodInsertion, params, overrides)
	params = sanitizeParams(params)
	local beta = params.betaEffective
	power = Utils.coerceNumber(power, params.referencePower)
	fuelTemp = Utils.coerceNumber(fuelTemp, params.referenceFuelTemp)
	coolantTemp = Utils.coerceNumber(coolantTemp, params.referenceCoolantTemp)
	controlRodInsertion = Utils.clamp(Utils.coerceNumber(controlRodInsertion, 0.0), 0.0, 1.0)

	local rhoTemp = params.tempFeedbackCoeff * (fuelTemp - params.referenceFuelTemp)
	local rhoCoolant = 0.4 * params.tempFeedbackCoeff * (coolantTemp - params.referenceCoolantTemp)
	local rhoPower = params.powerFeedbackCoeff * (power - params.referencePower)
	local rhoRod = -params.controlRodWorth * controlRodInsertion
	local overrideRho = overrides and overrides.additionalReactivity or 0.0
	local xenon = overrides and overrides.xenon or 0.0
	local samarium = overrides and overrides.samarium or 0.0
	local rhoXenon = params.xenonFeedbackCoeff * xenon
	local rhoSamarium = params.samariumFeedbackCoeff * samarium
	local totalRho = rhoTemp + rhoCoolant + rhoPower + rhoRod + rhoXenon + rhoSamarium + overrideRho

	return Utils.clamp(totalRho, -2.0 * beta, 1.5 * beta)
end

function CoreKinetics.derivatives(state, inputs, params)
	params = sanitizeParams(params)
	if type(state) ~= "table" then
		warn("[CoreKinetics.derivatives] State must be a table")
		state = CoreKinetics.initialState(params)
	end

	inputs = Utils.ensureTable(inputs)

	local beta = params.betaEffective
	local fractions = params.delayedFractions
	local lambdas = params.decayConstants
	local promptLifetime = params.promptLifetime

	local power = state.power
	local delayed = ensureVector(state.delayedNeutrons)
	local reactivity = state.reactivity
	local xenon = state.xenon or 0.0
	local samarium = state.samarium or 0.0

	local coolantTemp = inputs.coolantTemp or params.referenceCoolantTemp
	local fuelTemp = inputs.fuelTemp or params.referenceFuelTemp
	local controlRodInsertion = Utils.clamp(inputs.controlRodInsertion or 0.0, 0.0, 1.0)
	local externalReactivity = inputs.externalReactivity or 0.0

	if #delayed ~= #fractions then
		warn("[CoreKinetics.derivatives] Delayed neutron population count mismatch, reinitialising vector")
		delayed = CoreKinetics.initialState(params).delayedNeutrons
	end

	local rho = CoreKinetics.calculateReactivity(power, fuelTemp, coolantTemp, controlRodInsertion, params, {
		additionalReactivity = externalReactivity,
		xenon = xenon,
		samarium = samarium,
	})

	local dPower = ((rho - beta) / promptLifetime) * power
	for i = 1, #delayed do
		dPower = dPower + lambdas[i] * delayed[i]
	end

	local dDelayed = {}
	for i = 1, #delayed do
		dDelayed[i] = fractions[i] * power / promptLifetime - lambdas[i] * delayed[i]
	end

	local iodineYield = 0.063 -- atoms per fission
	local xenonYield = 0.003
	local sigmaF = 2.6e-24 -- m^2 effective absorption macro XS
	local neutronFlux = power / params.referencePower * 1.0e14

	local dXenon = iodineYield * power - (sigmaF * neutronFlux + 2.1e-5) * xenon + xenonYield * power
	local dSamarium = 0.0006 * power - 8.0e-6 * samarium

	return {
		dPower = dPower,
		dDelayedNeutrons = dDelayed,
		dReactivity = (rho - reactivity) * 2.0, -- first-order lag to avoid stiffness
		dXenon = dXenon,
		dSamarium = dSamarium,
	}
end

function CoreKinetics.step(state, dt, inputs, params)
	params = sanitizeParams(params)
	state = state or CoreKinetics.initialState(params)
	inputs = Utils.ensureTable(inputs)

	local function derivative(vectorState)
		return CoreKinetics.derivatives(vectorState, inputs, params)
	end

	local function toVector(vectorState)
		local output = {}
		output[1] = vectorState.power
		for i = 1, #vectorState.delayedNeutrons do
			output[i + 1] = vectorState.delayedNeutrons[i]
		end
		output[#vectorState.delayedNeutrons + 2] = vectorState.reactivity
		output[#vectorState.delayedNeutrons + 3] = vectorState.xenon
		output[#vectorState.delayedNeutrons + 4] = vectorState.samarium
		return output
	end

	local function fromVector(vector)
		local result = {}
		result.power = vector[1]
		result.delayedNeutrons = {}
		for i = 1, #params.delayedFractions do
			result.delayedNeutrons[i] = vector[i + 1]
		end
		result.reactivity = vector[#params.delayedFractions + 2]
		result.xenon = vector[#params.delayedFractions + 3]
		result.samarium = vector[#params.delayedFractions + 4]
		return result
	end

	local function derivativeVector(vector)
		local structured = fromVector(vector)
		local derivatives = derivative(structured)
		local output = {}
		output[1] = derivatives.dPower
		for i = 1, #derivatives.dDelayedNeutrons do
			output[i + 1] = derivatives.dDelayedNeutrons[i]
		end
		output[#derivatives.dDelayedNeutrons + 2] = derivatives.dReactivity
		output[#derivatives.dDelayedNeutrons + 3] = derivatives.dXenon
		output[#derivatives.dDelayedNeutrons + 4] = derivatives.dSamarium
		return output
	end

	local initialVector = toVector(state)
	local rkResult = Utils.rungeKutta4(initialVector, dt, derivativeVector)
	local updated = fromVector(rkResult)

	updated.reactivity = CoreKinetics.calculateReactivity(
		updated.power,
		inputs.fuelTemp or params.referenceFuelTemp,
		inputs.coolantTemp or params.referenceCoolantTemp,
		Utils.clamp(inputs.controlRodInsertion or 0.0, 0.0, 1.0),
		params,
		{
			additionalReactivity = inputs.externalReactivity or 0.0,
			xenon = updated.xenon,
			samarium = updated.samarium,
		}
	)

	return updated
end

return CoreKinetics


