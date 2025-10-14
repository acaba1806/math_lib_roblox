# NuclearMath Library for Roblox Studio

`math_lib/NuclearMath` provides a modular, math-heavy toolkit for simulating a pressurised water reactor (PWR) inside Roblox Studio. The package is designed for educational and serious-simulation experiences where thermal hydraulics, point kinetics, plant control, and safety margins must respond realistically to player input or scripted disturbances.

The codebase runs entirely in Roblox Lua and emphasises numerical stability: every public function validates inputs, clamps unsafe values, and propagates warnings through Roblox's `warn()` facility so that misconfiguration does not crash the experience.

## Module catalogue

- `NuclearMath.Constants` - canonical physical constants and reference design numbers (all SI units).
- `NuclearMath.Utils` - reusable numerical helpers (Runge-Kutta 4 integrator with guarded execution, vector math, clamps, deep copies, sanitisation helpers).
- `NuclearMath.CoreKinetics` - six-group point kinetics with prompt/delayed neutrons, temperature and power feedback, xenon/samarium poisoning, and control rod worth modelling.
- `NuclearMath.ThermalHydraulics` - primary-loop calculations: heat balance, pressure drop, pump dynamics, steam-generator effectiveness, density correlations, and void fractions.
- `NuclearMath.ThermalStructures` - fuel rod thermal response: radial conductance, hotspot estimation, axial profile synthesis, and simplified burnup accounting.
- `NuclearMath.ControlSystems` - configurable PID controllers for reactivity, feedwater, pressuriser spray/heaters, boron concentration, and axial offset, plus SCRAM decision logic.
- `NuclearMath.TurbineGenerator` - steam conditions, turbine power conversion, generator electrical output, and rotor inertia response.
- `NuclearMath.CoolantChemistry` - coolant pH, boron worth, lithium balance, corrosion rate, and activity coefficient estimates with temperature-aware clamping.
- `NuclearMath.SafetySystems` - DNBR, containment pressure rise, ECCS quench metrics, probabilistic failure estimates, radiation dose, and operating state classification.
- `NuclearMath.Simulation` - orchestrates all submodules, maintains plant state, executes time-stepped integration, and exposes helpers for scripted scenarios.

## Installation in Roblox Studio

1. In Studio, create a folder (for example `ReplicatedStorage/math_lib`).
2. Add a child folder named `NuclearMath`.
3. For each Lua file under `math_lib/NuclearMath` in this repo, create a ModuleScript with the same name and paste the contents.
4. Create one ModuleScript named `init` inside `NuclearMath` and paste `math_lib/NuclearMath/init.lua`.
5. Require the package from your systems using:
   ```lua
   local NuclearMath = require(ReplicatedStorage.math_lib.NuclearMath)
   ```

## Quick start: stepping the plant

```lua
local NuclearMath = require(ReplicatedStorage.math_lib.NuclearMath)
local plant = NuclearMath.Simulation.newPlant()
local dt = 0.05 -- 50 ms per step

for tick = 1, 2000 do
	local snapshot = NuclearMath.Simulation.stepPlant(plant, dt, {
		electricalDemand = 950e6,
		feedwaterTemperature = 500.0,
	})

	if snapshot.safety.scram then
		warn(("SCRAM triggered: %s"):format(table.concat(snapshot.safety.scramReasons, ", ")))
		break
	end
end
```

Each call to `Simulation.stepPlant`:

1. Validates the plant object and clamps the timestep.
2. Propagates control inputs (pump torque, feedwater commands, rod overrides).
3. Integrates core kinetics (Runge-Kutta), thermal hydraulics, and turbine dynamics.
4. Updates chemistry, pressuriser behaviour, and safety metrics.
5. Returns a deep-copied snapshot so you can store history without mutating the live state.

If any callback or derivative throws an error, the library catches it, emits a warning with context, and continues using the last stable state.

## Controlling the simulation loop

- **Stimulus functions**: `Simulation.runSeries(plant, steps, dt, stimulusFn)` invokes `stimulusFn(stepIndex, timeSeconds)` before each advance. Throwing inside the callback does not break the run; the warning identifies the offending step.
- **Direct module access**: The modules are independent. You can call `CoreKinetics.step`, `ThermalHydraulics.heatRemoval`, or `SafetySystems.eventClassification` in isolation for analysis or UI feedback.
- **Parameter customisation**: Pass a partial table into `Simulation.newPlant({ ... })`. Only supplied keys override defaults; every numeric field goes through range checks. Example:
  ```lua
  local customPlant = NuclearMath.Simulation.newPlant({
  	targetPower = 0.8, -- 80% rated
  	electricalLoad = 750e6,
  	core = {
  		controlRodWorth = 0.0075,
  	},
  	loop = {
  		massFlowRate = 15000,
  	},
  })
  ```

## Safety and robustness features

- **Input sanitisation**: Every public entry point coerces `nil`, `NaN`, and extreme values back to safe defaults. Negative flow rates, invalid rod insertions, and non-finite controller outputs are rejected.
- **Physical bounds**: Internal clamps prevent runaway reactivity, dry-out ratios below zero, or negative coolant levels. Values outside the plausible range saturate and generate a warning.
- **State guarding**: `Simulation.stepPlant` refuses to run on an uninitialised plant, guiding you to call `Simulation.newPlant` first.
- **Unit consistency**: All calculations use SI units. Temperatures are Kelvin, pressures in Pascal, energy in Joule, mass in kilogram, and power in Watt.
- **Non-blocking warnings**: Errors from user-supplied stimulus functions or derivative callbacks are reported via `warn()` without halting the simulation, helping you diagnose issues during development.

## Suggested development workflow

1. Assemble plant instrumentation GUIs that display fields from the returned snapshot (`snapshot.core.power`, `snapshot.coolant.deltaT`, `snapshot.safety.dnbr`, etc.).
2. Build scenario scripts that call `Simulation.runSeries` for automated transients (loss-of-flow, load rejections, feedwater failure).
3. Connect the control outputs (`snapshot.control.controlRodInsertion`, `snapshot.control.boronPpm`) to Roblox objects (e.g., servo animations, gauge readouts).
4. Record history in a `DataStore` or `MemoryStore` if you need post-mortem analysis of player actions.

## Troubleshooting checklist

- **Unresponsive plant**: Confirm the loop that calls `stepPlant` uses a positive `dt` (the library automatically clamps to at least 1 ms, but a zero timestep indicates logic bugs).
- **Frequent warnings**: Inspect the Roblox output for messages originating from `NuclearMath.Utils`. They usually highlight invalid controller gains or out-of-range stimulus values.
- **SCRAM trips**: Review `snapshot.safety.scramReasons` to see which threshold triggered the shutdown (power, reactivity, or coolant level).
- **Performance tuning**: Reduce `dt` for slower dynamics or increase it (within reason) for faster runs. Because the solver is explicit RK4, keep steps under 0.1 s for stability.

## Extending the library

- Add new chemistry effects by creating additional functions in `CoolantChemistry.lua` (reuse `Utils.coerceNumber` for sanitisation).
- Plug in alternative controller strategies by exposing new factories in `ControlSystems.lua` and referencing them inside `Simulation.createControllers`.
- Bolt on secondary-side detail (condensers, feedwater heaters) by expanding `TurbineGenerator.lua` and storing extra fields in the simulation state.

The project aims to stay modular: contribute new models by adding separate ModuleScripts and exporting them through `math_lib/NuclearMath/init.lua`.
