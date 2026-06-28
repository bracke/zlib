with AUnit; use AUnit;
with AUnit.Test_Suites; use AUnit.Test_Suites;

package All_Suites is

   function Suite return Access_Test_Suite;
   --  Build and return the AUnit test suite.
   --  @return result produced by Suite

end All_Suites;
