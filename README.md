# Evaluation Influence-Guided Simulation Campaigns for Use Case Sign Following Robot

This repository contains the implementation artifacts used to apply an influence-guided refinement process to a sign-following robot case study provided by Mathworks: [Sign Following Robot with Time Synchronization Using ROS and Gazebo Co-Simulation](https://fr.mathworks.com/help/robotics/ug/sign-following-robot-with-time-synchronization-using-ros-and-gazebo-co-simulation.html). It includes simulation campaign and analysis scripts, configuration files, and case-study-specific results used to refine influence knowledge from simulation evidence. The approach uses simulation evidence to identify, validate, and refine the **Influence Model** of this use case, which are relations among design artifacts, environmental factors, upstream System Response Properties (SRPs), that shape output SRPs. In prior work, [DemIstifyCPS: A Domain-Specific Language for Influence Modeling in Cyber-Physical Systems](https://www.scitepress.org/publishedPapers/2026/143420/pdf/index.html), influences were defined and operationalized with the [Domain-Specific Language DemIstifyCPS](https://github.com/barbara-da-silva-oliveira/DemIstifyCPS/tree/main). This work exploit the Influence model and exploit it with simulation for the design model refinement.

In this work, we treat simulation not only as a validation tool, but as a systematic mechanism for improving design-time knowledge.

## Overview

This repository operationalizes an influence-guided workflow with two complementary loops:

1. **Structural refinement**  
   Identifies which participants significantly affect each SRP using simulation campaigns and sensitivity analysis. In this phase participants can be prunned and ranked according to its measured effect in System Response Property.

2. **Functional refinement**  
   Uses the structural results to guide more focused simulation campaigns and approximate influence functions through lightweight abstractions.

The goal is to turn initially incomplete influence knowledge into structured, simulation evidence-based design knowledge that can support downstream reasoning, model refinement, and design-time decision making.

## Influence Model Sign Following Robot Case Study

Influences identified in the sign-following robot case study include:

- Nominal velocity and Ground Friction influencing Average Segment Speed.
- Controller Gain, Velocity, and Friction influencing Time Turning.
- Sign Detection Quality, Average Speed, and Controller Gain influencing Tracking Error.
- Ambient lighting and Blob Size influencing Sign Detection Quality.

<img width="872" height="352" alt="influencesSignFollow(2)" src="https://github.com/user-attachments/assets/be5ecf37-c055-496b-b029-787bd3c2fbe4" />


### Structural Refinement

The structural refinement loop aims to validate and refine the participant set of each Influence.

Main steps:

1. Define set of participants and target SRP for each Influence.
2. Generate a Morris design over the participant input space.
3. Execute Simulink/Gazebo simulations.
4. Extract SRPs from simulation logs.
5. Aggregate replicated runs.
6. Compute Morris sensitivity indices:
   - `MuStar`: providing overall participant impact on the resulting SRP.
   - `Sigma`: non-linearity or interaction indicator.
7. Retain, prune, or flag participants based on sensitivity and aleatory uncertainty.

### Functional Refinement

The functional refinement loop uses structural refinement results to guide another simulation campaign.

Main steps:

1. Load structural sensitivity indices.
2. Generate a Weighted Latin Hypercube Sampling design.
3. Execute refined simulation campaigns.
4. Aggregate valid traces.

From the results of functional refinement, we build abstractions of influence functions, such as monotonicity lookup tables.

## Implementation

The case study uses a sign-following mobile robot implemented with:

- MATLAB/Simulink for control logic.
- Gazebo for robot and environment simulation.
- ROS communication between Simulink and Gazebo.
- Simulation campaigns to explore environmental and design parameter variations.

<img width="803" height="575" alt="screenshot" src="https://github.com/user-attachments/assets/764f0084-9f98-4358-8867-608cbbebeecf" />


The robot must detect directional signs, follow a path, and stop at the final sign. From simulation traces, we have extracted SRPs such as:

- `sign_detection_quality`
- `average_segment_speed`
- `tracking_error_rms`
- `completion_time`
- `time_turning`
- `stop_distance_to_sign`

## Campaigns
The simulation campaigns in this repository were created specifically for the sign-following robot use case; they are derived from its Influence Model.

### Campaign P: Perception Influence

Studies how perception-related factors affect sign detection quality.
Participants:

- `luminosity`
- `size`
- `transparency`

Target SRP:

- `sign_detection_quality`

### Campaign S: Floor Slipperiness Influence

Studies how motion and environment factors affect robot average segment speed.

Typical participants:

- `v`
- `friction`

Target SRP:

- `average_segment_speed`

### Campaign C: Control-Stability Influence

Studies how controller gain and upstream operating regimes affect tracking of signs performance.

Typical participants:

- `w_gain`
- upstream perception regime
- upstream speed regime

Target SRP:

- `tracking_error_rms`

### Campaign M: Mission-Level Influence

Studies how combined upstream and control factors affect mission-level, the time the robot turns.

Typical participants:

- `v_nominal`
- `ground_friction`
- `w_gain`

Target SRP:

- `time_turning`

## Prerequisites

The scripts are designed for an environment similar to the following:

- MATLAB R2024a
- ROS / ROS2 support depending on the model configuration
- Python with SALib installed

Python dependencies may include:

```bash
pip install SALib numpy pandas scipy
```

MATLAB must be configured so that it can call the required Python environment.

## Install the Ubuntu Virtual Machine provided by MathWorks
Please refer to this repository Mathworks [Sign Following Robot with Time Synchronization Using ROS and Gazebo Co-Simulation](https://fr.mathworks.com/help/robotics/ug/sign-following-robot-with-time-synchronization-using-ros-and-gazebo-co-simulation.html) and follow the instructions for the installation, configuration, and usage of the simulation environment Matlab-Gazebo. In the VM, the simulations are pre-configured. For the paper experiments, we have modified the position of the Stop Sign. To replicate the same experiments, you must use the world file located in this repository.

## Clone this repository:
Clone this repository in the same repository as the Matlab model's folder:

```bash
git clone https://github.com/anon-researcher-models/anonymous-repo.git
```

## Configuration

Before running the campaigns, update the configuration fields in the MATLAB scripts:

In defaultConfigStructural.m and defaultConfigFunctional.m, configure the acess to your VM, and the paht to the Gazebo world file of the world files:

```matlab
cfg.vmIP       = '192.168.61.129';
cfg.vmUser     = 'user';
cfg.vmPassword = 'password';

cfg.remoteDir  = 'catkin_ws/src/mw_vision_example/worlds';
cfg.remoteFile = 'mw_vision_world_newstopsign_cosim.world';
```
Also, configure the Simulink model:

```
cfg.modelName = 'signFollowingRobotROSCoSim';
```

Verify SSH/SFTP access to the virtual machine and ROS/Gazebo launch commands.

In both files, you can control the bounds for each of the partipants:

```matlab
cfg.bounds.v = [0.2, 0.4];
cfg.bounds.w = [0.2, 0.4];
cfg.bounds.size = [90, 140];
cfg.bounds.friction = [0.2, 0.7];
cfg.bounds.luminosity = [0.3, 0.5];
cfg.bounds.transparency = [0.0, 0.3];
```

You can also modify the simuation stop time, the number of replicates per each configuration, the number of retries per each repetition, the number of levels and trajectories for the method of Morris. 

```matlab
cfg.simStopTime = 30;
cfg.replicates = 2;
cfg.maxRetriesPerRep = 3;
cfg.num_levels = int32(4);
cfg.N_trajectories = int32(4);
```

## Running the Structural Campaigns in Matlab
The structural refinement campaigns are executed in MATLAB. Before running the scripts, open MATLAB and set the repository folder as the current working directory, or add the campaigns folders to the MATLAB path.
From the MATLAB Command Window, run the structural campaigns as follows:

```matlab
run_structural_campaign("P")
run_structural_campaign("S")
run_structural_campaign("M")
```
For structural campaign C, you need to first run P and S:
```matlab
run_structural_campaign("C")
```

To run the full structural simlation campaign:

```matlab
run_structural_campaign("ALL")
```
The generated outputs are written to the structural campaign results folder defined in the MATLAB configuration.

## Running the Functional Campaigns in Matlab

From the MATLAB Command Window, run the functional campaigns as follows:

```matlab
run_functional_campaign("P_FUNC")
run_functional_campaign("S_FUNC")
run_functional_campaign("M_FUNC")
```
Build the functional regimes for P and S, to be used in campaign C:

```matlab
run_functional_campaign("BUILD_C_REGIMES")
```
Run the control functional refinement:

```matlab
run_functional_campaign("C_FUNC")
```

To run the full functional simulation campaign:

```matlab
run_functional_campaign("ALL")
```
The generated outputs are written to the functional campaign results folder defined in the MATLAB configuration.

## Running the script for analyse of functional results:
Run the script to produce analyses files of the functional refinement for each influence, including motonocity tables in format csv, functional regression results.

```python
functionalCampaignAnalyzer.py
```

## Data Validity

Each design point may be executed with multiple replicates to account for uncertainty. Moreover, we may realize multiple trials for each replicate, since we must account for technical problems such as loss of communication between Matlab and Gazebo.

The obtained results distinguish between:

- valid runs
- behavioral NaN outcomes
- zero-valued but valid outcomes

This distinction is important because simulation failures and meaningful behavioral outcomes should not be treated as the same in the analysis. 
