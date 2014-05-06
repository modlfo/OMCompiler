/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2014, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package HpcOmSimCodeMain
" file:        HpcOmSimCodeMain.mo
  package:     HpcOmSimCodeMain
  description: HpcOmSimCodeMain contains the logic to create a parallelized simcode.

  RCS: $Id: HpcOmSimCodeMain.mo 15486 2013-05-24 11:12:35Z marcusw $
"
// public imports
public import Absyn;
public import BackendDAE;
public import DAE;
public import HashTableExpToIndex;
public import HpcOmSimCode;
public import SimCode;

// protected imports
protected import Debug;
protected import Error;
protected import Flags;
protected import GlobalScript;
protected import HpcOmMemory;
protected import HpcOmScheduler;
protected import HpcOmTaskGraph;
protected import List;
protected import SimCodeUtil;
protected import System;
protected import Util;

public function createSimCode "function createSimCode
  entry point to create SimCode from BackendDAE."
  input BackendDAE.BackendDAE inBackendDAE;
  input Absyn.Path inClassName;
  input String filenamePrefix;
  input String inString11;
  input list<SimCode.Function> functions;
  input list<String> externalFunctionIncludes;
  input list<String> includeDirs;
  input list<String> libs;
  input Option<SimCode.SimulationSettings> simSettingsOpt;
  input list<SimCode.RecordDeclaration> recordDecls;
  input tuple<Integer, HashTableExpToIndex.HashTable, list<DAE.Exp>> literals;
  input Absyn.FunctionArgs args;
  output SimCode.SimCode simCode;
algorithm
  simCode := matchcontinue (inBackendDAE, inClassName, filenamePrefix, inString11, functions, externalFunctionIncludes, includeDirs, libs, simSettingsOpt, recordDecls, literals, args)
    local
      String fileDir, cname;
      Integer lastEqMappingIdx, maxDelayedExpIndex, uniqueEqIndex, numberofEqns, numberOfInitialEquations, numberOfInitialAlgorithms, numStateSets;
      Integer numberofLinearSys, numberofNonLinearSys, numberofMixedSys;
      BackendDAE.BackendDAE dlow, dlow2;
      Option<BackendDAE.BackendDAE> initDAE;
      BackendDAE.IncidenceMatrix incidenceMatrix;
      DAE.FunctionTree functionTree;
      BackendDAE.SymbolicJacobians symJacs;
      Absyn.Path class_;

      // new variables
      SimCode.ModelInfo modelInfo;
      list<SimCode.SimEqSystem> allEquations;
      list<list<SimCode.SimEqSystem>> odeEquations;         // --> functionODE
      list<list<SimCode.SimEqSystem>> algebraicEquations;   // --> functionAlgebraics
      list<SimCode.SimEqSystem> residuals;                  // --> initial_residual
      Boolean useSymbolicInitialization;                    // true if a system to solve the initial problem symbolically is generated, otherwise false
      Boolean useHomotopy;                                  // true if homotopy(...) is used during initialization
      list<SimCode.SimEqSystem> initialEquations;           // --> initial_equations
      list<SimCode.SimEqSystem> startValueEquations;        // --> updateBoundStartValues
      list<SimCode.SimEqSystem> nominalValueEquations;      // --> updateBoundNominalValues
      list<SimCode.SimEqSystem> minValueEquations;          // --> updateBoundMinValues
      list<SimCode.SimEqSystem> maxValueEquations;          // --> updateBoundMaxValues
      list<SimCode.SimEqSystem> parameterEquations;         // --> updateBoundParameters
      list<SimCode.SimEqSystem> removedEquations;
      list<SimCode.SimEqSystem> algorithmAndEquationAsserts;
      list<SimCode.SimEqSystem> jacobianEquations;
      list<SimCode.SimEqSystem> zeroCrossingsEquations;
      //list<DAE.Statement> algorithmAndEquationAsserts;
      list<DAE.Constraint> constraints;
      list<DAE.ClassAttributes> classAttributes;
      list<BackendDAE.ZeroCrossing> zeroCrossings, sampleZC, relations;
      list<SimCode.SimWhenClause> whenClauses;
      list<DAE.ComponentRef> discreteModelVars;
      SimCode.ExtObjInfo extObjInfo;
      SimCode.MakefileParams makefileParams;
      SimCode.DelayedExpression delayedExps;
      BackendDAE.Variables knownVars;
      list<BackendDAE.Var> varlst;

      list<SimCode.JacobianMatrix> LinearMatrices, SymbolicJacs, SymbolicJacsTemp, SymbolicJacsStateSelect;
      SimCode.HashTableCrefToSimVar crefToSimVarHT;
      Boolean ifcpp;
      BackendDAE.EqSystems eqs;
      BackendDAE.Shared shared;
      BackendDAE.EquationArray removedEqs;
      list<DAE.Constraint> constrsarr;
      list<DAE.ClassAttributes> clsattrsarra;

      list<DAE.Exp> lits;
      list<SimCode.SimVar> tempvars;

      SimCode.JacobianMatrix jacG;
      Integer highestSccIdx, compCountPlusDummy;
      Option<BackendDAE.BackendDAE> inlineDAE;
      list<SimCode.StateSet> stateSets;
      array<Integer> systemIndexMap;
      list<tuple<Integer,Integer>> equationSccMapping, equationSccMapping1; //Maps each simEq to the scc
      array<list<Integer>> sccSimEqMapping; //Maps each scc to a list of simEqs
      array<Integer> simeqCompMapping; //Maps each simEq to the scc
      list<BackendDAE.TimeEvent> timeEvents;
      BackendDAE.StrongComponents allComps;

      HpcOmTaskGraph.TaskGraph taskGraph;
      HpcOmTaskGraph.TaskGraph taskGraphOde;
      HpcOmTaskGraph.TaskGraph taskGraph1;
      HpcOmTaskGraph.TaskGraphMeta taskGraphData;
      HpcOmTaskGraph.TaskGraphMeta taskGraphDataOde;
      String fileName, fileNamePrefix;
      Integer numProc;
      HpcOmTaskGraph.TaskGraphMeta taskGraphData1;
      list<list<Integer>> parallelSets;
      list<list<Integer>> criticalPaths, criticalPathsWoC;
      Real cpCosts, cpCostsWoC, serTime, parTime, speedUp, speedUpMax;

      //Additional informations to append SimCode
      list<DAE.Exp> simCodeLiterals;
      list<SimCode.JacobianMatrix> jacobianMatrixes;
      list<SimCode.SimEqSystem> residualEquations;
      Option<SimCode.SimulationSettings> simulationSettingsOpt;
      list<SimCode.RecordDeclaration> simCodeRecordDecls;
      list<String> simCodeExternalFunctionIncludes;

      Boolean taskGraphMetaValid, numFixed;
      String taskGraphMetaMessage, criticalPathInfo;
      array<tuple<Integer,Integer,Real>> schedulerInfo;
      HpcOmSimCode.Schedule schedule;
      array<tuple<Integer,Integer,Integer>> eqCompMapping, varCompMapping;
      Real graphCosts;
      Integer graphOps;
      Option<SimCode.BackendMapping> backendMapping;
      Option<HpcOmSimCode.MemoryMap> optTmpMemoryMap;
    case (BackendDAE.DAE(eqs=eqs), _, _, _, _, _, _, _, _, _, _, _) equation

      //Setup
      //-----
      System.realtimeTick(GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);
      (simCode,(lastEqMappingIdx,equationSccMapping)) = SimCodeUtil.createSimCode(inBackendDAE, inClassName, filenamePrefix, inString11, functions, externalFunctionIncludes, includeDirs, libs, simSettingsOpt, recordDecls, literals, args);
      (allComps,_) = HpcOmTaskGraph.getSystemComponents(inBackendDAE);
      highestSccIdx = findHighestSccIdxInMapping(equationSccMapping,-1);
      compCountPlusDummy = listLength(allComps)+1;
      equationSccMapping1 = removeDummyStateFromMapping(equationSccMapping);
      //the mapping can contain a dummy state as first scc
      equationSccMapping = Util.if_(intEq(highestSccIdx, compCountPlusDummy), equationSccMapping1, equationSccMapping);

      sccSimEqMapping = convertToSccSimEqMapping(equationSccMapping, listLength(allComps));
      simeqCompMapping = convertToSimeqCompMapping(equationSccMapping, lastEqMappingIdx);
      Debug.execStat("hpcom setup", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);

      //dumpSccSimEqMapping(sccSimEqMapping);

      //Create TaskGraph
      //----------------
      (taskGraph,taskGraphData) = HpcOmTaskGraph.createTaskGraph(inBackendDAE,filenamePrefix);

      Debug.execStat("hpcom createTaskGraph", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);
      fileName = ("taskGraph"+&filenamePrefix+&".graphml");
      schedulerInfo = arrayCreate(arrayLength(taskGraph), (-1,-1,-1.0));
      HpcOmTaskGraph.dumpAsGraphMLSccLevel(taskGraph, taskGraphData, fileName, "", {}, {}, sccSimEqMapping ,schedulerInfo);
      Debug.execStat("hpcom dump TaskGraph", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);

      HpcOmTaskGraph.TASKGRAPHMETA(varCompMapping=varCompMapping,eqCompMapping=eqCompMapping) = taskGraphData;
      //HpcOmTaskGraph.printvarCompMapping(varCompMapping,1);
      //HpcOmTaskGraph.printeqCompMapping(eqCompMapping,1);

      //Create Costs
      //------------
      taskGraphData = HpcOmTaskGraph.createCosts(inBackendDAE, filenamePrefix +& "_eqs_prof" , simeqCompMapping, taskGraphData);
      Debug.execStat("hpcom create costs", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);

      //Get ODE System
      //--------------
      taskGraphOde = arrayCopy(taskGraph);
      taskGraphDataOde = HpcOmTaskGraph.copyTaskGraphMeta(taskGraphData);
      (taskGraphOde,taskGraphDataOde) = HpcOmTaskGraph.getOdeSystem(taskGraphOde,taskGraphDataOde,inBackendDAE,filenamePrefix);
      Debug.execStat("hpcom get ODE system", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);

      taskGraphMetaValid = HpcOmTaskGraph.validateTaskGraphMeta(taskGraphDataOde, inBackendDAE);
      taskGraphMetaMessage = Util.if_(taskGraphMetaValid, "TaskgraphMeta valid\n", "TaskgraphMeta invalid\n");
      print(taskGraphMetaMessage);

      //HpcOmTaskGraph.printTaskGraph(taskGraphOde);
      //HpcOmTaskGraph.printTaskGraphMeta(taskGraphDataOde);

      //Assign levels and get critcal path
      //----------------------------------
      ((criticalPaths,cpCosts),(criticalPathsWoC,cpCostsWoC),_) = HpcOmTaskGraph.longestPathMethod(taskGraphOde,taskGraphDataOde);
      cpCosts = HpcOmTaskGraph.roundReal(cpCosts,2);
      cpCostsWoC = HpcOmTaskGraph.roundReal(cpCostsWoC,2);
      criticalPathInfo = HpcOmTaskGraph.dumpCriticalPathInfo((criticalPaths,cpCosts),(criticalPathsWoC,cpCostsWoC));
      ((graphOps,graphCosts)) = HpcOmTaskGraph.sumUpExecCosts(taskGraphDataOde);
      graphCosts = HpcOmTaskGraph.roundReal(graphCosts,2);
      criticalPathInfo = criticalPathInfo +& " sum: (" +& realString(graphCosts) +& " ; " +& intString(graphOps) +& ")";
      fileName = ("taskGraph"+&filenamePrefix+&"ODE.graphml");
      schedulerInfo = arrayCreate(arrayLength(taskGraphOde), (-1,-1,-1.0));
      Debug.execStat("hpcom assign levels / get crit. path", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);
      HpcOmTaskGraph.dumpAsGraphMLSccLevel(taskGraphOde, taskGraphDataOde, fileName, criticalPathInfo, HpcOmTaskGraph.convertNodeListToEdgeTuples(List.first(criticalPaths)), HpcOmTaskGraph.convertNodeListToEdgeTuples(List.first(criticalPathsWoC)), sccSimEqMapping, schedulerInfo);
      Debug.execStat("hpcom dump ODE TaskGraph", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);

      //Apply filters
      //-------------
      taskGraphData1 = taskGraphDataOde;
      taskGraph1 = taskGraphOde;
      (taskGraph1,taskGraphData1) = applyFiltersToGraph(taskGraphOde,taskGraphDataOde,inBackendDAE,true); //TODO: Rename this to applyGRS or someting like that
      Debug.execStat("hpcom GRS", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);
      //Debug.fcall(Flags.HPCOM_DUMP,HpcOmTaskGraph.printTaskGraph,taskGraph1);
      //Debug.fcall(Flags.HPCOM_DUMP,HpcOmTaskGraph.printTaskGraphMeta,taskGraphData1);


      //Create schedule
      //---------------
      numProc = Flags.getConfigInt(Flags.NUM_PROC);
      (numProc,numFixed) = setNumProc(numProc,cpCostsWoC,taskGraphDataOde);
      schedule = createSchedule(taskGraph1,taskGraphData1,sccSimEqMapping,filenamePrefix,numProc);
      (schedule,numProc) = repeatScheduleWithOtherNumProc(taskGraph1,taskGraphData1,sccSimEqMapping,filenamePrefix,cpCostsWoC,schedule,numProc,numFixed);
      criticalPathInfo = HpcOmScheduler.analyseScheduledTaskGraph(schedule,numProc,taskGraph1,taskGraphData1);
      schedulerInfo = HpcOmScheduler.convertScheduleStrucToInfo(schedule,arrayLength(taskGraph));
      Debug.execStat("hpcom create schedule", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);
      fileName = ("taskGraph"+&filenamePrefix+&"ODE_schedule.graphml");

      HpcOmTaskGraph.dumpAsGraphMLSccLevel(taskGraph1, taskGraphData1, fileName, criticalPathInfo, HpcOmTaskGraph.convertNodeListToEdgeTuples(List.first(criticalPaths)), HpcOmTaskGraph.convertNodeListToEdgeTuples(List.first(criticalPathsWoC)), sccSimEqMapping, schedulerInfo);
      //HpcOmScheduler.printSchedule(schedule);

      Debug.execStat("hpcom dump schedule TaskGraph", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);
      SimCode.SIMCODE(modelInfo, simCodeLiterals, simCodeRecordDecls, simCodeExternalFunctionIncludes, allEquations, odeEquations, algebraicEquations, residualEquations, useSymbolicInitialization, useHomotopy, initialEquations, startValueEquations, nominalValueEquations, minValueEquations, maxValueEquations,
                 parameterEquations, removedEquations, algorithmAndEquationAsserts, zeroCrossingsEquations, jacobianEquations, stateSets, constraints, classAttributes, zeroCrossings, relations, timeEvents, whenClauses,
                 discreteModelVars, extObjInfo, makefileParams, delayedExps, jacobianMatrixes, simulationSettingsOpt, fileNamePrefix, _, _, crefToSimVarHT, backendMapping) = simCode;

      checkOdeSystemSize(taskGraphOde,odeEquations);
      Debug.execStat("hpcom check ODE system size", GlobalScript.RT_CLOCK_EXECSTAT_HPCOM_MODULES);

      optTmpMemoryMap = HpcOmMemory.createMemoryMap(modelInfo, taskGraph1, taskGraphData1, eqs, filenamePrefix, schedulerInfo, schedule, sccSimEqMapping, criticalPaths, criticalPathsWoC, criticalPathInfo, allComps);

      simCode = SimCode.SIMCODE(modelInfo, simCodeLiterals, simCodeRecordDecls, simCodeExternalFunctionIncludes, allEquations, odeEquations, algebraicEquations, residualEquations, useSymbolicInitialization, useHomotopy, initialEquations, startValueEquations, nominalValueEquations, minValueEquations, maxValueEquations,
                 parameterEquations, removedEquations, algorithmAndEquationAsserts, zeroCrossingsEquations, jacobianEquations, stateSets, constraints, classAttributes, zeroCrossings, relations, timeEvents, whenClauses,
                 discreteModelVars, extObjInfo, makefileParams, delayedExps, jacobianMatrixes, simulationSettingsOpt, fileNamePrefix, SOME(schedule), optTmpMemoryMap, crefToSimVarHT, backendMapping);

      //evaluateCacheBehaviour(schedulerInfo,taskGraphData1,clTaskMapping, transposeCacheLineTaskMapping(clTaskMapping, arrayLength(taskGraph1)));

      print("HpcOm is still under construction.\n");
      then simCode;
    else equation
      Error.addMessage(Error.INTERNAL_ERROR, {"./Compiler/BackEnd/HpcOmSimCode.mo: function createSimCode failed."});
    then fail();
  end matchcontinue;
end createSimCode;


protected function repeatScheduleWithOtherNumProc"checks if the scheduling with the given numProc is fine.
 if n=auto, more cores are available and more speedup could be achieved repeat schedule with increased num of procs.
 author:Waurich TUD 2013-011"
  input HpcOmTaskGraph.TaskGraph taskGraphIn;
  input HpcOmTaskGraph.TaskGraphMeta taskGraphMetaIn;
  input array<list<Integer>> sccSimEqMappingIn;
  input String fileNamePrefix;
  input Real cpCostsWoC;
  input HpcOmSimCode.Schedule scheduleIn;
  input Integer numProcIn;
  input Boolean numFixed;
  output HpcOmSimCode.Schedule scheduleOut;
  output Integer numProcOut;
protected
  Integer maxNumProc, maxIter;
  Real maxDiff;
algorithm
  maxNumProc := System.numProcessors();
  maxIter := 3;
  maxDiff := 0.5;
  (scheduleOut,numProcOut,_) := repeatScheduleWithOtherNumProc1(taskGraphIn,taskGraphMetaIn,sccSimEqMappingIn,fileNamePrefix,cpCostsWoC,scheduleIn,numProcIn,numFixed,maxNumProc,maxDiff,maxIter);
end repeatScheduleWithOtherNumProc;


protected function repeatScheduleWithOtherNumProc1"checks if the scheduling with the given numProc is fine.
 if n=auto, more cores are available and more speedup could be achieved repeat schedule with increased num of procs.
 author:Waurich TUD 2013-011"
  input HpcOmTaskGraph.TaskGraph taskGraphIn;
  input HpcOmTaskGraph.TaskGraphMeta taskGraphMetaIn;
  input array<list<Integer>> sccSimEqMappingIn;
  input String fileNamePrefix;
  input Real cpCostsWoC;
  input HpcOmSimCode.Schedule scheduleIn;
  input Integer numProcIn;
  input Boolean numFixed;
  input Integer maxNumProc;
  input Real maxDiff;
  input Integer numIterIn;
  output HpcOmSimCode.Schedule scheduleOut;
  output Integer numProcOut;
  output Integer numIterOut;
algorithm
  (scheduleOut,numProcOut,numIterOut) := matchcontinue(taskGraphIn,taskGraphMetaIn,sccSimEqMappingIn,fileNamePrefix,cpCostsWoC,scheduleIn,numProcIn,numFixed,maxNumProc,maxDiff,numIterIn)
    local
      Boolean scheduleAgain;
      Integer numProc, numIt;
      Real serTime,parTime,speedup,speedUp,speedUpMax,diff;
      HpcOmSimCode.Schedule schedule;
    case(_,_,_,_,_,_,_,true,_,_,_)
      equation // do not schedule again because the number of procs was given
        then
          (scheduleIn,numProcIn,0);
    case(_,_,_,_,_,_,_,false,_,_,_)
      equation
        true = numIterIn == 0; // the max number of schedules with increased num of procs
        then
          (scheduleIn,numProcIn,0);
    case(_,_,_,_,_,_,_,false,_,_,_)
      equation
        (_,_,speedUp,speedUpMax) = HpcOmScheduler.predictExecutionTime(scheduleIn,SOME(cpCostsWoC),numProcIn,taskGraphIn,taskGraphMetaIn);
        diff = speedUpMax -. speedUp;
        //print("the new speedUp with "+&intString(numProcIn)+&" processors: "+&realString(speedUp)+&"\n");
        true = diff <. maxDiff;
        //print("the schedule is fine\n");
      then
        (scheduleIn,numProcIn,numIterIn);
    else
      equation
        numProc = numProcIn+1; // increase the number of procs
        numIt = numIterIn-1; // lower the counter of scheduling runs
        scheduleAgain = intLe(numProc,maxNumProc);
        //print("schedule again\n");
        numProc = Util.if_(scheduleAgain,numProc,numProcIn);
        numIt = Util.if_(scheduleAgain,numIt,0);
        schedule= Debug.bcallret5(scheduleAgain,createSchedule,taskGraphIn,taskGraphMetaIn,sccSimEqMappingIn,fileNamePrefix,numProc,scheduleIn);
        (schedule,numProc,numIt) = repeatScheduleWithOtherNumProc1(taskGraphIn,taskGraphMetaIn,sccSimEqMappingIn,fileNamePrefix,cpCostsWoC,schedule,numProc,numFixed,maxNumProc,maxDiff,numIt);
      then
        (schedule,numProc,numIt);
  end matchcontinue;
end repeatScheduleWithOtherNumProc1;


protected function setNumProc "sets the number of processors. its upper limit is the number of processsors provided by the system.
if no n-flag is set, a ideal number is suggested but the simulation fails.
author: Waurich TUD 2013-11"
  input Integer numProcFlag;
  input Real cpCosts;
  input HpcOmTaskGraph.TaskGraphMeta taskGraphMetaIn;
  output Integer numProcOut;
  output Boolean numFixed;
algorithm
  (numProcOut,numFixed) := match(numProcFlag,cpCosts,taskGraphMetaIn)
    local
      Boolean isFixed;
      Integer numProcSys, numProc, numProcSched;
      Real serCosts, maxSpeedUp;
      String string1, string2;
    case(0,_,_)
      equation
        serCosts = HpcOmScheduler.getSerialExecutionTime(taskGraphMetaIn);
        maxSpeedUp = realDiv(serCosts,cpCosts);
        numProcSched = realInt(realAdd(maxSpeedUp,1.0));
        numProcSys = System.numProcessors();
        _ = intMin(numProcSched,numProcSys);
        string1 = "Your system provides only "+&intString(numProcSys)+&" processors!\n";
        string2 = intString(numProcSched)+&" processors might be a reasonable number of processors.\n";
        string1 = Util.if_(intGt(numProcSched,numProcSys),string1,string2);
        _ =  Util.if_(intGt(numProcSched,numProcSys),true,false);
        print("Please set the number of processors you want to use!\n");
        print(string1);
      then
        fail();
    else
      equation
        numProcSys = System.numProcessors();
        numProc = Util.if_(intGt(numProcFlag,numProcSys),numProcSys,numProcFlag); // the system does not provide so many cores
        Debug.bcall(intGt(numProcFlag,numProcSys),print,"Warning: Your system provides only "+&intString(numProcSys)+&" processors!\n");
      then
        (numProc,true);
  end match;
end setNumProc;


protected function applyFiltersToGraph
  input HpcOmTaskGraph.TaskGraph iTaskGraph;
  input HpcOmTaskGraph.TaskGraphMeta iTaskGraphMeta;
  input BackendDAE.BackendDAE inBackendDAE;
  input Boolean iApplyFilters;
  output HpcOmTaskGraph.TaskGraph oTaskGraph;
  output HpcOmTaskGraph.TaskGraphMeta oTaskGraphMeta;
protected
  String flagValue;
  Boolean changed1,changed2;
  HpcOmTaskGraph.TaskGraph taskGraph1;
  HpcOmTaskGraph.TaskGraphMeta taskGraphMeta1;

  array<list<Integer>> sccSimEqMapping;
  BackendDAE.StrongComponents allComps;
  array<tuple<Integer,Integer>> schedulerInfo;
algorithm
  (oTaskGraph,oTaskGraphMeta) := matchcontinue(iTaskGraph,iTaskGraphMeta,inBackendDAE,iApplyFilters)
    case(_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        true = stringEq(flagValue, "level");
      then (iTaskGraph, iTaskGraphMeta);
    case(_,_,_,true)
      equation
        //print("Start merging\n");
        //Merge simple and parent nodes
        taskGraph1 = arrayCopy(iTaskGraph);
        taskGraphMeta1 = HpcOmTaskGraph.copyTaskGraphMeta(iTaskGraphMeta);
        (taskGraph1,taskGraphMeta1,changed1) = HpcOmTaskGraph.mergeSimpleNodes(taskGraph1,taskGraphMeta1,inBackendDAE);

        //(allComps,_) = HpcOmTaskGraph.getSystemComponents(inBackendDAE);
        //sccSimEqMapping = arrayCreate(listLength(allComps), {});
        //schedulerInfo = arrayCreate(arrayLength(taskGraph1), (-1,-1));
        //print("MergeParentNodes\n");
        //HpcOmTaskGraph.dumpAsGraphMLSccLevel(taskGraph1, taskGraphMeta1, "testgraph.graphml", "", {}, {}, sccSimEqMapping, schedulerInfo);
        (taskGraph1,taskGraphMeta1,changed2) = HpcOmTaskGraph.mergeParentNodes(taskGraph1, taskGraphMeta1);
        (taskGraph1,taskGraphMeta1) = applyFiltersToGraph(taskGraph1,taskGraphMeta1,inBackendDAE,changed1 or changed2);
      then (taskGraph1,taskGraphMeta1);
    else then (iTaskGraph, iTaskGraphMeta);
  end matchcontinue;
end applyFiltersToGraph;

protected function createSchedule
  input HpcOmTaskGraph.TaskGraph iTaskGraph;
  input HpcOmTaskGraph.TaskGraphMeta iTaskGraphMeta;
  input array<list<Integer>> iSccSimEqMapping;
  input String iFilenamePrefix;
  input Integer numProc;
  output HpcOmSimCode.Schedule oSchedule;
protected
  String flagValue;
  list<Integer> lst;
  HpcOmTaskGraph.TaskGraph taskGraph1;
  HpcOmTaskGraph.TaskGraphMeta taskGraphMeta1;
algorithm
  oSchedule := matchcontinue(iTaskGraph,iTaskGraphMeta,iSccSimEqMapping,iFilenamePrefix,numProc)
    case(_,_,_,_,_)
      equation
        true = arrayLength(iTaskGraph) == 0;
        print("There is no ODE system that can be parallelized!\n");
        // just did this because this works fine. TODO: make something reasonable here and do not use a scheduler.
      then
        HpcOmScheduler.createLevelSchedule(iTaskGraphMeta,iSccSimEqMapping);
    case(_,_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        true = stringEq(flagValue, "level");
        print("Using level Scheduler\n");
      then HpcOmScheduler.createLevelSchedule(iTaskGraphMeta,iSccSimEqMapping);
    case(_,_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        true = stringEq(flagValue, "ext");
        print("Using external Scheduler\n");
      then HpcOmScheduler.createExtSchedule(iTaskGraph, iTaskGraphMeta, numProc, iSccSimEqMapping, "taskGraph" +& iFilenamePrefix +& "_ext.graphml");
    case(_,_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        true = stringEq(flagValue, "metis");
        print("Using METIS Scheduler\n");
      then HpcOmScheduler.createExtCSchedule(iTaskGraph, iTaskGraphMeta, numProc, iSccSimEqMapping);
    case(_,_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        true = stringEq(flagValue, "hmet");
        print("Using hMETIS Scheduler\n");
      then HpcOmScheduler.createhmetSchedule(iTaskGraph, iTaskGraphMeta, numProc, iSccSimEqMapping);
    case(_,_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        true = stringEq(flagValue, "listr");
      then HpcOmScheduler.createListScheduleReverse(iTaskGraph,iTaskGraphMeta,numProc,iSccSimEqMapping);
    case(_,_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        true = stringEq(flagValue, "list");
      then HpcOmScheduler.createListSchedule(iTaskGraph,iTaskGraphMeta,numProc,iSccSimEqMapping);
    case(_,_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        true = stringEq(flagValue, "mcp");
        print("Using Modified Critical Path Scheduler\n");
      then HpcOmScheduler.createMCPschedule(iTaskGraph,iTaskGraphMeta,numProc,iSccSimEqMapping);
    case(_,_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        true = stringEq(flagValue, "taskdep");
        print("Using OpenMP task dependencies\n");
      then HpcOmScheduler.createTaskDepSchedule(iTaskGraph,iTaskGraphMeta,iSccSimEqMapping);
    case(_,_,_,_,_)
      equation
        flagValue = Flags.getConfigString(Flags.HPCOM_SCHEDULER);
        print("HpcOmScheduler.createSchedule warning: The scheduler '" +& flagValue +& "' is unknown. The list-scheduling algorithm is used instead.\n");
      then HpcOmScheduler.createListSchedule(iTaskGraph,iTaskGraphMeta,numProc,iSccSimEqMapping);
    else
      equation
        print("HpcOmSimCode.createSchedule failed. Maybe the n-Flag was not set correctly\n");
      then fail();
  end matchcontinue;
end createSchedule;

protected function convertToSccSimEqMapping "function convertToSccSimEqMapping
  author: marcusw
  Converts the given mapping (simEqIndex -> sccIndex) to the inverse mapping (sccIndex->simEqIndex)."
  input list<tuple<Integer,Integer>> iMapping; //the mapping (simEqIndex -> sccIndex)
  input Integer numOfSccs; //important for arrayCreate
  output array<list<Integer>> oMapping; //the created mapping (sccIndex->simEqIndex)

protected
  array<list<Integer>> tmpMapping;

algorithm
  tmpMapping := arrayCreate(numOfSccs,{});
  //print("convertToSccSimEqMapping with " +& intString(numOfSccs) +& " sccs.\n");
  _ := List.fold(iMapping, convertToSccSimEqMapping1, tmpMapping);
  oMapping := tmpMapping;

end convertToSccSimEqMapping;

protected function convertToSccSimEqMapping1 "function convertToSccSimEqMapping1
  author: marcusw
  Helper function for convertToSccSimEqMapping. It will update the arrayIndex of the given mapping value."
  input tuple<Integer,Integer> iMapping; //<simEqIdx,sccIdx>
  input array<list<Integer>> iSccMapping;
  output array<list<Integer>> oSccMapping;

protected
  Integer i1,i2;
  List<Integer> tmpList;

algorithm
  (i1,i2) := iMapping;
  //print("convertToSccSimEqMapping1 accessing index " +& intString(i2) +& ".\n");
  tmpList := arrayGet(iSccMapping,i2);
  tmpList := i1 :: tmpList;
  oSccMapping := arrayUpdate(iSccMapping,i2,tmpList);

end convertToSccSimEqMapping1;

protected function convertToSimeqCompMapping "function convertToSimeqCompMapping
  author: marcusw
  Converts the given mapping (simEqIndex -> sccIndex) bases on tuples to an array mapping."
  input list<tuple<Integer,Integer>> iMapping; //<simEqIdx,sccIdx>
  input Integer numOfSimEqs;
  output array<Integer> oMapping; //maps each simEq to the scc

protected
  array<Integer> tmpMapping;

algorithm
  tmpMapping := arrayCreate(numOfSimEqs, -1);
  oMapping := List.fold(iMapping, convertToSimeqCompMapping1, tmpMapping);
end convertToSimeqCompMapping;

protected function convertToSimeqCompMapping1 "function convertToSimeqCompMapping1
  author: marcusw
  Helper function for convertToSimeqCompMapping. It will update the array at the given index."
  input tuple<Integer,Integer> iSimEqTuple; //<simEqIdx,sccIdx>
  input array<Integer> iMapping;
  output array<Integer> oMapping;

protected
  Integer simEqIdx,sccIdx;

algorithm
  (simEqIdx,sccIdx) := iSimEqTuple;
  //print("convertToSimeqCompMapping1 " +& intString(simEqIdx) +& " .. " +& intString(sccIdx) +& " iMapping_len: " +& intString(arrayLength(iMapping)) +& "\n");
  oMapping := arrayUpdate(iMapping,simEqIdx,sccIdx);
end convertToSimeqCompMapping1;

protected function dumpSccSimEqMapping "function dumpSccSimEqMapping
  author: marcusw
  Prints the given mapping out to the console."
  input array<list<Integer>> iSccMapping;

protected
  String text;

algorithm
  text := "SccToSimEqMapping";
  ((_,text)) := Util.arrayFold(iSccMapping, dumpSccSimEqMapping1, (1,text));
  print(text +& "\n");
end dumpSccSimEqMapping;

protected function dumpSccSimEqMapping1 "function dumpSccSimEqMapping1
  author: marcusw
  Helper function of dumpSccSimEqMapping to print one mapping list."
  input list<Integer> iMapping;
  input tuple<Integer,String> iIndexText;
  output tuple<Integer,String> oIndexText;

protected
  Integer iIndex;
  String text, iText;

algorithm
  (iIndex,iText) := iIndexText;
  text := List.fold(iMapping, dumpSccSimEqMapping2, " ");
  text := iText +& "\nSCC " +& intString(iIndex) +& ": {" +& text +& "}";
  oIndexText := (iIndex+1,text);
end dumpSccSimEqMapping1;

protected function dumpSccSimEqMapping2 "function dumpSccSimEqMapping2
  author: marcusw
  Helper function of dumpSccSimEqMapping1 to print one mapping element."
  input Integer iIndex;
  input String iText;
  output String oText;

algorithm
  oText := iText +& intString(iIndex) +& " ";

end dumpSccSimEqMapping2;

public function getSimCodeEqByIndex "function getSimCodeEqByIndex
  author: marcusw
  Returns the SimEqSystem which has the given Index. This method is called from susan."
  input list<SimCode.SimEqSystem> iEqs; //All SimEqSystems
  input Integer iIdx; //The index of the wanted system
  output SimCode.SimEqSystem oEq;

protected
  list<SimCode.SimEqSystem> rest;
  SimCode.SimEqSystem head;
  Integer headIdx;

algorithm
  oEq := matchcontinue(iEqs,iIdx)
    case(head::rest,_)
      equation
        headIdx = getIndexBySimCodeEq(head);
        //print("getSimCodeEqByIndex listLength: " +& intString(listLength(iEqs)) +& " head idx: " +& intString(headIdx) +& "\n");
        true = intEq(headIdx,iIdx);
      then head;
    case(head::rest,_) then getSimCodeEqByIndex(rest,iIdx);
    else
      equation
        print("getSimCodeEqByIndex failed. Looking for Index " +& intString(iIdx) +& "\n");
      then fail();
  end matchcontinue;
end getSimCodeEqByIndex;

protected function getIndexBySimCodeEq "function getIndexBySimCodeEq
  author: marcusw
  Just a small helper function to get the index of a SimEqSystem."
  input SimCode.SimEqSystem iEq;
  output Integer oIdx;

protected
  Integer index;

algorithm
  oIdx := match(iEq)
    case(SimCode.SES_RESIDUAL(index=index)) then index;
    case(SimCode.SES_SIMPLE_ASSIGN(index=index)) then index;
    case(SimCode.SES_ARRAY_CALL_ASSIGN(index=index)) then index;
    case(SimCode.SES_IFEQUATION(index=index)) then index;
    case(SimCode.SES_ALGORITHM(index=index)) then index;
    case(SimCode.SES_LINEAR(index=index)) then index;
    case(SimCode.SES_NONLINEAR(index=index)) then index;
    case(SimCode.SES_MIXED(index=index)) then index;
    case(SimCode.SES_WHEN(index=index)) then index;
    else then fail();
  end match;
end getIndexBySimCodeEq;

public function analyzeOdeEquations
  input list<list<SimCode.SimEqSystem>> systems;
algorithm
  _ := List.fold(systems, analyzeOdeEquations1, 1);
end analyzeOdeEquations;

protected function analyzeOdeEquations1
  input list<SimCode.SimEqSystem> iEqs;
  input Integer iLevel;
  output Integer oLevel;
algorithm
  print("Equation level " +& intString(iLevel) +& "\n");
  _ := List.fold(iEqs,analyzeOdeEquations2,1);
  oLevel := iLevel + 1;
end analyzeOdeEquations1;

protected function analyzeOdeEquations2
  input SimCode.SimEqSystem iEq;
  input Integer iEqIndex;
  output Integer oEqIndex;
protected
  Integer simEqIdx;
algorithm
  simEqIdx := getIndexBySimCodeEq(iEq);
  print("Equation " +& intString(simEqIdx) +& "\n");
  oEqIndex := iEqIndex + 1;
end analyzeOdeEquations2;

protected function findHighestSccIdxInMapping "function findHighestSccIdxInMapping
  author: marcusw
  Find the highest scc-index in the mapping list."
  input list<tuple<Integer,Integer>> iEquationSccMapping; //<simEqIdx,sccIdx>
  input Integer iHighestIndex;
  output Integer oIndex;

protected
  Integer eqIdx, sccIdx;
  list<tuple<Integer,Integer>> rest;
algorithm
  oIndex := matchcontinue(iEquationSccMapping,iHighestIndex)
    case((eqIdx,sccIdx)::rest,_)
      equation
        true = intGt(sccIdx,iHighestIndex);
      then findHighestSccIdxInMapping(rest,sccIdx);
    case((eqIdx,sccIdx)::rest,_)
      then findHighestSccIdxInMapping(rest,iHighestIndex);
    else
      then iHighestIndex;
  end matchcontinue;
end findHighestSccIdxInMapping;

protected function removeDummyStateFromMapping "function removeDummyStateFromMapping
  author: marcusw
  Removes all mappings with sccIdx=1 from the list and decrements all other scc-indices by 1."
  input list<tuple<Integer,Integer>> iEquationSccMapping;
  output list<tuple<Integer,Integer>> oEquationSccMapping;
algorithm
  oEquationSccMapping := List.fold(iEquationSccMapping, removeDummyStateFromMapping1, {});
end removeDummyStateFromMapping;

protected function removeDummyStateFromMapping1 "function removeDummyStateFromMapping1
  author: marcusw
  Helper function of removeDummyStateFromMapping. Handles one list-element."
  input tuple<Integer,Integer> iTuple; //<eqIdx,sccIdx>
  input list<tuple<Integer,Integer>> iNewList;
  output list<tuple<Integer,Integer>> oNewList;
protected
  Integer eqIdx,sccIdx;
  tuple<Integer,Integer> newElem;
algorithm
  oNewList := matchcontinue(iTuple,iNewList)
    case((eqIdx,sccIdx),_)
      equation
        true = intEq(sccIdx,1);
      then iNewList;
    case((eqIdx,sccIdx),_)
      equation
        newElem = (eqIdx,sccIdx-1);
      then newElem::iNewList;
    else
      equation
        print("removeDummyStateFromMapping1 failed\n");
    then iNewList;
  end matchcontinue;
end removeDummyStateFromMapping1;

// test functions
//------------------------------------------
//------------------------------------------

protected function checkOdeSystemSize " compares the size of the ode-taskgraph with the number of ode-equations in the simCode.
Remark: this can occure when asserts are added to the ode-system.
author:Waurich TUD 2013-07"
  input HpcOmTaskGraph.TaskGraph taskGraphOdeIn;
  input list<list<SimCode.SimEqSystem>> odeEqsIn;
algorithm
  _ := matchcontinue(taskGraphOdeIn,odeEqsIn)
    local
      Integer actualSize;
      Integer targetSize;
    case(_,_)
      equation
        targetSize = listLength(List.flatten(odeEqsIn));
        actualSize = arrayLength(taskGraphOdeIn);
        true = intEq(targetSize,actualSize);
        print("the ODE-system size is correct("+&intString(actualSize)+&")\n");
        then
          ();
    case(_,_)
      equation
        targetSize = listLength(List.flatten(odeEqsIn));
        actualSize = arrayLength(taskGraphOdeIn);
        true = intEq(targetSize,1) and intEq(actualSize,0);
        // there is a dummyDER in the simcode
        print("the ODE-system size is correct(0)\n");
        then
          ();
    else
      equation
        targetSize = listLength(List.flatten(odeEqsIn));
        actualSize = arrayLength(taskGraphOdeIn);
        print("the size should be "+&intString(targetSize)+&" but it is "+&intString(actualSize)+&" !\n");
        print("the ODE-system is NOT correct\n");
      then
        ();
  end matchcontinue;
end checkOdeSystemSize;

end HpcOmSimCodeMain;