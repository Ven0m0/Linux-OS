#!/usr/bin/bash

sudo -v

sudo java -Xms8192M -Xmx8192M -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+UseG1GC -XX:+AlwaysActAsServerClassMachine -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:NmethodSweepActivity=1 -XX:ReservedCodeCacheSize=400M -XX:NonNMethodCodeHeapSize=12M -XX:ProfiledCodeHeapSize=194M -XX:NonProfiledCodeHeapSize=194M -XX:-DontCompileHugeMethods -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000 -XX:+UseVectorCmov -XX:+PerfDisableSharedMem -XX:+UseFastUnorderedTimeStamps -XX:+UseCriticalJavaThreadPriority -XX:ThreadPriorityPolicy=1 -XX:MaxGCPauseMillis=130 -XX:G1NewSizePercent=28 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=20 -XX:G1MixedGCCountTarget=3 -XX:InitiatingHeapOccupancyPercent=10 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=0 -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 -XX:G1SATBBufferEnqueueingThresholdPercent=30 -XX:G1ConcMarkStepDurationMillis=5.0 -XX:AllocatePrefetchStyle=3 -XX:ConcGCThreads=2 -XX:+UseTransparentHugePages -XX:+UseStringDeduplication -XX:+UseFMA -XX:+ParallelRefProcEnabled -XX:+UseTLAB -XX:+UseCompressedOops -XX:+OptimizeStringConcat -XX:+RangeCheckElimination -XX:+UseLoopPredicate -XX:+OmitStackTraceInFastThrow -XX:+UseNewLongLShift -XX:+UseFPUForSpilling -XX:+EliminateLocks -XX:+OptimizeFill -XX:+EnableVectorSupport -XX:+UseVectorStubs -XX:+UseFastJNIAccessors -XX:+UseInlineCaches -XX:+SegmentedCodeCache -Xlog:none -Dfile.encoding=UTF-8 -XX:+ParallelRefProcEnabled -XX:MaxTenuringThreshold=1 -jar fabric-server.jar --nogui

# -Xlog:none
# -Xlog:async
