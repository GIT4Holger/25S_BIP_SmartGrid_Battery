
close all; clear; clc;
years_operation=2;
%% load data
load('profiles.mat'); % profiles in kWh
 
steps_per_year=length(energy_generation);
steps=steps_per_year*years_operation;
%% scale and read profiles
peak_kW_generation=10; % PV peak Power in kWp
annual_kWh_demand=6000; % annual energy demand in kWh
energy_generation = double(peak_kW_generation * repmat(energy_generation(1:steps_per_year),years_operation,1)); % energy peak
energy_load = double(annual_kWh_demand * repmat(energy_load(1:steps_per_year),years_operation,1)); % annual energy demand
price_energy_purchase = 0.32; % purchasing price in EUR/kWh
price_energy_sell = 0.065; % selling price in EUR/kWh
BESS_energy_nominal = 5; % nominal energy content in kWh
state_of_charge_min = 0.1; % minimum state of charge
state_of_charge_max = 0.9; % maximum state of charge
state_of_charge_initial = state_of_charge_min; % initial state of charge
erate_discharge = 1; % maximum e-rate during discharge
erate_charge = 0.5; % maximum e-rate during charge
efficiency_discharge = 0.95; % efficiency during discharge
efficiency_charge = 0.95; % efficiency during charge

energy_residual = energy_load - energy_generation;
energy_residual_pos = energy_residual;
	energy_residual_pos(energy_residual_pos<0) = 0;
energy_residual_neg = energy_residual;
	energy_residual_neg(energy_residual_neg>0) = 0;

%% optimization
% decision variables
	energy_actual = optimvar('energy_actual', steps,1,...
		'LowerBound',BESS_energy_nominal*state_of_charge_min, 'UpperBound',BESS_energy_nominal*state_of_charge_max); % actual energy content
	energy_discharge = optimvar('energy_discharge', steps,1,...
		'LowerBound',0, 'UpperBound',BESS_energy_nominal*erate_discharge); % maximum energy during discharge
	energy_charge = optimvar('energy_charge', steps,1,...
		'LowerBound',0, 'UpperBound',BESS_energy_nominal*erate_charge); % maximum energy during charge
	energy_purchase = optimvar('energy_purchase', steps,1,...
		'LowerBound',0); % purchased energy from grid
	energy_sell = optimvar('energy_sell', steps,1,...
		'LowerBound',0); % sold energy to grid
	cost_energy = optimvar('profit_energy', steps,1); % profitability
% objective function
	OptProb = optimproblem('ObjectiveSense','minimize','Objective',...
		sum(cost_energy)); % cumulative traded energy with grid
% constraints
	OptProb.Constraints.profit_energy = ... % calculate profit from energy trading with grid
		cost_energy == - energy_sell * price_energy_sell + energy_purchase * price_energy_purchase;
	OptProb.Constraints.node = ... % energy balance at point of common coupling
		energy_generation + energy_discharge + energy_purchase == energy_load + energy_charge + energy_sell;
	OptProb.Constraints.energy_conservation = ... % energy conservation within the storage system
		energy_actual ==  sparse(diag(ones(steps-1,1),-1)) * energy_actual + energy_charge * efficiency_charge - energy_discharge * (1/efficiency_discharge);
	OptProb.Constraints.energy_conservation(1,:) = ... % energy conservation within the storage system with respect to the initial state of charge
		energy_actual(1,:) == BESS_energy_nominal * state_of_charge_initial + energy_charge(1,:) * efficiency_charge - energy_discharge(1,:) * (1/efficiency_discharge);
% call solver
	[OptDecisionVariables,OptObjectiveValue,OptExitFlag,OptSettings] = solve(OptProb);

%% calculations & plotting
state_of_charge = OptDecisionVariables.energy_actual / BESS_energy_nominal;
equivalent_full_cycles = (OptDecisionVariables.energy_charge + OptDecisionVariables.energy_discharge) / (2 * BESS_energy_nominal);
figure();
ax1=subplot(3,1,1); hold on;
	yyaxis left;
	area(1:steps,energy_load, 'FaceColor',[0.6 0.6 0.6], 'EdgeColor','none', 'DisplayName','E^{Load}');
	area(1:steps,-energy_generation, 'FaceColor',[1.0 0.8 0.0], 'EdgeColor','none', 'DisplayName','E^{Generation}');
	xlim([0 steps]); ylabel('Energy / kWh');
	yyaxis right;
	plot(1:steps,cumsum(OptDecisionVariables.profit_energy), 'LineWidth',2, 'DisplayName','Profit^{w/ ESS}');
	plot(1:steps,cumsum(energy_residual_neg*price_energy_sell-energy_residual_pos*price_energy_purchase), 'LineWidth',2, 'DisplayName','Profit^{w/o ESS}');
	xlim([0 steps]); ylabel('Cumulative Profit / EUR');
	xlabel('Time / h');
	legend('Location','SouthWest'); hold off; grid on; box on;
	
ax2=subplot(3,1,2); hold on;
	plot(1:steps,state_of_charge * 100, '-', 'LineWidth',2, 'DisplayName','State of Charge');
	xlim([0 steps]); ylim([0 100]); ylabel('State of Charge / %'); xlabel('Time / h');
	legend('Location','South'); hold off; grid on; box on;
	
ax3=subplot(3,1,3); hold on;
	plot(1:steps,cumsum(equivalent_full_cycles), '-', 'LineWidth',2, 'DisplayName','Cumulative Equivalent Full Cycles');
	xlim([0 steps]); ylabel('Cumulative Equivalent Full Cycles / 1'); xlabel('Time / h');
	legend('Location','NorthWest'); hold off; grid on; box on;
    
    linkaxes([ax1 ax2 ax3], 'x')
    
%showproblem(OptProb)