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

encapsulated package SimCodeMain
" file:        SimCodeMain.mo
  package:     SimCodeMain
  description: Code generation using Susan templates

  The entry points to this module are the translateModel function and the
  translateFunctions fuction.

  RCS: $Id$"

// public imports
public
import Absyn;
import BackendDAE;
import BackendDAEUtil;
import Ceval;
import DAE;
import FCore;
import GlobalScript;
import HashTableExpToIndex;
import HashTableStringToPath;
import Tpl;
import Values;
import SimCode;

// protected imports
protected
import BackendDAECreate;
import BackendQSS;
import BaseHashTable;
import ClockIndexes;
import CevalScript;
import CodegenC;
import CodegenFMU;
import CodegenFMUCpp;
import CodegenQSS;
import CodegenAdevs;
import CodegenSparseFMI;
import CodegenCSharp;
import CodegenCpp;
import CodegenCppHpcom;
import CodegenXML;
import CodegenJava;
import CodegenJS;
import Config;
import DAEUtil;
import Debug;
import Error;
import Flags;
import FMI;
import HpcOmSimCodeMain;
import HpcOmTaskGraph;
import SerializeModelInfo;
import SimCodeDump;
import TaskSystemDump;
import SimCodeUtil;
import System;
import Util;
import BackendDump;

public function createSimulationSettings
  input Real startTime;
  input Real stopTime;
  input Integer inumberOfIntervals;
  input Real tolerance;
  input String method;
  input String options;
  input String outputFormat;
  input String variableFilter;
  input String cflags;
  output SimCode.SimulationSettings simSettings;
protected
  Real stepSize;
  Integer numberOfIntervals;
algorithm
  numberOfIntervals := if inumberOfIntervals <= 0 then 1 else inumberOfIntervals;
  stepSize := (stopTime - startTime) / intReal(numberOfIntervals);
  simSettings := SimCode.SIMULATION_SETTINGS(
    startTime, stopTime, numberOfIntervals, stepSize, tolerance,
    method, options, outputFormat, variableFilter, cflags);
end createSimulationSettings;


protected function generateModelCodeFMU "
  Generates code for a model by creating a SimCode structure and calling the
  template-based code generator on it."
  input BackendDAE.BackendDAE inBackendDAE;
  input Absyn.Program p;
  input DAE.DAElist dae;
  input Absyn.Path className;
  input String FMUVersion;
  input String FMUType;
  input String filenamePrefix;
  input Option<SimCode.SimulationSettings> simSettingsOpt;
  output BackendDAE.BackendDAE outIndexedBackendDAE;
  output list<String> libs;
  output String fileDir;
  output Real timeSimCode;
  output Real timeTemplates;
protected
  list<String> includes,includeDirs;
  list<SimCode.Function> functions;
  String filename, funcfilename;
  SimCode.SimCode simCode;
  list<SimCode.RecordDeclaration> recordDecls;
  BackendDAE.BackendDAE indexed_dlow,indexed_dlow_1;
  Absyn.ComponentRef a_cref;
  list<String> libPaths;
  tuple<Integer,HashTableExpToIndex.HashTable,list<DAE.Exp>> literals;
algorithm
  System.realtimeTick(ClockIndexes.RT_CLOCK_SIMCODE);
  a_cref := Absyn.pathToCref(className);
  fileDir := CevalScript.getFileDir(a_cref, p);
  (libs,libPaths,includes, includeDirs, recordDecls, functions, outIndexedBackendDAE, _, literals) :=
    SimCodeUtil.createFunctions(p, dae, inBackendDAE, className);
  (simCode,_) := SimCodeUtil.createSimCode(outIndexedBackendDAE,
    className, filenamePrefix, fileDir, functions, includes, includeDirs, libs, libPaths,simSettingsOpt, recordDecls, literals,Absyn.FUNCTIONARGS({},{}));
  timeSimCode := System.realtimeTock(ClockIndexes.RT_CLOCK_SIMCODE);
  SimCodeUtil.execStat("SimCode");

  System.realtimeTick(ClockIndexes.RT_CLOCK_TEMPLATES);
  callTargetTemplatesFMU(simCode, Config.simCodeTarget(), FMUVersion, FMUType);
  timeTemplates := System.realtimeTock(ClockIndexes.RT_CLOCK_TEMPLATES);
end generateModelCodeFMU;


protected function generateModelCodeXML "
  Generates code for a model by creating a SimCode structure and calling the
  template-based code generator on it."
  input BackendDAE.BackendDAE inBackendDAE;
  input Absyn.Program p;
  input DAE.DAElist dae;
  input Absyn.Path className;
  input String filenamePrefix;
  input Option<SimCode.SimulationSettings> simSettingsOpt;
  output BackendDAE.BackendDAE outIndexedBackendDAE;
  output list<String> libs;
  output String fileDir;
  output Real timeSimCode;
  output Real timeTemplates;
protected
  list<String> includes,includeDirs;
  list<SimCode.Function> functions;
  String filename, funcfilename;
  SimCode.SimCode simCode;
  list<SimCode.RecordDeclaration> recordDecls;
  BackendDAE.BackendDAE indexed_dlow,indexed_dlow_1;
  list<String> libPaths;
  Absyn.ComponentRef a_cref;
  tuple<Integer,HashTableExpToIndex.HashTable,list<DAE.Exp>> literals;
algorithm
  System.realtimeTick(ClockIndexes.RT_CLOCK_SIMCODE);
  a_cref := Absyn.pathToCref(className);
  fileDir := CevalScript.getFileDir(a_cref, p);
  (libs, libPaths, includes, includeDirs, recordDecls, functions, outIndexedBackendDAE, _, literals) :=
    SimCodeUtil.createFunctions(p, dae, inBackendDAE, className);
  (simCode,_) := SimCodeUtil.createSimCode(outIndexedBackendDAE,
    className, filenamePrefix, fileDir, functions, includes, includeDirs, libs,libPaths, simSettingsOpt, recordDecls, literals,Absyn.FUNCTIONARGS({},{}));
  timeSimCode := System.realtimeTock(ClockIndexes.RT_CLOCK_SIMCODE);
  SimCodeUtil.execStat("SimCode");

  System.realtimeTick(ClockIndexes.RT_CLOCK_TEMPLATES);
  callTargetTemplatesXML(simCode, Config.simCodeTarget());
  timeTemplates := System.realtimeTock(ClockIndexes.RT_CLOCK_TEMPLATES);
end generateModelCodeXML;


public function translateModelFMU
"Entry point to translate a Modelica model for FMU export.

 Called from other places in the compiler."
  input FCore.Cache inCache;
  input FCore.Graph inEnv;
  input Absyn.Path className "path for the model";
  input GlobalScript.SymbolTable inInteractiveSymbolTable;
  input String inFMUVersion;
  input String inFMUType;
  input String inFileNamePrefix;
  input Boolean addDummy "if true, add a dummy state";
  input Option<SimCode.SimulationSettings> inSimSettingsOpt;
  output FCore.Cache outCache;
  output Values.Value outValue;
  output GlobalScript.SymbolTable outInteractiveSymbolTable;
  output BackendDAE.BackendDAE outBackendDAE;
  output list<String> outStringLst;
  output String outFileDir;
  output list<tuple<String,Values.Value>> resultValues;
algorithm
  (outCache,outValue,outInteractiveSymbolTable,outBackendDAE,outStringLst,outFileDir,resultValues):=
  matchcontinue (inCache,inEnv,className,inInteractiveSymbolTable,inFMUVersion,inFMUType,inFileNamePrefix,addDummy,inSimSettingsOpt)
    local
      String FMUVersion,FMUType,filenameprefix,file_dir,resstr;
      DAE.DAElist dae;
      FCore.Graph graph;
      BackendDAE.BackendDAE dlow,dlow_1,indexed_dlow_1;
      list<String> libs;
      GlobalScript.SymbolTable st;
      Absyn.Program p;
      //DAE.Exp fileprefix;
      FCore.Cache cache;
      DAE.FunctionTree funcs;
      Real timeSimCode, timeTemplates, timeBackend, timeFrontend;
      String description;
      Boolean symbolicJacActivated;
      Boolean fmi20;

    case (cache,graph,_,st as GlobalScript.SYMBOLTABLE(ast=p),FMUVersion,FMUType,filenameprefix,_, _)
      equation
        /* calculate stuff that we need to create SimCode data structure */
        System.realtimeTick(ClockIndexes.RT_CLOCK_FRONTEND);
        //(cache,Values.STRING(filenameprefix),SOME(_)) = Ceval.ceval(cache,graph, fileprefix, true, SOME(st),NONE(), msg);
        (cache,graph,dae,st) = CevalScript.runFrontEnd(cache,graph,className,st,false);
        timeFrontend = System.realtimeTock(ClockIndexes.RT_CLOCK_FRONTEND);
        System.realtimeTick(ClockIndexes.RT_CLOCK_BACKEND);

        // activate symolic jacobains for fmi 2.0
        // to provide dependence information and partial derivatives
        fmi20 = FMI.isFMIVersion20(FMUVersion);
        symbolicJacActivated = Flags.getConfigBool(Flags.GENERATE_SYMBOLIC_LINEARIZATION);
        Flags.setConfigBool(Flags.GENERATE_SYMBOLIC_LINEARIZATION, fmi20);

        _ = FCore.getFunctionTree(cache);
        dae = DAEUtil.transformationsBeforeBackend(cache,graph,dae);
        description = DAEUtil.daeDescription(dae);
        dlow = BackendDAECreate.lower(dae, cache, graph, BackendDAE.EXTRA_INFO(description,filenameprefix));
        dlow_1 = BackendDAEUtil.getSolvedSystem(dlow,inFileNamePrefix);
        timeBackend = System.realtimeTock(ClockIndexes.RT_CLOCK_BACKEND);

        (indexed_dlow_1,libs,file_dir,timeSimCode,timeTemplates) =
          generateModelCodeFMU(dlow_1, p, dae,  className, FMUVersion, FMUType, filenameprefix, inSimSettingsOpt);

        //reset config flag
        Flags.setConfigBool(Flags.GENERATE_SYMBOLIC_LINEARIZATION, symbolicJacActivated);

        resultValues =
        {("timeTemplates",Values.REAL(timeTemplates)),
          ("timeSimCode",  Values.REAL(timeSimCode)),
          ("timeBackend",  Values.REAL(timeBackend)),
          ("timeFrontend", Values.REAL(timeFrontend))
          };
          resstr = Absyn.pathStringNoQual(className);
        resstr = stringAppendList({"SimCode: The model ",resstr," has been translated to FMU"});
      then
        (cache,Values.STRING(resstr),st,indexed_dlow_1,libs,file_dir, resultValues);
    case (_,_,_,_,_,_,_,_,_)
      equation
        resstr = Absyn.pathStringNoQual(className);
        resstr = stringAppendList({"SimCode: The model ",resstr," could not be translated to FMU"});
        Error.addMessage(Error.INTERNAL_ERROR, {resstr});
      then
        fail();
  end matchcontinue;
end translateModelFMU;


public function translateModelXML
"Entry point to translate a Modelica model for XML export.

 Called from other places in the compiler."
  input FCore.Cache inCache;
  input FCore.Graph inEnv;
  input Absyn.Path className "path for the model";
  input GlobalScript.SymbolTable inInteractiveSymbolTable;
  input String inFileNamePrefix;
  input Boolean addDummy "if true, add a dummy state";
  input Option<SimCode.SimulationSettings> inSimSettingsOpt;
  output FCore.Cache outCache;
  output Values.Value outValue;
  output GlobalScript.SymbolTable outInteractiveSymbolTable;
  output BackendDAE.BackendDAE outBackendDAE;
  output list<String> outStringLst;
  output String outFileDir;
  output list<tuple<String,Values.Value>> resultValues;
algorithm
  (outCache,outValue,outInteractiveSymbolTable,outBackendDAE,outStringLst,outFileDir,resultValues):=
  matchcontinue (inCache,inEnv,className,inInteractiveSymbolTable,inFileNamePrefix,addDummy, inSimSettingsOpt)
    local
      String filenameprefix,file_dir,resstr,description;
      DAE.DAElist dae;
      FCore.Graph graph;
      BackendDAE.BackendDAE dlow,dlow_1,indexed_dlow_1;
      list<String> libs;
      GlobalScript.SymbolTable st;
      Absyn.Program p;
      //DAE.Exp fileprefix;
      FCore.Cache cache;
      DAE.FunctionTree funcs;
      Real timeSimCode, timeTemplates, timeBackend, timeFrontend;
    case (cache,graph,_,st as GlobalScript.SYMBOLTABLE(ast=p),filenameprefix,_, _)
      equation
        /* calculate stuff that we need to create SimCode data structure */
        System.realtimeTick(ClockIndexes.RT_CLOCK_FRONTEND);
        //(cache,Values.STRING(filenameprefix),SOME(_)) = Ceval.ceval(cache,graph, fileprefix, true, SOME(st),NONE(), msg);
        (cache,graph,dae,st) = CevalScript.runFrontEnd(cache,graph,className,st,false);
        timeFrontend = System.realtimeTock(ClockIndexes.RT_CLOCK_FRONTEND);
        System.realtimeTick(ClockIndexes.RT_CLOCK_BACKEND);
        _ = FCore.getFunctionTree(cache);
        dae = DAEUtil.transformationsBeforeBackend(cache,graph,dae);
        description = DAEUtil.daeDescription(dae);
        dlow = BackendDAECreate.lower(dae, cache, graph, BackendDAE.EXTRA_INFO(description,filenameprefix));
        dlow_1 = BackendDAEUtil.getSolvedSystem(dlow,inFileNamePrefix);
        timeBackend = System.realtimeTock(ClockIndexes.RT_CLOCK_BACKEND);

        (indexed_dlow_1,libs,file_dir,timeSimCode,timeTemplates) =
          generateModelCodeXML(dlow_1, p, dae, className, filenameprefix, inSimSettingsOpt);
        resultValues =
        {("timeTemplates",Values.REAL(timeTemplates)),
          ("timeSimCode",  Values.REAL(timeSimCode)),
          ("timeBackend",  Values.REAL(timeBackend)),
          ("timeFrontend", Values.REAL(timeFrontend))
          };
          resstr = Absyn.pathStringNoQual(className);
        resstr = stringAppendList({"SimCode: The model ",resstr," has been translated to XML"});
      then
        (cache,Values.STRING(resstr),st,indexed_dlow_1,libs,file_dir, resultValues);
    case (_,_,_,_,_,_, _)
      equation
        resstr = Absyn.pathStringNoQual(className);
        resstr = stringAppendList({"SimCode: The model ",resstr," could not be translated to XML"});
        Error.addMessage(Error.INTERNAL_ERROR, {resstr});
      then
        fail();
  end matchcontinue;
end translateModelXML;



public function generateModelCode "
  Generates code for a model by creating a SimCode structure and calling the
  template-based code generator on it."
  input BackendDAE.BackendDAE inBackendDAE;
  input Absyn.Program p;
  input DAE.DAElist dae;
  input Absyn.Path className;
  input String filenamePrefix;
  input Option<SimCode.SimulationSettings> simSettingsOpt;
  input Absyn.FunctionArgs args;
  output BackendDAE.BackendDAE outIndexedBackendDAE;
  output list<String> libs;
  output String fileDir;
  output Real timeSimCode;
  output Real timeTemplates;
protected
  list<String> includes, includeDirs,libPaths;
  list<SimCode.Function> functions;
  SimCode.SimCode simCode;
  list<SimCode.RecordDeclaration> recordDecls;
  Absyn.ComponentRef a_cref;
  tuple<Integer, HashTableExpToIndex.HashTable, list<DAE.Exp>> literals;
algorithm
  if Flags.isSet(Flags.GRAPHML) then
    HpcOmTaskGraph.dumpTaskGraph(inBackendDAE,filenamePrefix);
  end if;
  System.realtimeTick(ClockIndexes.RT_CLOCK_SIMCODE);
  a_cref := Absyn.pathToCref(className);
  fileDir := CevalScript.getFileDir(a_cref, p);
  (libs, libPaths,includes, includeDirs, recordDecls, functions, outIndexedBackendDAE, _, literals) := SimCodeUtil.createFunctions(p, dae, inBackendDAE, className);
  simCode := createSimCode(outIndexedBackendDAE, className, filenamePrefix, fileDir, functions, includes, includeDirs, libs,libPaths, simSettingsOpt, recordDecls, literals, args);
  timeSimCode := System.realtimeTock(ClockIndexes.RT_CLOCK_SIMCODE);
  SimCodeUtil.execStat("SimCode");

  System.realtimeTick(ClockIndexes.RT_CLOCK_TEMPLATES);
  callTargetTemplates(simCode, inBackendDAE, Config.simCodeTarget());
  timeTemplates := System.realtimeTock(ClockIndexes.RT_CLOCK_TEMPLATES);
  SimCodeUtil.execStat("Templates");
end generateModelCode;

protected function createSimCode "
  SimCode generator switch - if the NUMPROC-Flag is set, the simcode will be extended with parallel informations."
  input BackendDAE.BackendDAE inBackendDAE;
  input Absyn.Path inClassName;
  input String filenamePrefix;
  input String inString11;
  input list<SimCode.Function> functions;
  input list<String> externalFunctionIncludes;
  input list<String> includeDirs;
  input list<String> libs;
  input list<String> libPaths;
  input Option<SimCode.SimulationSettings> simSettingsOpt;
  input list<SimCode.RecordDeclaration> recordDecls;
  input tuple<Integer, HashTableExpToIndex.HashTable, list<DAE.Exp>> literals;
  input Absyn.FunctionArgs args;
  output SimCode.SimCode simCode;
algorithm
  simCode := matchcontinue(inBackendDAE, inClassName, filenamePrefix, inString11, functions, externalFunctionIncludes, includeDirs, libs, libPaths,simSettingsOpt, recordDecls, literals, args)
    local
      Integer numProc;
      SimCode.SimCode tmpSimCode;

    case(_, _, _, _, _, _, _, _, _, _,_, _, _) equation
      true = Flags.isSet(Flags.HPCOM);

      // either generate code for profiling or for parallel simulation
      //bcall(not stringEq("none",Flags.getConfigString(Flags.PROFILING_LEVEL)),print,"Deactivate profiling if you want to simulate in parallel.\n");
      //_ = bcallret2((not stringEq("none",Flags.getConfigString(Flags.PROFILING_LEVEL))) and (not stringEq("all_perf",Flags.getConfigString(Flags.PROFILING_LEVEL))),Flags.set,Flags.HPCOM,false,true);
      //true = stringEq("none",Flags.getConfigString(Flags.PROFILING_LEVEL)) or stringEq("all_perf",Flags.getConfigString(Flags.PROFILING_LEVEL));

      numProc = Flags.getConfigInt(Flags.NUM_PROC);
      true = numProc == 0;
      print("hpcom computes the ideal number of processors. If you want to set the number manually, use the flag +n=_ \n");
    then HpcOmSimCodeMain.createSimCode(inBackendDAE, inClassName, filenamePrefix, inString11, functions, externalFunctionIncludes, includeDirs, libs,libPaths, simSettingsOpt, recordDecls, literals, args);

    case(_, _, _, _, _, _, _, _, _,_, _, _, _) equation
      true = Flags.isSet(Flags.HPCOM);

      // either generate code for profiling or for parallel simulation
      //bcall((not stringEq("none",Flags.getConfigString(Flags.PROFILING_LEVEL))) and (not stringEq("all_perf",Flags.getConfigString(Flags.PROFILING_LEVEL))),print,"Deactivate profiling if you want to simulate in parallel.\n");
      //_ = bcallret2(not stringEq("none",Flags.getConfigString(Flags.PROFILING_LEVEL)),Flags.set,Flags.HPCOM,false,true);
      //true = stringEq("none",Flags.getConfigString(Flags.PROFILING_LEVEL)) or stringEq("all_perf",Flags.getConfigString(Flags.PROFILING_LEVEL));

      numProc = Flags.getConfigInt(Flags.NUM_PROC);
      true = (numProc > 0);
    then HpcOmSimCodeMain.createSimCode(inBackendDAE, inClassName, filenamePrefix, inString11, functions, externalFunctionIncludes, includeDirs, libs, libPaths,simSettingsOpt, recordDecls, literals, args);

    else equation
      (tmpSimCode, _) = SimCodeUtil.createSimCode(inBackendDAE, inClassName, filenamePrefix, inString11, functions, externalFunctionIncludes, includeDirs, libs,libPaths, simSettingsOpt, recordDecls, literals, args);
    then tmpSimCode;
  end matchcontinue;
end createSimCode;

// TODO: use another switch ... later make it first class option like -target or so
// Update: inQSSrequiredData passed in order to call BackendQSS and generate the extra structures needed for QSS simulation.
protected function callTargetTemplates "
  Generate target code by passing the SimCode data structure to templates."
  input SimCode.SimCode simCode;
  input BackendDAE.BackendDAE inQSSrequiredData;
  input String target;
algorithm
  _ := match(simCode, inQSSrequiredData, target)
    local
    BackendDAE.BackendDAE outIndexedBackendDAE;
    BackendQSS.QSSinfo qssInfo;
    String str,guid;
    SimCode.SimCode sc;

    case (_, _, "CSharp") equation
      Tpl.tplNoret(CodegenCSharp.translateModel, simCode);
    then ();

    case (_, _, "Cpp") equation
      callTargetTemplatesCPP(simCode);
    then ();

    case (_, _, "Adevs") equation
      Tpl.tplNoret(CodegenAdevs.translateModel, simCode);
    then ();

    case (_, _, "sfmi") equation
      Tpl.tplNoret3(CodegenSparseFMI.translateModel, simCode, "2.0", "me");
    then ();

    case (_, outIndexedBackendDAE, "QSS") equation
      /* as BackendDAE.DAE(eqs={ BackendDAE.EQSYSTEM( m=SOME(incidenceMatrix) , mT=SOME(incidenceMatrixT), matching=BackendDAE.MATCHING(equationIndices, variableIndices, strongComponents)*/
      Debug.trace("Generating code for QSS solver\n");
      (qssInfo, sc) = BackendQSS.generateStructureCodeQSS(outIndexedBackendDAE, simCode); //, equationIndices, variableIndices, incidenceMatrix, incidenceMatrixT, strongComponents, simCode);
      Tpl.tplNoret2(CodegenQSS.translateModel, sc, qssInfo);
    then ();

    case (_, _, "C")
      equation
        guid = System.getUUIDStr();

        System.realtimeTick(ClockIndexes.RT_PROFILER0);
        Tpl.tplNoret2(CodegenC.translateInitFile, simCode, guid);
        // print("SimCode -> init.xml: " + realString(System.realtimeTock(ClockIndexes.RT_PROFILER0)*1000) + "ms\n");
        // System.realtimeTick(ClockIndexes.RT_PROFILER0);
        if Flags.isSet(Flags.MODEL_INFO_JSON) then
          SerializeModelInfo.serialize(simCode, Flags.isSet(Flags.INFO_XML_OPERATIONS));
        else
          Tpl.tplNoret2(SimCodeDump.dumpSimCode, simCode, Flags.isSet(Flags.INFO_XML_OPERATIONS));
        end if;
        dumpTaskSystemIfFlag(simCode);
        // print("SimCode -> info.xml: " + realString(System.realtimeTock(ClockIndexes.RT_PROFILER0)*1000) + "ms\n");
        // System.realtimeTick(ClockIndexes.RT_PROFILER0);
        // print("SimCode -> info.json: " + realString(System.realtimeTock(ClockIndexes.RT_PROFILER0)*1000) + "ms\n");
        Tpl.tplNoret2(CodegenC.translateModel, simCode, guid);
        // print("SimCode -> C-files: " + realString(System.realtimeTock(ClockIndexes.RT_PROFILER0)*1000) + "ms\n");
      then ();

    case (_, _, "JavaScript")
      equation
        guid = System.getUUIDStr();
        Tpl.tplNoret2(CodegenC.translateModel, simCode, guid);
        Tpl.tplNoret2(CodegenC.translateInitFile, simCode, guid);
        Tpl.tplNoret2(SimCodeDump.dumpSimCodeToC, simCode, false);
        Tpl.tplNoret(CodegenJS.markdownFile, simCode);
      then ();

    case (_, _, "XML") equation
      Tpl.tplNoret(CodegenXML.translateModel, simCode);
    then ();

    case (_, _, "Java") equation
      Tpl.tplNoret(CodegenJava.translateModel, simCode);
    then ();

    case (_, _, "None")
    then ();

    case (_, _, _) equation
      str = "Unknown template target: " + target;
      Error.addMessage(Error.INTERNAL_ERROR, {str});
    then fail();
  end match;
end callTargetTemplates;

protected function dumpTaskSystemIfFlag
  input SimCode.SimCode simCode;
algorithm
  if Flags.isSet(Flags.PARMODAUTO) then
    Tpl.tplNoret2(TaskSystemDump.dumpTaskSystem, simCode, Flags.isSet(Flags.INFO_XML_OPERATIONS));
  end if;
end dumpTaskSystemIfFlag;

protected function callTargetTemplatesCPP
  input SimCode.SimCode iSimCode;
algorithm
  if(Flags.isSet(Flags.HPCOM)) then
    Tpl.tplNoret(CodegenCppHpcom.translateModel, iSimCode);
  else
    Tpl.tplNoret(CodegenCpp.translateModel, iSimCode);
  end if;
end callTargetTemplatesCPP;

protected function callTargetTemplatesFMU
"Generate target code by passing the SimCode data structure to templates."
  input SimCode.SimCode simCode;
  input String target;
  input String FMUVersion;
  input String FMUType;
algorithm
  _ := match (simCode,target)
    local
      String str;

    case (SimCode.SIMCODE(),"C")
      algorithm
        if Flags.isSet(Flags.MODEL_INFO_JSON) then
          SerializeModelInfo.serialize(simCode, Flags.isSet(Flags.INFO_XML_OPERATIONS));
          true := System.covertTextFileToCLiteral(simCode.fileNamePrefix+"_info.json", simCode.fileNamePrefix+"_info.c");
        else
          Tpl.tplNoret2(SimCodeDump.dumpSimCodeToC, simCode, false);
        end if;
        Tpl.tplNoret3(CodegenFMU.translateModel, simCode, FMUVersion, FMUType);
      then ();
    case (_,"Cpp")
      equation
        Tpl.tplNoret3(CodegenFMUCpp.translateModel, simCode, FMUVersion, FMUType);
      then ();
    else
      equation
        str = "Unknown FMU template target: " + target;
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then fail();
  end match;
end callTargetTemplatesFMU;


protected function callTargetTemplatesXML
"Generate target code by passing the SimCode data structure to templates."
  input SimCode.SimCode simCode;
  input String target;
algorithm
  Tpl.tplNoret(CodegenXML.translateModel, simCode);
end callTargetTemplatesXML;

public function translateModel "
  Entry point to translate a Modelica model for simulation.
  Called from other places in the compiler."
  input FCore.Cache inCache;
  input FCore.Graph inEnv;
  input Absyn.Path className "path for the model";
  input GlobalScript.SymbolTable inInteractiveSymbolTable;
  input String inFileNamePrefix;
  input Boolean addDummy "if true, add a dummy state";
  input Option<SimCode.SimulationSettings> inSimSettingsOpt;
  input Absyn.FunctionArgs args "labels for remove terms";
  output FCore.Cache outCache;
  output GlobalScript.SymbolTable outInteractiveSymbolTable;
  output BackendDAE.BackendDAE outBackendDAE;
  output list<String> outStringLst;
  output String outFileDir;
  output list<tuple<String, Values.Value>> resultValues;
algorithm
  (outCache, outInteractiveSymbolTable, outBackendDAE, outStringLst, outFileDir, resultValues) :=
  matchcontinue (inCache, inEnv, className, inInteractiveSymbolTable, inFileNamePrefix, addDummy, inSimSettingsOpt, args)
    local
      String filenameprefix, file_dir, resstr, description;
      DAE.DAElist dae;
      FCore.Graph graph;
      BackendDAE.BackendDAE dlow, dlow_1, indexed_dlow_1;
      list<String> libs;
      GlobalScript.SymbolTable st;
      Absyn.Program p;
      //DAE.Exp fileprefix;
      FCore.Cache cache;
      Real timeSimCode, timeTemplates, timeBackend, timeFrontend;

    case (cache, graph, _, (st as GlobalScript.SYMBOLTABLE(ast=p)), filenameprefix, _, _, _) equation
      // calculate stuff that we need to create SimCode data structure
      System.realtimeTick(ClockIndexes.RT_CLOCK_FRONTEND);
      System.realtimeTick(ClockIndexes.RT_CLOCK_EXECSTAT);
      System.realtimeTick(ClockIndexes.RT_CLOCK_EXECSTAT_CUMULATIVE);
      (cache, graph, dae, st) = CevalScript.runFrontEnd(cache, graph, className, st, false);
      SimCodeUtil.execStat("FrontEnd");
      timeFrontend = System.realtimeTock(ClockIndexes.RT_CLOCK_FRONTEND);

      System.realtimeTick(ClockIndexes.RT_CLOCK_BACKEND);
      dae = DAEUtil.transformationsBeforeBackend(cache, graph, dae);
      SimCodeUtil.execStat("Transformations before backend");
      description = DAEUtil.daeDescription(dae);
      dlow = BackendDAECreate.lower(dae, cache, graph, BackendDAE.EXTRA_INFO(description,filenameprefix));
      //BackendDump.printBackendDAE(dlow);
      dlow_1 = BackendDAEUtil.getSolvedSystem(dlow,inFileNamePrefix);
      timeBackend = System.realtimeTock(ClockIndexes.RT_CLOCK_BACKEND);

      (indexed_dlow_1, libs, file_dir, timeSimCode, timeTemplates) =
        generateModelCode(dlow_1, p, dae, className, filenameprefix, inSimSettingsOpt, args);

      resultValues = {("timeTemplates", Values.REAL(timeTemplates)),
                      ("timeSimCode", Values.REAL(timeSimCode)),
                      ("timeBackend", Values.REAL(timeBackend)),
                      ("timeFrontend", Values.REAL(timeFrontend))};
    then (cache, st, indexed_dlow_1, libs, file_dir, resultValues);

    case (_, _, _, _, _, _, _, _) equation
      true = Flags.isSet(Flags.FAILTRACE);
      resstr = Absyn.pathStringNoQual(className);
      resstr = stringAppendList({"SimCode: The model ", resstr, " could not be translated"});
      Error.addMessage(Error.INTERNAL_ERROR, {resstr});
    then fail();
  end matchcontinue;
end translateModel;

public function translateFunctions "
  Entry point to translate Modelica/MetaModelica functions to C functions.
  Called from other places in the compiler."
  input Absyn.Program program;
  input String name;
  input Option<DAE.Function> optMainFunction;
  input list<DAE.Function> idaeElements;
  input list<DAE.Type> metarecordTypes;
  input list<String> inIncludes;
algorithm
  _ := match (program, name, optMainFunction, idaeElements, metarecordTypes, inIncludes)
    local
      DAE.Function daeMainFunction;
      SimCode.Function mainFunction;
      list<SimCode.Function> fns;
      list<String> includes, libs, libPaths,includeDirs;
      SimCode.MakefileParams makefileParams;
      SimCode.FunctionCode fnCode;
      list<SimCode.RecordDeclaration> extraRecordDecls;
      list<DAE.Exp> literals;
      list<DAE.Function> daeElements;

    case (_, _, SOME(daeMainFunction), daeElements, _, includes)
      equation
        // Create SimCode.FunctionCode
        (daeElements,literals) = SimCodeUtil.findLiterals(daeMainFunction::daeElements);
        (mainFunction::fns, extraRecordDecls, includes, includeDirs, libs,libPaths) = SimCodeUtil.elaborateFunctions(program, daeElements, metarecordTypes, literals, includes);
        SimCodeUtil.checkValidMainFunction(name, mainFunction);
        makefileParams = SimCodeUtil.createMakefileParams(includeDirs, libs,libPaths, true);
        fnCode = SimCode.FUNCTIONCODE(name, SOME(mainFunction), fns, literals, includes, makefileParams, extraRecordDecls);
        // Generate code
        _ = Tpl.tplString(CodegenC.translateFunctions, fnCode);
      then
        ();
    case (_, _, NONE(), daeElements, _, includes)
      equation
        // Create SimCode.FunctionCode
        (daeElements,literals) = SimCodeUtil.findLiterals(daeElements);
        (fns, extraRecordDecls, includes, includeDirs, libs,libPaths) = SimCodeUtil.elaborateFunctions(program, daeElements, metarecordTypes, literals, includes);
        makefileParams = SimCodeUtil.createMakefileParams(includeDirs, libs,libPaths, true);
        // remove OpenModelica.threadData.ThreadData
        fns = removeThreadDataFunction(fns, {});
        extraRecordDecls = removeThreadDataRecord(extraRecordDecls, {});

        fnCode = SimCode.FUNCTIONCODE(name, NONE(), fns, literals, includes, makefileParams, extraRecordDecls);
        // Generate code
        _ = Tpl.tplString(CodegenC.translateFunctions, fnCode);
      then
        ();
  end match;
end translateFunctions;

protected function removeThreadDataRecord
"remove OpenModelica.threadData.ThreadData
 as is already defined in openmodelica.h"
  input list<SimCode.RecordDeclaration> inRecs;
  input list<SimCode.RecordDeclaration> inAcc;
  output list<SimCode.RecordDeclaration> outRecs;
algorithm
  outRecs := match(inRecs, inAcc)
    local
      Absyn.Path p;
      list<SimCode.RecordDeclaration> acc, rest;
      SimCode.RecordDeclaration r;

    case ({}, _) then listReverse(inAcc);

    case (SimCode.RECORD_DECL_FULL(name = "OpenModelica_threadData_ThreadData")::rest, _)
     equation
       acc = removeThreadDataRecord(rest, inAcc);
     then
       acc;

    case (SimCode.RECORD_DECL_DEF(path = Absyn.QUALIFIED("OpenModelica",Absyn.QUALIFIED("threadData",Absyn.IDENT("ThreadData"))))::rest, _)
     equation
       acc = removeThreadDataRecord(rest, inAcc);
     then
       acc;

    case (r::rest, _)
     equation
       acc = removeThreadDataRecord(rest, r::inAcc);
     then
       acc;

  end match;
end removeThreadDataRecord;

protected function removeThreadDataFunction
"remove OpenModelica.threadData.ThreadData
 as is already defined in openmodelica.h"
  input list<SimCode.Function> inFuncs;
  input list<SimCode.Function> inAcc;
  output list<SimCode.Function> outFuncs;
algorithm
  outFuncs := match(inFuncs, inAcc)
    local
      Absyn.Path p;
      list<SimCode.Function> acc, rest;
      SimCode.Function f;

    case ({}, _) then listReverse(inAcc);

    case (SimCode.RECORD_CONSTRUCTOR(name = Absyn.FULLYQUALIFIED(Absyn.QUALIFIED("OpenModelica",Absyn.QUALIFIED("threadData",Absyn.IDENT("ThreadData")))))::rest, _)
     equation
       acc = removeThreadDataFunction(rest, inAcc);
     then
       acc;

    case (f::rest, _)
     equation
       acc = removeThreadDataFunction(rest, f::inAcc);
     then
       acc;

  end match;
end removeThreadDataFunction;

public function getCalledFunctionsInFunction
"Goes through the given DAE, finds the given function and collects
  the names of the functions called from within those functions"
  input Absyn.Path path;
  input DAE.FunctionTree funcs;
  output list<Absyn.Path> outPaths;
protected
  HashTableStringToPath.HashTable ht;
algorithm
  ht := HashTableStringToPath.emptyHashTable();
  ht := SimCodeUtil.getCalledFunctionsInFunction2(path,Absyn.pathStringNoQual(path),ht,funcs);
  outPaths := BaseHashTable.hashTableValueList(ht);
end getCalledFunctionsInFunction;

annotation(__OpenModelica_Interface="backend");
end SimCodeMain;
