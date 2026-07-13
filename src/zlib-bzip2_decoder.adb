with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;

with Interfaces;

with Zlib.BZip2_Bits;
with Zlib.BZip2_CRC;
with Zlib.BZip2_Huffman;

package body Zlib.BZip2_Decoder is

   use type Interfaces.Unsigned_32;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Byte);

   Group_Size    : constant Natural := 50;
   Max_Groups    : constant Natural := 6;
   Max_Selectors : constant Natural := 18_002;
   Run_A         : constant Natural := 0;
   Run_B         : constant Natural := 1;

   Block_Magic_High : constant Interfaces.Unsigned_32 := 16#31_4159#;
   Block_Magic_Low  : constant Interfaces.Unsigned_32 := 16#26_5359#;
   End_Magic_High   : constant Interfaces.Unsigned_32 := 16#17_7245#;
   End_Magic_Low    : constant Interfaces.Unsigned_32 := 16#38_5090#;

   --  The Burrows-Wheeler block: each entry packs the byte in its low 8 bits and,
   --  once the inverse transform has threaded them, the successor index above.
   type Block_Data is array (Natural range <>) of Interfaces.Unsigned_32;
   type Block_Access is access Block_Data;
   procedure Free is new Ada.Unchecked_Deallocation (Block_Data, Block_Access);

   type Table_Array is
     array (0 .. Max_Groups - 1) of Zlib.BZip2_Huffman.Decode_Table;
   type Selector_Array is array (0 .. Max_Selectors - 1) of Natural;
   type Count_Array is array (0 .. 255) of Natural;
   type Cumulative_Array is array (0 .. 256) of Natural;
   type Mtf_Array is array (0 .. 255) of Byte;
   type Use_Array is array (0 .. 255) of Boolean;

   function To_Array (Source : Byte_Vectors.Vector) return Byte_Array;

   procedure Decode_Block
     (R         : in out Zlib.BZip2_Bits.Reader;
      Payload   : Byte_Array;
      Max_Block : Positive;
      Block_CRC : out Interfaces.Unsigned_32;
      Output    : in out Byte_Vectors.Vector;
      Status    : out Status_Code);

   function To_Array (Source : Byte_Vectors.Vector) return Byte_Array is
      Result : Byte_Array (1 .. Natural (Source.Length));
   begin
      for Index in Result'Range loop
         Result (Index) := Source (Index - 1);
      end loop;
      return Result;
   end To_Array;

   procedure Decode_Block
     (R         : in out Zlib.BZip2_Bits.Reader;
      Payload   : Byte_Array;
      Max_Block : Positive;
      Block_CRC : out Interfaces.Unsigned_32;
      Output    : in out Byte_Vectors.Vector;
      Status    : out Status_Code)
   is
      TT : Block_Access := new Block_Data (0 .. Max_Block - 1);

      Stored_CRC : Interfaces.Unsigned_32 := 0;

      procedure Run;
      --  The block body, so that TT can be freed on every exit path.

      procedure Run is
         In_Use       : Use_Array := [others => False];
         Seq_To_Unseq : Mtf_Array := [others => 0];
         Mtf          : Mtf_Array := [others => 0];
         Unzftab      : Count_Array := [others => 0];
         Cftab        : Cumulative_Array := [others => 0];
         Tables       : Table_Array;
         Selector     : Selector_Array := [others => 0];
         Selector_Mtf : Selector_Array := [others => 0];

         N_In_Use     : Natural := 0;
         Alpha_Size   : Natural := 0;
         N_Groups     : Natural := 0;
         N_Selectors  : Natural := 0;
         N_Block      : Natural := 0;
         Orig_Ptr     : Natural := 0;
         End_Of_Block : Natural := 0;

         Group_No  : Natural := 0;
         Group_Pos : Natural := 0;
         Group_Sel : Natural := 0;

         Raw   : Interfaces.Unsigned_32;
         Bit   : Boolean;
         Value : Natural;

         function Next_Symbol return Natural;

         function Next_Symbol return Natural is
         begin
            if Group_Pos = 0 then
               if Group_No >= N_Selectors then
                  Status := Invalid_Huffman_Code;
                  return 0;
               end if;
               Group_Sel := Selector (Group_No);
               Group_No := Group_No + 1;
               Group_Pos := Group_Size;
            end if;
            Group_Pos := Group_Pos - 1;

            return
              Zlib.BZip2_Huffman.Decode
                (R, Payload, Tables (Group_Sel), Status);
         end Next_Symbol;

      begin
         Stored_CRC := Zlib.BZip2_Bits.Read_Bits (R, Payload, 32, Status);
         if Status /= Ok then
            return;
         end if;

         Bit := Zlib.BZip2_Bits.Read_Bit (R, Payload, Status);
         if Status /= Ok then
            return;
         end if;
         if Bit then
            --  Deprecated randomisation, unused since bzip2 0.9.5. Refuse rather
            --  than silently produce wrong output.
            Status := Unsupported_Method;
            return;
         end if;

         Raw := Zlib.BZip2_Bits.Read_Bits (R, Payload, 24, Status);
         if Status /= Ok then
            return;
         end if;
         Orig_Ptr := Natural (Raw);

         --  Symbol map: 16 group bits, then 16 bits for each non-empty group.
         declare
            Group_Used : array (0 .. 15) of Boolean := [others => False];
         begin
            for Index in Group_Used'Range loop
               Group_Used (Index) :=
                 Zlib.BZip2_Bits.Read_Bit (R, Payload, Status);
               if Status /= Ok then
                  return;
               end if;
            end loop;

            for Index in Group_Used'Range loop
               if Group_Used (Index) then
                  for Offset in 0 .. 15 loop
                     Bit := Zlib.BZip2_Bits.Read_Bit (R, Payload, Status);
                     if Status /= Ok then
                        return;
                     end if;
                     if Bit then
                        In_Use (Index * 16 + Offset) := True;
                     end if;
                  end loop;
               end if;
            end loop;
         end;

         for Symbol in In_Use'Range loop
            if In_Use (Symbol) then
               Seq_To_Unseq (N_In_Use) := Byte (Symbol);
               N_In_Use := N_In_Use + 1;
            end if;
         end loop;

         if N_In_Use = 0 then
            Status := Invalid_Block_Type;
            return;
         end if;

         Alpha_Size := N_In_Use + 2;
         End_Of_Block := Alpha_Size - 1;

         Raw := Zlib.BZip2_Bits.Read_Bits (R, Payload, 3, Status);
         if Status /= Ok then
            return;
         end if;
         N_Groups := Natural (Raw);
         if N_Groups < 2 or else N_Groups > Max_Groups then
            Status := Invalid_Block_Type;
            return;
         end if;

         Raw := Zlib.BZip2_Bits.Read_Bits (R, Payload, 15, Status);
         if Status /= Ok then
            return;
         end if;
         N_Selectors := Natural (Raw);
         if N_Selectors = 0 or else N_Selectors > Max_Selectors then
            Status := Invalid_Block_Type;
            return;
         end if;

         --  Selectors, themselves move-to-front coded as unary run lengths.
         for Index in 0 .. N_Selectors - 1 loop
            Value := 0;
            loop
               Bit := Zlib.BZip2_Bits.Read_Bit (R, Payload, Status);
               if Status /= Ok then
                  return;
               end if;
               exit when not Bit;
               Value := Value + 1;
               if Value >= N_Groups then
                  Status := Invalid_Huffman_Code;
                  return;
               end if;
            end loop;
            Selector_Mtf (Index) := Value;
         end loop;

         declare
            Pos  : array (0 .. Max_Groups - 1) of Natural := [others => 0];
            Temp : Natural;
         begin
            for Index in 0 .. N_Groups - 1 loop
               Pos (Index) := Index;
            end loop;

            for Index in 0 .. N_Selectors - 1 loop
               Value := Selector_Mtf (Index);
               Temp := Pos (Value);
               for Back in reverse 1 .. Value loop
                  Pos (Back) := Pos (Back - 1);
               end loop;
               Pos (0) := Temp;
               Selector (Index) := Temp;
            end loop;
         end;

         --  Code lengths, delta coded from a 5-bit starting length.
         for Group in 0 .. N_Groups - 1 loop
            declare
               Lengths : Zlib.BZip2_Huffman.Length_Array (0 .. Alpha_Size - 1) :=
                 [others => 0];
               Current : Integer;
            begin
               Raw := Zlib.BZip2_Bits.Read_Bits (R, Payload, 5, Status);
               if Status /= Ok then
                  return;
               end if;
               Current := Integer (Raw);

               for Symbol in Lengths'Range loop
                  loop
                     if Current < 1 or else Current > 20 then
                        Status := Invalid_Huffman_Code;
                        return;
                     end if;

                     Bit := Zlib.BZip2_Bits.Read_Bit (R, Payload, Status);
                     if Status /= Ok then
                        return;
                     end if;
                     exit when not Bit;

                     Bit := Zlib.BZip2_Bits.Read_Bit (R, Payload, Status);
                     if Status /= Ok then
                        return;
                     end if;
                     if Bit then
                        Current := Current - 1;
                     else
                        Current := Current + 1;
                     end if;
                  end loop;

                  Lengths (Symbol) := Current;
               end loop;

               Zlib.BZip2_Huffman.Build (Lengths, Tables (Group), Status);
               if Status /= Ok then
                  return;
               end if;
            end;
         end loop;

         --  Move-to-front list over the symbols actually present.
         for Index in 0 .. N_In_Use - 1 loop
            Mtf (Index) := Seq_To_Unseq (Index);
         end loop;

         --  The MTF/RLE2 symbol stream, producing the Burrows-Wheeler block.
         declare
            Symbol : Natural := Next_Symbol;
            Run    : Natural;
            Weight : Natural;
            Item   : Byte;
         begin
            if Status /= Ok then
               return;
            end if;

            while Symbol /= End_Of_Block loop
               if Symbol = Run_A or else Symbol = Run_B then
                  Run := 0;
                  Weight := 1;

                  while Symbol = Run_A or else Symbol = Run_B loop
                     if Symbol = Run_A then
                        Run := Run + Weight;
                     else
                        Run := Run + 2 * Weight;
                     end if;

                     if Run > Max_Block then
                        Status := Invalid_Block_Type;
                        return;
                     end if;

                     Weight := Weight * 2;
                     Symbol := Next_Symbol;
                     if Status /= Ok then
                        return;
                     end if;
                  end loop;

                  Item := Mtf (0);
                  if N_Block + Run > Max_Block then
                     Status := Invalid_Block_Type;
                     return;
                  end if;

                  Unzftab (Natural (Item)) := Unzftab (Natural (Item)) + Run;
                  for Unused_Index in 1 .. Run loop
                     TT (N_Block) := Interfaces.Unsigned_32 (Item);
                     N_Block := N_Block + 1;
                  end loop;

               else
                  --  Symbols 2 .. Alpha_Size - 2 select move-to-front position
                  --  Symbol - 1; position 0 is reachable only through a run.
                  Value := Symbol - 1;
                  if Value < 1 or else Value > N_In_Use - 1 then
                     Status := Invalid_Huffman_Code;
                     return;
                  end if;

                  Item := Mtf (Value);
                  for Back in reverse 1 .. Value loop
                     Mtf (Back) := Mtf (Back - 1);
                  end loop;
                  Mtf (0) := Item;

                  if N_Block >= Max_Block then
                     Status := Invalid_Block_Type;
                     return;
                  end if;

                  Unzftab (Natural (Item)) := Unzftab (Natural (Item)) + 1;
                  TT (N_Block) := Interfaces.Unsigned_32 (Item);
                  N_Block := N_Block + 1;

                  Symbol := Next_Symbol;
                  if Status /= Ok then
                     return;
                  end if;
               end if;
            end loop;
         end;

         if N_Block = 0 or else Orig_Ptr >= N_Block then
            Status := Invalid_Block_Type;
            return;
         end if;

         --  Inverse Burrows-Wheeler transform: thread each position to its
         --  successor, then walk the chain from Orig_Ptr.
         Cftab (0) := 0;
         for Index in 0 .. 255 loop
            Cftab (Index + 1) := Unzftab (Index);
         end loop;
         for Index in 1 .. 256 loop
            Cftab (Index) := Cftab (Index) + Cftab (Index - 1);
         end loop;

         for Index in 0 .. N_Block - 1 loop
            declare
               Item : constant Natural := Natural (TT (Index) and 16#FF#);
            begin
               TT (Cftab (Item)) :=
                 TT (Cftab (Item))
                 or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Index), 8);
               Cftab (Item) := Cftab (Item) + 1;
            end;
         end loop;

         --  Walk the block, undoing the initial run-length coding as we go, and
         --  check the block against its stored CRC.
         declare
            Position : Natural :=
              Natural (Interfaces.Shift_Right (TT (Orig_Ptr), 8));
            Plain    : Byte_Vectors.Vector;
            Item     : Byte;
            Previous : Integer := -1;
            Run      : Natural := 0;
            Expect   : Boolean := False;
         begin
            for Unused_Index in 1 .. N_Block loop
               if Position >= N_Block then
                  Status := Invalid_Block_Type;
                  return;
               end if;

               Item := Byte (TT (Position) and 16#FF#);
               Position := Natural (Interfaces.Shift_Right (TT (Position), 8));

               if Expect then
                  --  The byte after four equal ones is a repeat count.
                  for Unused_Repeat in 1 .. Natural (Item) loop
                     Plain.Append (Byte (Previous));
                  end loop;
                  Expect := False;
                  Run := 0;
                  Previous := -1;
               else
                  if Run > 0 and then Integer (Item) = Previous then
                     Run := Run + 1;
                  else
                     Previous := Integer (Item);
                     Run := 1;
                  end if;

                  Plain.Append (Item);
                  Expect := Run = 4;
               end if;
            end loop;

            if Expect then
               --  A run of four ended the block with no count byte behind it.
               Status := Unexpected_End_Of_Input;
               return;
            end if;

            declare
               Decoded : constant Byte_Array := To_Array (Plain);
            begin
               if Zlib.BZip2_CRC.Compute (Decoded) /= Stored_CRC then
                  Status := Invalid_Checksum;
                  return;
               end if;

               for Item_Value of Decoded loop
                  Output.Append (Item_Value);
               end loop;
            end;
         end;

         Status := Ok;
      end Run;

   begin
      Block_CRC := 0;
      Status := Ok;

      Run;

      Block_CRC := Stored_CRC;
      Free (TT);

   exception
      when others =>
         Free (TT);
         Status := Invalid_Block_Type;
   end Decode_Block;

   function Decode
     (Payload : Byte_Array;
      Status  : out Status_Code) return Byte_Array
   is
      Empty  : constant Byte_Array (1 .. 0) := [others => 0];
      Output : Byte_Vectors.Vector;
      R      : Zlib.BZip2_Bits.Reader;

      High : Interfaces.Unsigned_32;
      Low  : Interfaces.Unsigned_32;

      Level        : Natural;
      Max_Block    : Positive;
      Block_CRC    : Interfaces.Unsigned_32;
      Combined     : Interfaces.Unsigned_32;
      Stored_Total : Interfaces.Unsigned_32;
   begin
      Status := Ok;

      if Payload'Length < 4 then
         Status := Unexpected_End_Of_Input;
         return Empty;
      end if;

      Zlib.BZip2_Bits.Reset (R, Payload'First);

      --  One iteration per stream; bzip2(1) accepts concatenated streams.
      loop
         High := Zlib.BZip2_Bits.Read_Bits (R, Payload, 24, Status);
         if Status /= Ok then
            return Empty;
         end if;

         --  "BZh"
         if High /= 16#42_5A68# then
            Status := Invalid_Header;
            return Empty;
         end if;

         Low := Zlib.BZip2_Bits.Read_Bits (R, Payload, 8, Status);
         if Status /= Ok then
            return Empty;
         end if;

         --  Level is the ASCII digit '1' .. '9', in units of 100k.
         if Low < Character'Pos ('1') or else Low > Character'Pos ('9') then
            Status := Invalid_Header;
            return Empty;
         end if;
         Level := Natural (Low) - Character'Pos ('0');
         Max_Block := Level * 100_000;

         Combined := 0;

         loop
            High := Zlib.BZip2_Bits.Read_Bits (R, Payload, 24, Status);
            if Status /= Ok then
               return Empty;
            end if;
            Low := Zlib.BZip2_Bits.Read_Bits (R, Payload, 24, Status);
            if Status /= Ok then
               return Empty;
            end if;

            if High = Block_Magic_High and then Low = Block_Magic_Low then
               Decode_Block (R, Payload, Max_Block, Block_CRC, Output, Status);
               if Status /= Ok then
                  return Empty;
               end if;
               Combined := Zlib.BZip2_CRC.Combine (Combined, Block_CRC);

            elsif High = End_Magic_High and then Low = End_Magic_Low then
               Stored_Total :=
                 Zlib.BZip2_Bits.Read_Bits (R, Payload, 32, Status);
               if Status /= Ok then
                  return Empty;
               end if;
               if Stored_Total /= Combined then
                  Status := Invalid_Checksum;
                  return Empty;
               end if;
               exit;

            else
               Status := Invalid_Header;
               return Empty;
            end if;
         end loop;

         --  A stream is padded to a byte boundary; another may follow.
         Zlib.BZip2_Bits.Align_To_Byte (R);
         exit when Zlib.BZip2_Bits.Byte_Position (R) > Payload'Last;
      end loop;

      Status := Ok;
      return To_Array (Output);
   end Decode;

end Zlib.BZip2_Decoder;
