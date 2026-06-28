with AUnit.Test_Cases;

package Zlib_Seven_Zip_Tests is
   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String;
   --  Return the AUnit display name for this test case.
   --  @param T T argument supplied to Name
   --  @return result produced by Name

   overriding procedure Register_Tests
     (T : in out Test_Case);
   --  Register this test case's AUnit routines.
   --  @param T T argument supplied to Register_Tests

end Zlib_Seven_Zip_Tests;
