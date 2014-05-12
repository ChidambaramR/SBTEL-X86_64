SBTEL-X86_64
============

Functional core for reduced X86_64 Instruction Set.
    (This is a 60 Points Project Submission)

High level design details:
--------------------------

       ---------------------------------------------------------
      |                           Core                          |
      | Fetch <-> Decode <-> MemStage <-> Execute <-> Writeback |
       ---------------------------------------------------------
                    ^                              ^                          
                    |                              |
             <ICoreCacheBus>                <DCoreCacheBus>
                    |                              |
                    v                              v
         -----------------------        -----------------------
        |  ICache 32K (512x512) |      |  DCache 32K (512x512) |
        |  4-Way Set Ass Cache  |      |  4-Way Set Ass Cache  |
         -----------------------        -----------------------
                    ^                              ^ 
                    |                              |
           <ICacheArbiterBus>              <DCacheArbiterBus>
                    |                              | 
                    |     ------------------       |
                    ---->|      Arbiter     |<------
                          ------------------
                                   ^
                                   |
                               <Sysbus>
                                   |
                                   v
                          ------------------ 
                         |       DRAM       |
                          ------------------


Performance Results:
--------------------
    Following are the Performance Results of running "prog2" for different Inputs:

    Input Arg        Value              Cycles
   ---------------------------------------------
        2           3.15                86772
        3           3.1417              172158
        5           3.141593            259164
        8           3.14159267          399696
        10          3.1415926538        534672
        12          3.141592653592      710418
        15          3.1415926535897934  1109214

