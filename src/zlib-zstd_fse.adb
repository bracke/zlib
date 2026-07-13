package body Zlib.Zstd_FSE is

   package Bits renames Zlib.Zstd_Bits;
   package Tables renames Zlib.Zstd_Tables;

   function Table_Step (Size : Natural) return Natural;

   function Table_Step (Size : Natural) return Natural is
   begin
      --  The stride that spreads symbols evenly over the table.
      return Size / 2 + Size / 8 + 3;
   end Table_Step;

   procedure Read_Counts
     (Data      : Byte_Array;
      First     : Natural;
      Max_Code  : Natural;
      Counts    : out Tables.Count_Array;
      Log       : out Natural;
      Last_Code : out Natural;
      Used      : out Natural;
      Status    : out Status_Code)
   is
      R : Bits.Forward_Reader;

      Bit_Width : Natural;
      Remaining : Integer;
      Threshold : Integer;
      Symbol_Id : Natural := 0;
      Previous  : Boolean := False;
      Raw       : Interfaces.Unsigned_32;
   begin
      Counts := [others => 0];
      Log := 0;
      Last_Code := 0;
      Used := 0;
      Status := Ok;

      Bits.Reset (R, First);

      Raw := Bits.Read (R, Data, 4, Status);
      if Status /= Ok then
         return;
      end if;

      Log := Natural (Raw) + 5;
      if Log > Max_Log then
         Status := Invalid_Huffman_Code;
         return;
      end if;

      Remaining := 2 ** Log + 1;
      Threshold := 2 ** Log;
      Bit_Width := Log + 1;

      while Remaining > 1 and then Symbol_Id <= Max_Code loop
         if Previous then
            --  A zero count is followed by a run length of further zeroes, in
            --  units of 24, then 3, then the remainder.
            declare
               Zero_End : Natural := Symbol_Id;
            begin
               while Bits.Peek (R, Data, 16) = 16#FFFF# loop
                  Zero_End := Zero_End + 24;
                  Bits.Skip (R, 16);
               end loop;

               while (Bits.Peek (R, Data, 2) and 3) = 3 loop
                  Zero_End := Zero_End + 3;
                  Bits.Skip (R, 2);
               end loop;

               Zero_End := Zero_End + Natural (Bits.Peek (R, Data, 2) and 3);
               Bits.Skip (R, 2);

               if Zero_End > Max_Code + 1 then
                  Status := Invalid_Huffman_Code;
                  return;
               end if;

               while Symbol_Id < Zero_End loop
                  Counts (Symbol_Id) := 0;
                  Symbol_Id := Symbol_Id + 1;
               end loop;

               Previous := False;
            end;

            exit when Symbol_Id > Max_Code;
         end if;

         declare
            Ceiling : constant Integer :=
              (2 * Threshold - 1) - Remaining;
            Value   : constant Integer :=
              Integer (Bits.Peek (R, Data, Bit_Width));
            Count   : Integer;
         begin
            if (Value mod Threshold) < Ceiling then
               Count := Value mod Threshold;
               Bits.Skip (R, Bit_Width - 1);
            else
               Count := Value mod (2 * Threshold);
               if Count >= Threshold then
                  Count := Count - Ceiling;
               end if;
               Bits.Skip (R, Bit_Width);
            end if;

            --  The wire value is one more than the count, so that -1 can mark a
            --  symbol of less-than-one probability.
            Count := Count - 1;
            Remaining := Remaining - abs Count;

            Counts (Symbol_Id) := Count;
            Symbol_Id := Symbol_Id + 1;
            Previous := Count = 0;

            while Remaining < Threshold loop
               Bit_Width := Bit_Width - 1;
               Threshold := Threshold / 2;
            end loop;
         end;
      end loop;

      if Remaining /= 1 then
         Status := Invalid_Huffman_Code;
         return;
      end if;

      Last_Code := (if Symbol_Id = 0 then 0 else Symbol_Id - 1);
      Used := Bits.Bytes_Used (R, First);
   end Read_Counts;

   procedure Build_Decode
     (Counts : Tables.Count_Array;
      Log    : Natural;
      Table  : out Decode_Table;
      Status : out Status_Code)
   is
      Size      : constant Natural := 2 ** Log;
      Step      : constant Natural := Table_Step (Size);
      High      : Integer := Size - 1;
      Position  : Natural := 0;
      Next_Free : array (0 .. Max_Symbol) of Natural := [others => 0];
   begin
      Table.Log := Log;
      Table.Entries := [others => (0, 0, 0)];
      Status := Ok;

      --  Low-probability symbols get one slot each, taken from the top.
      for Code in Counts'Range loop
         if Counts (Code) = -1 then
            if High < 0 then
               Status := Invalid_Huffman_Code;
               return;
            end if;
            Table.Entries (Natural (High)).Symbol := Code;
            Next_Free (Code) := 1;
            High := High - 1;
         else
            Next_Free (Code) := Natural'Max (Counts (Code), 0);
         end if;
      end loop;

      --  Spread the rest with the stride, stepping over the reserved top slots.
      for Code in Counts'Range loop
         if Counts (Code) > 0 then
            for Unused_Index in 1 .. Counts (Code) loop
               Table.Entries (Position).Symbol := Code;
               loop
                  Position := (Position + Step) mod Size;
                  exit when High < 0 or else Position <= Natural (High);
               end loop;
            end loop;
         end if;
      end loop;

      --  Give each slot the bit count and successor state its symbol implies.
      for Slot in 0 .. Size - 1 loop
         declare
            Code  : constant Natural := Table.Entries (Slot).Symbol;
            Taken : constant Natural := Next_Free (Code);
            Width : Natural;
         begin
            if Taken = 0 then
               Status := Invalid_Huffman_Code;
               return;
            end if;

            Next_Free (Code) := Taken + 1;
            Width := Log - Tables.Highest_Bit (Taken);
            Table.Entries (Slot).Bits := Width;
            Table.Entries (Slot).Next_State :=
              (Taken * 2 ** Width) - Size;
         end;
      end loop;
   end Build_Decode;

   procedure Init_Decode
     (Table  : Decode_Table;
      R      : in out Bits.Backward_Reader;
      Data   : Byte_Array;
      State  : out Natural;
      Status : out Status_Code)
   is
      Raw : constant Interfaces.Unsigned_32 :=
        Bits.Read (R, Data, Table.Log, Status);
   begin
      State := Natural (Raw);
   end Init_Decode;

   function Symbol (Table : Decode_Table; State : Natural) return Natural is
   begin
      return Table.Entries (State).Symbol;
   end Symbol;

   procedure Advance
     (Table  : Decode_Table;
      R      : in out Bits.Backward_Reader;
      Data   : Byte_Array;
      State  : in out Natural;
      Status : out Status_Code)
   is
      Width : constant Natural := Table.Entries (State).Bits;
      Base  : constant Natural := Table.Entries (State).Next_State;
      Raw   : Interfaces.Unsigned_32;
   begin
      Raw := Bits.Read (R, Data, Width, Status);
      if Status /= Ok then
         return;
      end if;
      State := Base + Natural (Raw);
   end Advance;

   procedure Advance_Padded
     (Table : Decode_Table;
      R     : in out Bits.Backward_Reader;
      Data  : Byte_Array;
      State : in out Natural)
   is
      Width : constant Natural := Table.Entries (State).Bits;
      Base  : constant Natural := Table.Entries (State).Next_State;
      Raw   : constant Interfaces.Unsigned_32 :=
        Bits.Read_Padded (R, Data, Width);
   begin
      State := Base + Natural (Raw);
   end Advance_Padded;

   procedure Build_Encode
     (Counts : Tables.Count_Array;
      Log    : Natural;
      Table  : out Encode_Table;
      Status : out Status_Code)
   is
      Size     : constant Natural := 2 ** Log;
      Step     : constant Natural := Table_Step (Size);
      High     : Integer := Size - 1;
      Position : Natural := 0;

      subtype Cumulative_Array is Zlib.Zstd_Tables.Value_Array (0 .. Max_Symbol + 1);

      Spread : array (0 .. Max_Table - 1) of Natural := [others => 0];
      Cumul  : Cumulative_Array := [others => 0];
      Total  : Natural := 0;
   begin
      Table.Log := Log;
      Table.States := [others => 0];
      Table.Transform := [others => (0, 0)];
      Status := Ok;

      for Code in Counts'Range loop
         if Counts (Code) = -1 then
            if High < 0 then
               Status := Invalid_Huffman_Code;
               return;
            end if;
            Spread (Natural (High)) := Code;
            High := High - 1;
         end if;
      end loop;

      for Code in Counts'Range loop
         if Counts (Code) > 0 then
            for Unused_Index in 1 .. Counts (Code) loop
               Spread (Position) := Code;
               loop
                  Position := (Position + Step) mod Size;
                  exit when High < 0 or else Position <= Natural (High);
               end loop;
            end loop;
         end if;
      end loop;

      --  Cumulative starts, so each symbol's states land in its own run.
      Cumul (0) := 0;
      for Code in Counts'Range loop
         Cumul (Code + 1) :=
           Cumul (Code) + (if Counts (Code) = -1 then 1
                           else Natural'Max (Counts (Code), 0));
      end loop;

      declare
         Fill : Cumulative_Array := Cumul;
      begin
         for Slot in 0 .. Size - 1 loop
            declare
               Code : constant Natural := Spread (Slot);
            begin
               Table.States (Fill (Code)) := Size + Slot;
               Fill (Code) := Fill (Code) + 1;
            end;
         end loop;
      end;

      for Code in Counts'Range loop
         case Counts (Code) is
            when 0 =>
               Table.Transform (Code) :=
                 (Delta_Bits  => (Log + 1) * 2 ** 16 - Size,
                  Delta_State => 0);

            when -1 | 1 =>
               Table.Transform (Code) :=
                 (Delta_Bits  => Log * 2 ** 16 - Size,
                  Delta_State => Total - 1);
               Total := Total + 1;

            when others =>
               declare
                  Count : constant Natural := Counts (Code);
                  Width : constant Natural :=
                    Log - Tables.Highest_Bit (Count - 1);
                  Floor : constant Natural := Count * 2 ** Width;
               begin
                  Table.Transform (Code) :=
                    (Delta_Bits  => Width * 2 ** 16 - Floor,
                     Delta_State => Total - Count);
                  Total := Total + Count;
               end;
         end case;
      end loop;
   end Build_Encode;

   function Log_Of (Table : Encode_Table) return Natural is
   begin
      return Table.Log;
   end Log_Of;

   procedure Init_Encode
     (Table  : Encode_Table;
      Symbol : Natural;
      State  : out Natural;
      W      : in out Bits.Backward_Writer)
   is
      pragma Unreferenced (W);
      Transform : constant Transform_Record := Table.Transform (Symbol);
      Width     : constant Natural :=
        Natural ((Transform.Delta_Bits + 2 ** 15) / 2 ** 16);
      Value     : constant Integer :=
        Width * 2 ** 16 - Transform.Delta_Bits;
   begin
      State :=
        Table.States (Natural (Value / 2 ** Width) + Transform.Delta_State);
   end Init_Encode;

   procedure Encode
     (Table  : Encode_Table;
      Symbol : Natural;
      State  : in out Natural;
      W      : in out Bits.Backward_Writer)
   is
      Transform : constant Transform_Record := Table.Transform (Symbol);
      Width     : constant Natural :=
        Natural ((State + Transform.Delta_Bits) / 2 ** 16);
   begin
      Bits.Write (W, Interfaces.Unsigned_32 (State), Width);
      State :=
        Table.States (State / 2 ** Width + Transform.Delta_State);
   end Encode;

   procedure Flush_Encode
     (Table : Encode_Table;
      State : Natural;
      W     : in out Bits.Backward_Writer) is
   begin
      Bits.Write
        (W, Interfaces.Unsigned_32 (State - 2 ** Table.Log), Table.Log);
   end Flush_Encode;

   procedure Normalize
     (Frequencies : Tables.Value_Array;
      Total       : Natural;
      Max_Code    : Natural;
      Log         : Natural;
      Counts      : out Tables.Count_Array;
      Status      : out Status_Code)
   is
      Size      : constant Natural := 2 ** Log;
      Remaining : Integer := Size;
      Largest   : Natural := 0;
      Largest_C : Integer := 0;
   begin
      Counts := [others => 0];
      Status := Ok;

      if Total = 0 then
         Status := Invalid_Huffman_Code;
         return;
      end if;

      for Code in 0 .. Max_Code loop
         if Frequencies (Code) = 0 then
            Counts (Code) := 0;
         else
            declare
               Scaled : Integer :=
                 Integer ((Frequencies (Code) * Size) / Total);
            begin
               --  Every symbol that occurs must get at least one slot, or the
               --  decoder could never emit it.
               if Scaled = 0 then
                  Scaled := 1;
               end if;
               Counts (Code) := Scaled;
               Remaining := Remaining - Scaled;

               if Scaled > Largest_C then
                  Largest_C := Scaled;
                  Largest := Code;
               end if;
            end;
         end if;
      end loop;

      if Remaining < 0 then
         --  Over-allocated by the round-ups: take it back off the commonest
         --  symbol, where one slot matters least.
         Counts (Largest) := Counts (Largest) + Remaining;
         if Counts (Largest) < 1 then
            Status := Invalid_Huffman_Code;
            return;
         end if;
      elsif Remaining > 0 then
         Counts (Largest) := Counts (Largest) + Remaining;
      end if;
   end Normalize;

   procedure Write_Counts
     (Counts   : Tables.Count_Array;
      Log      : Natural;
      Max_Code : Natural;
      Output   : out Byte_Array;
      Length   : out Natural;
      Status   : out Status_Code)
   is
      Bit_Store : array (0 .. 4_095) of Boolean := [others => False];
      Bit_Count : Natural := 0;

      procedure Put (Value : Natural; Width : Natural);

      procedure Put (Value : Natural; Width : Natural) is
      begin
         for Index in 0 .. Width - 1 loop
            Bit_Store (Bit_Count) := (Value / 2 ** Index) mod 2 = 1;
            Bit_Count := Bit_Count + 1;
         end loop;
      end Put;

      Remaining : Integer := 2 ** Log + 1;
      Threshold : Integer := 2 ** Log;
      Bit_Width : Natural := Log + 1;
      Code      : Natural := 0;
      Previous  : Boolean := False;
   begin
      Output := [others => 0];
      Length := 0;
      Status := Ok;

      Put (Log - 5, 4);

      while Remaining > 1 and then Code <= Max_Code loop
         if Previous then
            --  Emit the run of zero counts that follows a zero.
            declare
               Run : Natural := 0;
            begin
               while Code + Run <= Max_Code
                 and then Counts (Code + Run) = 0
               loop
                  Run := Run + 1;
               end loop;

               while Run >= 24 loop
                  Put (16#FFFF#, 16);
                  Run := Run - 24;
                  Code := Code + 24;
               end loop;

               while Run >= 3 loop
                  Put (3, 2);
                  Run := Run - 3;
                  Code := Code + 3;
               end loop;

               Put (Run, 2);
               Code := Code + Run;
               Previous := False;
            end;

            exit when Code > Max_Code;
         end if;

         declare
            Ceiling : constant Integer := (2 * Threshold - 1) - Remaining;
            Count   : constant Integer := Counts (Code);
            Wire    : Integer := Count + 1;
         begin
            if Count = -1 then
               Wire := 0;
            end if;

            --  Values below the ceiling fit in one bit fewer. Values at or above
            --  the threshold are pushed up by the ceiling, which is the gap the
            --  short encoding leaves behind.
            if Wire < Ceiling then
               Put (Natural (Wire), Bit_Width - 1);
            else
               if Wire >= Threshold then
                  Wire := Wire + Ceiling;
               end if;
               Put (Natural (Wire), Bit_Width);
            end if;

            Remaining := Remaining - abs Count;
            Previous := Count = 0;
            Code := Code + 1;

            while Remaining < Threshold loop
               Bit_Width := Bit_Width - 1;
               Threshold := Threshold / 2;
            end loop;
         end;
      end loop;

      Length := (Bit_Count + 7) / 8;
      if Length > Output'Length then
         Status := Invalid_Huffman_Code;
         Length := 0;
         return;
      end if;

      for Index in 0 .. Bit_Count - 1 loop
         if Bit_Store (Index) then
            Output (Output'First + Index / 8) :=
              Output (Output'First + Index / 8)
              or Byte (2 ** (Index mod 8));
         end if;
      end loop;
   end Write_Counts;

end Zlib.Zstd_FSE;
