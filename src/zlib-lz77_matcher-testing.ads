package Zlib.LZ77_Matcher.Testing is
   --  Support level: private internal implementation.
   --  Test seam for the tokenizer's table allocations. It lets the suite
   --  refuse one allocation the way a full heap would and count the tables
   --  still allocated afterwards, so a leak on that path is observable.
   --  Production code never calls it; disarmed, Tokenize pays one Boolean
   --  test per table. Not task-safe: arm it only while no other task
   --  tokenizes.

   procedure Arm (Fail_At : Natural := 0);
   --  Start counting table allocations from zero.
   --  @param Fail_At Allocation number (1-based, counted across Tokenize
   --  calls since arming) that raises Storage_Error; 0 refuses none.

   procedure Disarm;
   --  Stop counting and forget the counts.

   function Attempted return Natural;
   --  Table allocations attempted since Arm, the refused one included.
   --  @return The number of allocations Tokenize attempted while armed.

   function Outstanding return Integer;
   --  Tables allocated while armed and not yet freed.
   --  @return Zero when every table allocated since Arm has been freed.

end Zlib.LZ77_Matcher.Testing;
