package body Zlib.LZMA_Parser is

   procedure Backtrack
     (Opt   : Opt_Array;
      Span  : Natural;
      Ops   : out Op_Array;
      Count : out Natural)
   is
      J : Natural := Span;
   begin
      Count := 0;
      while J > 0 loop
         Count := Count + 1;
         Ops (Ops'First + Count - 1) :=
           (Opt (J).Kind, Opt (J).Dist, Opt (J).Len, Opt (J).Rep_Idx);
         J := Opt (J).From;
      end loop;
   end Backtrack;

end Zlib.LZMA_Parser;
