local Constants = {}

Constants.Avogadro = 6.02214076e23 -- 1/mol
Constants.Boltzmann = 1.380649e-23 -- J/K
Constants.GasConstant = 8.314462618 -- J/(mol*K)
Constants.NeutronMass = 1.67492749804e-27 -- kg
Constants.ElementaryCharge = 1.602176634e-19 -- C
Constants.StefanBoltzmann = 5.670374419e-8 -- W/(m^2*K^4)
Constants.Gravity = 9.80665 -- m/s^2
Constants.WaterDensity = 997 -- kg/m^3 at approximately 25C
Constants.WaterThermalConductivity = 0.58 -- W/(m*K) at approximately 25C
Constants.WaterSpecificHeat = 4181.3 -- J/(kg*K)
Constants.U235MicroscopicFissionXS = 585e-28 -- m^2 (585 barns)
Constants.NeutronGenerationTime = 1.0e-5 -- s, prompt neutron lifetime
Constants.DelayedNeutronFraction = 0.0065 -- beta_eff typical PWR
Constants.DecayConstants = {0.0127, 0.0317, 0.115, 0.311, 1.4, 3.87} -- 1/s delayed neutron groups
Constants.DelayedGroupFractions = {0.000266, 0.001491, 0.001316, 0.002849, 0.000896, 0.000507}
Constants.FuelHeatCapacity = 270 -- J/(kg*K) UO2 approx
Constants.FuelDensity = 10970 -- kg/m^3 UO2
Constants.CladdingConductivity = 16.0 -- W/(m*K) Zircaloy
Constants.CladdingThickness = 0.00057 -- m
Constants.FuelThermalConductivity = 2.8 -- W/(m*K) UO2 at high temp
Constants.ReferenceTemperature = 565.0 -- K typical reactor operating temp
Constants.TemperatureFeedbackCoeff = -4.5e-5 -- delta-rho/degC
Constants.PowerCoefficient = -2.0e-7 -- delta-rho/W
Constants.CoolantBoilingPoint = 620.0 -- K at ~155 bar
Constants.CoolantPressure = 15.5e6 -- Pa typical PWR
Constants.PumpInertia = 12.5 -- kg*m^2 hypothetical
Constants.PumpDamping = 3.25 -- N*m*s

return Constants



