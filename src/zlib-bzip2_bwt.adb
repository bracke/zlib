with Ada.Unchecked_Deallocation;

package body Zlib.BZip2_BWT is

   type Index_Array is array (Natural range <>) of Natural;
   type Index_Access is access Index_Array;
   procedure Free is new Ada.Unchecked_Deallocation (Index_Array, Index_Access);

   procedure Transform
     (Block    : Byte_Array;
      Last     : out Byte_Array;
      Orig_Ptr : out Natural)
   is
      N : constant Positive := Block'Length;

      --  Order holds the rotation starts in sorted order; Rank the equivalence
      --  class of each rotation under the prefix compared so far.
      Order   : Index_Access := new Index_Array (0 .. N - 1);
      Rank    : Index_Access := new Index_Array (0 .. N - 1);
      Next    : Index_Access := new Index_Array (0 .. N - 1);
      Shifted : Index_Access := new Index_Array (0 .. N - 1);

      Classes : Natural;
      Step    : Natural;

      function At_Index (Offset : Natural) return Byte is
        (Block (Block'First + Offset));

   begin
      --  Initial pass: counting sort on the first byte.
      declare
         Count : array (0 .. 255) of Natural := [others => 0];
         Start : Natural := 0;
      begin
         for Index in 0 .. N - 1 loop
            Count (Natural (At_Index (Index))) :=
              Count (Natural (At_Index (Index))) + 1;
         end loop;

         for Value in Count'Range loop
            declare
               Here : constant Natural := Count (Value);
            begin
               Count (Value) := Start;
               Start := Start + Here;
            end;
         end loop;

         for Index in 0 .. N - 1 loop
            Order (Count (Natural (At_Index (Index)))) := Index;
            Count (Natural (At_Index (Index))) :=
              Count (Natural (At_Index (Index))) + 1;
         end loop;
      end;

      Rank (Order (0)) := 0;
      Classes := 1;
      for Index in 1 .. N - 1 loop
         if At_Index (Order (Index)) /= At_Index (Order (Index - 1)) then
            Classes := Classes + 1;
         end if;
         Rank (Order (Index)) := Classes - 1;
      end loop;

      --  Double the compared prefix until every rotation is in its own class.
      Step := 1;
      while Classes < N loop
         --  Order by the second half, by shifting the current order left.
         for Index in 0 .. N - 1 loop
            if Order (Index) >= Step then
               Shifted (Index) := Order (Index) - Step;
            else
               Shifted (Index) := Order (Index) + N - Step;
            end if;
         end loop;

         --  Stable counting sort by the first half's class.
         declare
            Count : Index_Array (0 .. Classes - 1) := [others => 0];
            Start : Natural := 0;
         begin
            for Index in 0 .. N - 1 loop
               Count (Rank (Shifted (Index))) :=
                 Count (Rank (Shifted (Index))) + 1;
            end loop;

            for Value in Count'Range loop
               declare
                  Here : constant Natural := Count (Value);
               begin
                  Count (Value) := Start;
                  Start := Start + Here;
               end;
            end loop;

            for Index in 0 .. N - 1 loop
               Order (Count (Rank (Shifted (Index)))) := Shifted (Index);
               Count (Rank (Shifted (Index))) :=
                 Count (Rank (Shifted (Index))) + 1;
            end loop;
         end;

         --  Re-class on the doubled prefix.
         Next (Order (0)) := 0;
         Classes := 1;
         for Index in 1 .. N - 1 loop
            declare
               Current  : constant Natural := Order (Index);
               Previous : constant Natural := Order (Index - 1);
               Current_Half  : constant Natural :=
                 Rank ((Current + Step) mod N);
               Previous_Half : constant Natural :=
                 Rank ((Previous + Step) mod N);
            begin
               if Rank (Current) /= Rank (Previous)
                 or else Current_Half /= Previous_Half
               then
                  Classes := Classes + 1;
               end if;
               Next (Current) := Classes - 1;
            end;
         end loop;

         Rank.all := Next.all;

         exit when Step > N;
         Step := Step * 2;
      end loop;

      --  Last column: the byte before each sorted rotation's start.
      Orig_Ptr := 0;
      for Index in 0 .. N - 1 loop
         if Order (Index) = 0 then
            Orig_Ptr := Index;
            Last (Last'First + Index) := At_Index (N - 1);
         else
            Last (Last'First + Index) := At_Index (Order (Index) - 1);
         end if;
      end loop;

      Free (Order);
      Free (Rank);
      Free (Next);
      Free (Shifted);

   exception
      when others =>
         Free (Order);
         Free (Rank);
         Free (Next);
         Free (Shifted);
         raise;
   end Transform;

end Zlib.BZip2_BWT;
