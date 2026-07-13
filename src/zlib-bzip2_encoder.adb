with Ada.Unchecked_Deallocation;

with Interfaces;

with Zlib.BZip2_Bit_Writer;
with Zlib.BZip2_BWT;
with Zlib.BZip2_CRC;
with Zlib.BZip2_Lengths;

package body Zlib.BZip2_Encoder is

   package Writer renames Zlib.BZip2_Bit_Writer;

   Group_Size : constant Natural := 50;
   Max_Groups : constant Natural := 6;
   Iterations : constant Natural := 4;
   Run_A      : constant Natural := 0;
   Run_B      : constant Natural := 1;

   --  Seed costs for the initial table split: a symbol a table "owns" is free,
   --  anything else is dear, so the first refinement pass has a gradient to
   --  follow.
   Lesser_Cost  : constant Natural := 0;
   Greater_Cost : constant Natural := 15;

   Max_Run : constant Natural := 255;
   --  Longest run the initial run-length coding can express: four literals plus
   --  a count byte of 251.

   Block_Magic_High : constant Interfaces.Unsigned_32 := 16#31_4159#;
   Block_Magic_Low  : constant Interfaces.Unsigned_32 := 16#26_5359#;
   End_Magic_High   : constant Interfaces.Unsigned_32 := 16#17_7245#;
   End_Magic_Low    : constant Interfaces.Unsigned_32 := 16#38_5090#;

   type Symbol_Buffer is array (Natural range <>) of Natural;
   type Symbol_Buffer_Access is access Symbol_Buffer;
   procedure Free is
     new Ada.Unchecked_Deallocation (Symbol_Buffer, Symbol_Buffer_Access);

   type Byte_Buffer_Access is access Byte_Array;
   procedure Free is
     new Ada.Unchecked_Deallocation (Byte_Array, Byte_Buffer_Access);

   subtype Alphabet_Range is Natural range 0 .. 257;
   type Group_Lengths is array (Alphabet_Range) of Natural;
   type Group_Codes is array (Alphabet_Range) of Interfaces.Unsigned_32;
   type Group_Frequencies is array (Alphabet_Range) of Natural;

   type Length_Set is array (0 .. Max_Groups - 1) of Group_Lengths;
   type Code_Set is array (0 .. Max_Groups - 1) of Group_Codes;
   type Frequency_Set is array (0 .. Max_Groups - 1) of Group_Frequencies;

   function Group_Count (Symbols : Natural) return Natural;

   procedure Encode_Block
     (W         : in out Writer.Writer;
      Block     : Byte_Array;
      Block_CRC : Interfaces.Unsigned_32;
      Status    : out Status_Code);

   function Group_Count (Symbols : Natural) return Natural is
   begin
      --  bzip2's thresholds: more tables only pay for themselves once there are
      --  enough symbols to amortise their code-length headers.
      if Symbols < 200 then
         return 2;
      elsif Symbols < 600 then
         return 3;
      elsif Symbols < 1_200 then
         return 4;
      elsif Symbols < 2_400 then
         return 5;
      else
         return 6;
      end if;
   end Group_Count;

   procedure Encode_Block
     (W         : in out Writer.Writer;
      Block     : Byte_Array;
      Block_CRC : Interfaces.Unsigned_32;
      Status    : out Status_Code)
   is
      N : constant Positive := Block'Length;

      Last     : Byte_Buffer_Access := new Byte_Array (0 .. N - 1);
      Mtf      : Symbol_Buffer_Access := new Symbol_Buffer (0 .. N + 1);
      Selector : Symbol_Buffer_Access :=
        new Symbol_Buffer (0 .. (N / Group_Size) + 2);

      Orig_Ptr : Natural := 0;

      In_Use       : array (0 .. 255) of Boolean := [others => False];
      Unseq_To_Seq : array (0 .. 255) of Natural := [others => 0];
      N_In_Use     : Natural := 0;

      Alpha_Size : Natural := 0;
      End_Symbol : Natural := 0;
      N_Mtf      : Natural := 0;

      Mtf_Freq : Group_Frequencies := [others => 0];
      Lengths  : Length_Set := [others => [others => 0]];
      Codes    : Code_Set := [others => [others => 0]];

      N_Groups    : Natural := 0;
      N_Selectors : Natural := 0;

      procedure Cleanup;

      procedure Cleanup is
      begin
         Free (Last);
         Free (Mtf);
         Free (Selector);
      end Cleanup;

   begin
      Status := Ok;

      --  Burrows-Wheeler: sort the rotations, keep the last column.
      Zlib.BZip2_BWT.Transform (Block, Last.all, Orig_Ptr);

      for Index in Last'Range loop
         In_Use (Natural (Last (Index))) := True;
      end loop;

      for Value in In_Use'Range loop
         if In_Use (Value) then
            Unseq_To_Seq (Value) := N_In_Use;
            N_In_Use := N_In_Use + 1;
         end if;
      end loop;

      Alpha_Size := N_In_Use + 2;
      End_Symbol := Alpha_Size - 1;

      --  Move-to-front, with runs of the front symbol coded as RUNA/RUNB in a
      --  bijective base two -- which is why move-to-front position 0 has no
      --  symbol of its own.
      declare
         Order   : array (0 .. 255) of Natural := [others => 0];
         Pending : Natural := 0;
         Value   : Natural;
         Found   : Natural;

         procedure Flush_Pending;

         procedure Flush_Pending is
            Count : Natural := Pending;
         begin
            if Count = 0 then
               return;
            end if;

            Count := Count - 1;
            loop
               if Count mod 2 = 1 then
                  Mtf (N_Mtf) := Run_B;
                  Mtf_Freq (Run_B) := Mtf_Freq (Run_B) + 1;
               else
                  Mtf (N_Mtf) := Run_A;
                  Mtf_Freq (Run_A) := Mtf_Freq (Run_A) + 1;
               end if;
               N_Mtf := N_Mtf + 1;

               exit when Count < 2;
               Count := (Count - 2) / 2;
            end loop;

            Pending := 0;
         end Flush_Pending;

      begin
         for Index in 0 .. N_In_Use - 1 loop
            Order (Index) := Index;
         end loop;

         for Index in Last'Range loop
            Value := Unseq_To_Seq (Natural (Last (Index)));

            Found := 0;
            for Position in 0 .. N_In_Use - 1 loop
               if Order (Position) = Value then
                  Found := Position;
                  exit;
               end if;
            end loop;

            for Back in reverse 1 .. Found loop
               Order (Back) := Order (Back - 1);
            end loop;
            Order (0) := Value;

            if Found = 0 then
               Pending := Pending + 1;
            else
               Flush_Pending;
               Mtf (N_Mtf) := Found + 1;
               Mtf_Freq (Found + 1) := Mtf_Freq (Found + 1) + 1;
               N_Mtf := N_Mtf + 1;
            end if;
         end loop;

         Flush_Pending;

         Mtf (N_Mtf) := End_Symbol;
         Mtf_Freq (End_Symbol) := Mtf_Freq (End_Symbol) + 1;
         N_Mtf := N_Mtf + 1;
      end;

      N_Groups := Group_Count (N_Mtf);

      --  Seed each table with a contiguous slice of the alphabet carrying about
      --  an equal share of the total symbol count.
      declare
         Remaining : Natural := N_Mtf;
         Start     : Natural := 0;
         Stop      : Integer;
         Target    : Natural;
         Taken     : Natural;
      begin
         for Part in reverse 1 .. N_Groups loop
            Target := Remaining / Part;
            Stop := Start - 1;
            Taken := 0;

            while Taken < Target and then Stop < Alpha_Size - 1 loop
               Stop := Stop + 1;
               Taken := Taken + Mtf_Freq (Stop);
            end loop;

            if Stop > Start
              and then Part /= N_Groups
              and then Part /= 1
              and then (N_Groups - Part) mod 2 = 1
            then
               Taken := Taken - Mtf_Freq (Stop);
               Stop := Stop - 1;
            end if;

            for Symbol in 0 .. Alpha_Size - 1 loop
               if Symbol >= Start and then Symbol <= Stop then
                  Lengths (Part - 1) (Symbol) := Lesser_Cost;
               else
                  Lengths (Part - 1) (Symbol) := Greater_Cost;
               end if;
            end loop;

            Remaining := Remaining - Taken;
            Start := Stop + 1;
         end loop;
      end;

      --  Refine: give each 50-symbol group to its cheapest table, then rebuild
      --  each table from the symbols that chose it. The assignment and the
      --  tables co-adapt over the passes.
      for Unused_Pass in 1 .. Iterations loop
         declare
            Freq  : Frequency_Set := [others => [others => 0]];
            Start : Natural := 0;
            Stop  : Natural;
            Cost  : array (0 .. Max_Groups - 1) of Natural;
            Best  : Natural;
         begin
            N_Selectors := 0;

            while Start < N_Mtf loop
               Stop := Natural'Min (Start + Group_Size - 1, N_Mtf - 1);

               Cost := [others => 0];
               for Group in 0 .. N_Groups - 1 loop
                  for Index in Start .. Stop loop
                     Cost (Group) :=
                       Cost (Group) + Lengths (Group) (Mtf (Index));
                  end loop;
               end loop;

               Best := 0;
               for Group in 1 .. N_Groups - 1 loop
                  if Cost (Group) < Cost (Best) then
                     Best := Group;
                  end if;
               end loop;

               Selector (N_Selectors) := Best;
               N_Selectors := N_Selectors + 1;

               for Index in Start .. Stop loop
                  Freq (Best) (Mtf (Index)) := Freq (Best) (Mtf (Index)) + 1;
               end loop;

               Start := Stop + 1;
            end loop;

            for Group in 0 .. N_Groups - 1 loop
               declare
                  Source : Zlib.BZip2_Lengths.Frequency_Array
                             (0 .. Alpha_Size - 1);
                  Result : Zlib.BZip2_Lengths.Length_Array
                             (0 .. Alpha_Size - 1);
               begin
                  for Symbol in Source'Range loop
                     Source (Symbol) := Freq (Group) (Symbol);
                  end loop;

                  Zlib.BZip2_Lengths.Make_Code_Lengths (Source, Result);

                  for Symbol in Result'Range loop
                     Lengths (Group) (Symbol) := Result (Symbol);
                  end loop;
               end;
            end loop;
         end;
      end loop;

      for Group in 0 .. N_Groups - 1 loop
         declare
            Source : Zlib.BZip2_Lengths.Length_Array (0 .. Alpha_Size - 1);
            Result : Zlib.BZip2_Lengths.Code_Array (0 .. Alpha_Size - 1);
         begin
            for Symbol in Source'Range loop
               Source (Symbol) := Lengths (Group) (Symbol);
            end loop;

            Zlib.BZip2_Lengths.Assign_Codes (Source, Result);

            for Symbol in Result'Range loop
               Codes (Group) (Symbol) := Result (Symbol);
            end loop;
         end;
      end loop;

      --  Block header.
      Writer.Write_Bits (W, Block_Magic_High, 24);
      Writer.Write_Bits (W, Block_Magic_Low, 24);
      Writer.Write_Bits (W, Block_CRC, 32);
      Writer.Write_Bit (W, False);                      --  never randomised
      Writer.Write_Bits (W, Interfaces.Unsigned_32 (Orig_Ptr), 24);

      --  Symbol map.
      declare
         Group_Used : array (0 .. 15) of Boolean := [others => False];
      begin
         for High in Group_Used'Range loop
            for Low in 0 .. 15 loop
               if In_Use (High * 16 + Low) then
                  Group_Used (High) := True;
               end if;
            end loop;
         end loop;

         for High in Group_Used'Range loop
            Writer.Write_Bit (W, Group_Used (High));
         end loop;

         for High in Group_Used'Range loop
            if Group_Used (High) then
               for Low in 0 .. 15 loop
                  Writer.Write_Bit (W, In_Use (High * 16 + Low));
               end loop;
            end if;
         end loop;
      end;

      Writer.Write_Bits (W, Interfaces.Unsigned_32 (N_Groups), 3);
      Writer.Write_Bits (W, Interfaces.Unsigned_32 (N_Selectors), 15);

      --  Selectors, themselves move-to-front coded and written in unary.
      declare
         Order : array (0 .. Max_Groups - 1) of Natural := [others => 0];
         Found : Natural;
         Value : Natural;
      begin
         for Index in 0 .. N_Groups - 1 loop
            Order (Index) := Index;
         end loop;

         for Index in 0 .. N_Selectors - 1 loop
            Value := Selector (Index);

            Found := 0;
            for Position in 0 .. N_Groups - 1 loop
               if Order (Position) = Value then
                  Found := Position;
                  exit;
               end if;
            end loop;

            for Unused_Bit in 1 .. Found loop
               Writer.Write_Bit (W, True);
            end loop;
            Writer.Write_Bit (W, False);

            for Back in reverse 1 .. Found loop
               Order (Back) := Order (Back - 1);
            end loop;
            Order (0) := Value;
         end loop;
      end;

      --  Code lengths, delta coded: "10" steps up, "11" steps down, "0" ends.
      for Group in 0 .. N_Groups - 1 loop
         declare
            Current : Natural := Lengths (Group) (0);
         begin
            Writer.Write_Bits (W, Interfaces.Unsigned_32 (Current), 5);

            for Symbol in 0 .. Alpha_Size - 1 loop
               while Current < Lengths (Group) (Symbol) loop
                  Writer.Write_Bit (W, True);
                  Writer.Write_Bit (W, False);
                  Current := Current + 1;
               end loop;

               while Current > Lengths (Group) (Symbol) loop
                  Writer.Write_Bit (W, True);
                  Writer.Write_Bit (W, True);
                  Current := Current - 1;
               end loop;

               Writer.Write_Bit (W, False);
            end loop;
         end;
      end loop;

      --  The symbols themselves, fifty per selector.
      declare
         Start : Natural := 0;
         Stop  : Natural;
         Group : Natural := 0;
         Table : Natural;
      begin
         while Start < N_Mtf loop
            Stop := Natural'Min (Start + Group_Size - 1, N_Mtf - 1);
            Table := Selector (Group);
            Group := Group + 1;

            for Index in Start .. Stop loop
               Writer.Write_Bits
                 (W,
                  Codes (Table) (Mtf (Index)),
                  Lengths (Table) (Mtf (Index)));
            end loop;

            Start := Stop + 1;
         end loop;
      end;

      Cleanup;

   exception
      when others =>
         Cleanup;
         Status := Invalid_Block_Type;
   end Encode_Block;

   function Encode
     (Plain  : Byte_Array;
      Level  : Level_Range := 9;
      Status : out Status_Code) return Byte_Array
   is
      W : Writer.Writer;

      --  bzip2 keeps a small margin below the nominal block size, because the
      --  run-length coder may emit up to five bytes for one input run.
      Limit : constant Positive := Level * 100_000 - 19;

      Block    : Byte_Buffer_Access := new Byte_Array (0 .. Limit - 1);
      Filled   : Natural;
      Combined : Interfaces.Unsigned_32 := 0;
      Position : Natural;
   begin
      Status := Ok;
      Writer.Reset (W);

      --  "BZh" and the level digit.
      Writer.Write_Bits (W, 16#42#, 8);
      Writer.Write_Bits (W, 16#5A#, 8);
      Writer.Write_Bits (W, 16#68#, 8);
      Writer.Write_Bits
        (W, Interfaces.Unsigned_32 (Character'Pos ('0') + Level), 8);

      Position := Plain'First;

      while Position <= Plain'Last loop
         Filled := 0;

         declare
            Running : Interfaces.Unsigned_32 := Zlib.BZip2_CRC.Initial;
         begin
            --  Fill one block with run-length-coded input.
            while Position <= Plain'Last loop
               declare
                  Item  : constant Byte := Plain (Position);
                  Run   : Natural := 1;
                  Coded : Natural;
               begin
                  while Position + Run <= Plain'Last
                    and then Plain (Position + Run) = Item
                    and then Run < Max_Run
                  loop
                     Run := Run + 1;
                  end loop;

                  Coded := (if Run >= 4 then 5 else Run);
                  exit when Filled + Coded > Limit;

                  for Unused_Index in 1 .. Natural'Min (Run, 4) loop
                     Block (Filled) := Item;
                     Filled := Filled + 1;
                  end loop;

                  if Run >= 4 then
                     Block (Filled) := Byte (Run - 4);
                     Filled := Filled + 1;
                  end if;

                  --  The stored CRC covers the block's original bytes, before
                  --  this run-length coding.
                  declare
                     Repeat : constant Byte_Array (1 .. Run) := [others => Item];
                  begin
                     Running := Zlib.BZip2_CRC.Update (Running, Repeat);
                  end;

                  Position := Position + Run;
               end;
            end loop;

            exit when Filled = 0;

            declare
               Block_CRC : constant Interfaces.Unsigned_32 :=
                 Zlib.BZip2_CRC.Finish (Running);
            begin
               Encode_Block (W, Block (0 .. Filled - 1), Block_CRC, Status);
               if Status /= Ok then
                  Free (Block);
                  return [1 .. 0 => 0];
               end if;

               Combined := Zlib.BZip2_CRC.Combine (Combined, Block_CRC);
            end;
         end;
      end loop;

      Writer.Write_Bits (W, End_Magic_High, 24);
      Writer.Write_Bits (W, End_Magic_Low, 24);
      Writer.Write_Bits (W, Combined, 32);
      Writer.Flush (W);

      Free (Block);
      Status := Ok;
      return Writer.To_Array (W);

   exception
      when others =>
         Free (Block);
         Status := Invalid_Block_Type;
         return [1 .. 0 => 0];
   end Encode;

end Zlib.BZip2_Encoder;
