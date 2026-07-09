with Interfaces;

package body Zlib.LZMA_Match_Finder is
   use type Interfaces.Unsigned_32;

   function Hash3 (Plain : Byte_Array; I : Natural) return Natural is
      V : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Plain (I))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Plain (I + 1)), 8)
        or Interfaces.Shift_Left
             (Interfaces.Unsigned_32 (Plain (I + 2)), 16);
   begin
      return Natural
        (Interfaces.Shift_Right (V * 16#9E37_79B1#, 32 - Hash_Bits));
   end Hash3;

   procedure Insert
     (Plain : Byte_Array;
      Head  : in out Pos_Table;
      Chain : in out Pos_Table;
      I     : Natural)
   is
   begin
      if I + 2 <= Plain'Last then
         declare
            H : constant Natural := Hash3 (Plain, I);
            S : constant Natural := I - Plain'First + 1;
         begin
            Chain (S) := Head (H);
            Head (H) := S;
         end;
      end if;
   end Insert;

   function Match_Length
     (Plain : Byte_Array;
      I     : Natural;
      D     : Natural) return Natural
   is
      L : Natural := 0;
   begin
      while I + L <= Plain'Last and then L < Max_Match
        and then Plain (I + L) = Plain (I + L - D)
      loop
         L := L + 1;
      end loop;
      return L;
   end Match_Length;

   procedure Find_All_Matches
     (Plain   : Byte_Array;
      Head    : Pos_Table;
      Chain   : Pos_Table;
      I       : Natural;
      Dict_Sz : Natural;
      Count   : out Natural;
      Lens    : out Len_Array;
      Dists   : out Len_Array)
   is
      I_Pos : constant Natural := I - Plain'First;
      Cur   : Natural;
      Depth : Natural := 0;
      Steps : Natural := 0;
      Best  : Natural := 0;
   begin
      Count := 0;
      Lens  := [others => 0];
      Dists := [others => 0];
      if I + 2 > Plain'Last then
         return;
      end if;

      Cur := Head (Hash3 (Plain, I));
      while Cur /= 0
        and then Depth < Max_Chain
        and then Steps < Max_Seg_Len + Max_Chain
      loop
         declare
            Candidate_Pos : constant Natural := Cur - 1;
         begin
            if Candidate_Pos < I_Pos then
               declare
                  D : constant Natural := I_Pos - Candidate_Pos;
               begin
                  exit when D > Dict_Sz;
                  declare
                     L : constant Natural := Match_Length (Plain, I, D);
                  begin
                     if L > Best then
                        Best := L;
                        if Count < Max_Pairs then
                           Count := Count + 1;
                           Lens (Count) := L;
                           Dists (Count) := D;
                        end if;
                        exit when L >= Nice_Len;
                     end if;
                  end;
               end;
               Depth := Depth + 1;
            end if;
         end;
         Cur := Chain (Cur);
         Steps := Steps + 1;
      end loop;
   end Find_All_Matches;

   function Longest_Match_From
     (Plain   : Byte_Array;
      Head    : Pos_Table;
      Chain   : Pos_Table;
      I       : Natural;
      Dict_Sz : Natural) return Natural
   is
      I_Pos : constant Natural := I - Plain'First;
      Cur   : Natural;
      Depth : Natural := 0;
      Steps : Natural := 0;
      Best  : Natural := 0;
   begin
      if I + 2 > Plain'Last then
         return 0;
      end if;

      Cur := Head (Hash3 (Plain, I));
      while Cur /= 0
        and then Depth < Max_Chain
        and then Steps < Max_Seg_Len + Max_Chain
      loop
         declare
            Candidate_Pos : constant Natural := Cur - 1;
         begin
            if Candidate_Pos < I_Pos then
               declare
                  D : constant Natural := I_Pos - Candidate_Pos;
               begin
                  exit when D > Dict_Sz;
                  Best := Natural'Max (Best, Match_Length (Plain, I, D));
                  exit when Best >= Nice_Len;
               end;
               Depth := Depth + 1;
            end if;
         end;
         Cur := Chain (Cur);
         Steps := Steps + 1;
      end loop;

      return Best;
   end Longest_Match_From;

   procedure Insert_Range
     (Plain     : Byte_Array;
      Head      : in out Pos_Table;
      Chain     : in out Pos_Table;
      First_Pos : Natural;
      Count     : Natural)
   is
   begin
      if Count > 0 then
         for Offset in reverse 0 .. Count - 1 loop
            Insert (Plain, Head, Chain, First_Pos + Offset);
         end loop;
      end if;
   end Insert_Range;

   procedure Prepare_Adaptive_Segment
     (Plain   : Byte_Array;
      Head    : in out Pos_Table;
      Chain   : in out Pos_Table;
      Cur     : Natural;
      Dict_Sz : Natural;
      Span    : in out Natural)
   is
      Max_Remaining : constant Natural :=
        Natural'Min (Max_Seg_Len, Plain'Last - Cur + 1);
      Inserted : Natural := Span;
      Scan     : Natural := 0;
   begin
      Insert_Range (Plain, Head, Chain, Cur, Span);

      while Scan < Span loop
         declare
            L : constant Natural :=
              Longest_Match_From (Plain, Head, Chain, Cur + Scan, Dict_Sz);
         begin
            if L >= Nice_Len and then Scan + L > Span then
               declare
                  New_Span : constant Natural :=
                    Natural'Min (Max_Remaining, Scan + L);
               begin
                  if New_Span > Inserted then
                     Insert_Range
                       (Plain, Head, Chain, Cur + Inserted,
                        New_Span - Inserted);
                     Inserted := New_Span;
                     Span := New_Span;
                  end if;
               end;
            end if;
         end;
         Scan := Scan + 1;
      end loop;
   end Prepare_Adaptive_Segment;

end Zlib.LZMA_Match_Finder;
