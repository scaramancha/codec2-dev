
This is the unittest system for the stm32 implementation of codec2/FreeDV

Objectives:

   It is important to have a robust set of tests for the functionality
   of any software project, especially when there are multiple developers.

   It is easier to test small units of code first as stand alone functions.

   The more automated the test system is the easier it is to run and thus
   the more likely people are to run it.


Directory Structure:

   scripts     Where scripts for this unittest system are found

   lib         Where includable files for this unittest system are found
      /python     python library files
      /octave     octave library files

   test_run    Each test is run in a subdirectory here.


Test Run Scripts:

   The basics of running each test are included as comments in the test's
   source code.  However some test code is used be multiple tests and 
   some tests have several actions to setup their data or check their
   output.  So there are scripts to run these tests.

   For example "run_tst_ofdm_demod_ideal" (in the scripts directory).

   These scripts use some common options:

       --clean     Clean out the test run directory (delete it and re-create)
       --setup     Create input files.
       --run       Run the test
       --check     Create reference data and check test output.

   If none of these options are given, then all of the steps will be 
   run, in order.


Debug and semihosting:

   These tests use a newer version of the st-util program.
   This one supports the newer boards but also does semihosting differently.
   It needs a command line option to turn on semihosting.

   The source can be downloaded from"

       https://github.com/texane/stlink

   After compiling it can be installed anywhere.  The program is in
   build/Release/src/gdbserver/st-util.

   This program needs to be run from the active test directory.

       cd tests_run/tst_ofdm_demod_ideal
       st-util --semihosting

   The target program can then access files in this directory.

   These tests will read "stm_in.raw", and write "stm_out.raw".
   Their stdout and stderr streams will go to "stm_stdout.txt" and "stm_stderr.txt".

   A file ":tt" will get created by the default initialzation but should be empty.

   The newlib stdio functions (open, fread, fwrite, flush, fclose, etc.) send
   some requests that this tool does not recognize and those messages will appear
   in the output of st-util.  They can be ignored.


QuickStart (TODO: David & Don work together to complete this section)
---------------------------------------------------------------------

1/ Build stlink:

  $ cd ~
  $ git clone https://github.com/texane/stlink
  $ cd stlink
  $ make

2/ Build unittests:

  $ cd codec2-dev/stm32/unittest
  $ unzip ~/Downloads/en.stm32f4_dsp_stdperiph_lib.zip
  (TODO: how to handle different STM32F4xx_DSP_StdPeriph_Lib versions)
  $ make
  
3/ Plug in a Discovery (or other suitable stm32 board).  You need two open
   terminals.  In the first terminal start st-util:

     $ cd tests_run/tst_ofdm_demod_ideal
     $ sudo ~/stlink/build/Release/src/gdbserver/st-util --semihosting

   In the second terminal configure and run the unittest:
   
     $ cd codec2-dev/stm32/unittest
     $ ./scripts/tst_ofdm_demod_setup ideal
     $ (TODO: commands to start and run test in gdb)
     $ ./scripts/tst_ofdm_demod_check ideal

   The check script will print information on each check.
   The final line should be "Test PASSED".  If any of the checks fail
   then it will be "Test FAILED".

   The checks are:

     * BER - Do the reported bit error numbers and rates match?
     * Output - Do the output bits match (as well as expected for each test)?
     * Symbols - Do the Symbols and such match closely (from debug outputs)?

   The check script also translates the target data into octave
   format in the file "ofdm_demod_log.txt" which goes with the
   reference file "ofdm_demod_ref_log.txt".  These files can be
   loaded into octave for debugging and analisys.  There is a file in
   unittest/lib/octave/ofdm_demod_check.m which may be useful.


# vi:set ts=3 et sts=3: