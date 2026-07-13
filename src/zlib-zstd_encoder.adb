with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;

with Interfaces;

with Zlib.Zstd_Bits;
with Zlib.Zstd_FSE;
with Zlib.Zstd_Huffman;
with Zlib.Zstd_Tables;
with Zlib.Zstd_XXH64;

package body Zlib.Zstd_Encoder is

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   package Stream_Bits renames Zlib.Zstd_Bits;
   package FSE renames Zlib.Zstd_FSE;
   package Huffman renames Zlib.Zstd_Huffman;
   package Tables renames Zlib.Zstd_Tables;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Byte);

   Block_Max  : constant Natural := 131_072;
   Min_Match  : constant Natural := 3;
   Hash_Bits  : constant Natural := 16;
   Hash_Size  : constant Natural := 2 ** Hash_Bits;
   Chain_Depth : constant Natural := 32;

   type Sequence is record
      Literals : Natural := 0;
      Match    : Natural := 0;
      Offset   : Natural := 0;
   end record;

   package Sequence_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Sequence);

   type Position_Array is array (Natural range <>) of Natural;
   type Position_Access is access Position_Array;
   procedure Free is
     new Ada.Unchecked_Deallocation (Position_Array, Position_Access);

   function To_Array (Source : Byte_Vectors.Vector) return Byte_Array;
   procedure Put_LE
     (Target : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_64;
      Count  : Natural);

   function To_Array (Source : Byte_Vectors.Vector) return Byte_Array is
      Result : Byte_Array (1 .. Natural (Source.Length));
   begin
      for Index in Result'Range loop
         Result (Index) := Source (Index - 1);
      end loop;
      return Result;
   end To_Array;

   procedure Put_LE
     (Target : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_64;
      Count  : Natural) is
   begin
      for Index in 0 .. Count - 1 loop
         Target.Append
           (Byte (Interfaces.Shift_Right (Value, 8 * Index) and 16#FF#));
      end loop;
   end Put_LE;

   --------------------------------------------------------------------------
   --  Literals
   --------------------------------------------------------------------------

   procedure Write_Literals
     (Lits   : Byte_Array;
      Target : in out Byte_Vectors.Vector;
      Status : out Status_Code);

   procedure Write_Literals
     (Lits   : Byte_Array;
      Target : in out Byte_Vectors.Vector;
      Status : out Status_Code)
   is
      Regen : constant Natural := Lits'Length;

      procedure Write_Raw;

      procedure Write_Raw is
      begin
         if Regen < 32 then
            Target.Append (Byte (Regen * 8));
         elsif Regen < 4_096 then
            Target.Append (Byte (4 + (Regen mod 16) * 16));
            Target.Append (Byte (Regen / 16));
         else
            Target.Append (Byte (12 + (Regen mod 16) * 16));
            Target.Append (Byte ((Regen / 16) mod 256));
            Target.Append (Byte ((Regen / 4_096) mod 256));
         end if;

         for Item of Lits loop
            Target.Append (Item);
         end loop;
      end Write_Raw;

      Frequencies : Tables.Value_Array (0 .. 255) := [others => 0];
      Table       : Huffman.Encode_Table;
      Usable      : Boolean;
   begin
      Status := Ok;

      if Regen = 0 then
         Target.Append (0);
         return;
      end if;

      for Item of Lits loop
         Frequencies (Natural (Item)) := Frequencies (Natural (Item)) + 1;
      end loop;

      Huffman.Build_Encode (Frequencies, Table, Usable, Status);
      if Status /= Ok then
         return;
      end if;

      if not Usable then
         Write_Raw;
         return;
      end if;

      declare
         Description : Byte_Array (1 .. 512);
         Desc_Length : Natural;
         Can_Write   : Boolean;
      begin
         Huffman.Write_Table
           (Table, Description, Desc_Length, Can_Write, Status);
         if Status /= Ok then
            return;
         end if;

         if not Can_Write then
            Write_Raw;
            return;
         end if;

         --  One stream while it fits the narrow header, four otherwise: the
         --  single-stream form is the only one with a 10-bit size field.
         declare
            Single : constant Boolean := Regen < 1_024;
            Buffer : Byte_Array (1 .. Regen + Regen / 2 + 64) :=
              [others => 0];
            Body_Length : Natural := 0;

            Quarter : constant Natural := (Regen + 3) / 4;
            Sizes   : array (1 .. 4) of Natural := [others => 0];
            Parts   : Byte_Vectors.Vector;
         begin
            if Single then
               Huffman.Encode_Stream
                 (Table, Lits, Buffer, Body_Length, Status);
               if Status /= Ok then
                  Write_Raw;
                  Status := Ok;
                  return;
               end if;

               for Index in 1 .. Body_Length loop
                  Parts.Append (Buffer (Index));
               end loop;

            else
               for Part in 1 .. 4 loop
                  declare
                     From : constant Natural :=
                       Lits'First + (Part - 1) * Quarter;
                     To   : constant Natural :=
                       (if Part = 4 then Lits'Last
                        else Natural'Min
                               (Lits'First + Part * Quarter - 1, Lits'Last));
                  begin
                     if From > To then
                        --  Four streams need four non-empty parts.
                        Write_Raw;
                        return;
                     end if;

                     Huffman.Encode_Stream
                       (Table, Lits (From .. To), Buffer, Body_Length, Status);
                     if Status /= Ok then
                        Write_Raw;
                        Status := Ok;
                        return;
                     end if;

                     Sizes (Part) := Body_Length;
                     for Index in 1 .. Body_Length loop
                        Parts.Append (Buffer (Index));
                     end loop;
                  end;
               end loop;
            end if;

            declare
               Jump  : constant Natural := (if Single then 0 else 6);
               Total : constant Natural :=
                 Desc_Length + Jump + Natural (Parts.Length);
               Kind  : constant Natural := 2;
               Format : Natural;
               Header : Interfaces.Unsigned_64;
               Width  : Natural;
            begin
               --  Storing them raw is cheaper than a Huffman table that does
               --  not earn its keep.
               if Total >= Regen then
                  Write_Raw;
                  return;
               end if;

               if Single and then Total < 1_024 then
                  Format := 0;
                  Width := 3;
               elsif not Single and then Regen < 1_024 and then Total < 1_024
               then
                  Format := 1;
                  Width := 3;
               elsif not Single
                 and then Regen < 16_384 and then Total < 16_384
               then
                  Format := 2;
                  Width := 4;
               elsif not Single then
                  Format := 3;
                  Width := 5;
               else
                  --  A single stream whose compressed size overflows the 10-bit
                  --  field has no header to describe it.
                  Write_Raw;
                  return;
               end if;

               case Width is
                  when 3 =>
                     Header :=
                       Interfaces.Unsigned_64 (Kind)
                       + Interfaces.Unsigned_64 (Format) * 4
                       + Interfaces.Unsigned_64 (Regen) * 16
                       + Interfaces.Unsigned_64 (Total) * 16_384;
                  when 4 =>
                     Header :=
                       Interfaces.Unsigned_64 (Kind)
                       + Interfaces.Unsigned_64 (Format) * 4
                       + Interfaces.Unsigned_64 (Regen) * 16
                       + Interfaces.Unsigned_64 (Total) * 262_144;
                  when others =>
                     Header :=
                       Interfaces.Unsigned_64 (Kind)
                       + Interfaces.Unsigned_64 (Format) * 4
                       + Interfaces.Unsigned_64 (Regen) * 16
                       + Interfaces.Unsigned_64 (Total) * 4_194_304;
               end case;

               Put_LE (Target, Header, Width);

               for Index in 1 .. Desc_Length loop
                  Target.Append (Description (Index));
               end loop;

               if not Single then
                  Put_LE (Target, Interfaces.Unsigned_64 (Sizes (1)), 2);
                  Put_LE (Target, Interfaces.Unsigned_64 (Sizes (2)), 2);
                  Put_LE (Target, Interfaces.Unsigned_64 (Sizes (3)), 2);
               end if;

               for Index in 0 .. Natural (Parts.Length) - 1 loop
                  Target.Append (Parts (Index));
               end loop;
            end;
         end;
      end;
   end Write_Literals;

   --------------------------------------------------------------------------
   --  Sequences
   --------------------------------------------------------------------------

   procedure Write_Sequences
     (Seqs   : Sequence_Vectors.Vector;
      Target : in out Byte_Vectors.Vector;
      Status : out Status_Code);

   procedure Write_Sequences
     (Seqs   : Sequence_Vectors.Vector;
      Target : in out Byte_Vectors.Vector;
      Status : out Status_Code)
   is
      Count : constant Natural := Natural (Seqs.Length);

      type Code_Array is array (Natural range <>) of Natural;

      Lit_Codes : Code_Array (0 .. Natural'Max (Count, 1) - 1);
      Off_Codes : Code_Array (0 .. Natural'Max (Count, 1) - 1);
      Mat_Codes : Code_Array (0 .. Natural'Max (Count, 1) - 1);

      Lit_Freq : Tables.Value_Array (0 .. Tables.Max_Literal_Code) :=
        [others => 0];
      Off_Freq : Tables.Value_Array (0 .. 31) := [others => 0];
      Mat_Freq : Tables.Value_Array (0 .. Tables.Max_Match_Code) :=
        [others => 0];

      function Pick_Log
        (Frequencies : Tables.Value_Array;
         Max_Code    : Natural;
         Ceiling     : Natural) return Natural;

      function Pick_Log
        (Frequencies : Tables.Value_Array;
         Max_Code    : Natural;
         Ceiling     : Natural) return Natural
      is
         Present : Natural := 0;
         Log     : Natural := 5;
      begin
         for Code in 0 .. Max_Code loop
            if Frequencies (Code) > 0 then
               Present := Present + 1;
            end if;
         end loop;

         --  Every present symbol needs at least one state, and a wider table
         --  than the sequence count buys nothing.
         while 2 ** Log < Present and then Log < Ceiling loop
            Log := Log + 1;
         end loop;

         while 2 ** Log < Count and then Log < Ceiling loop
            Log := Log + 1;
         end loop;

         return Log;
      end Pick_Log;

   begin
      Status := Ok;

      if Count = 0 then
         Target.Append (0);
         return;
      end if;

      --  Classify every sequence, and count the codes.
      for Index in 0 .. Count - 1 loop
         declare
            Item     : constant Sequence := Seqs (Index);
            Off_Wire : constant Natural := Item.Offset + 3;
            Lit_Code : constant Natural := Tables.Literal_Code (Item.Literals);
            Mat_Code : constant Natural := Tables.Match_Code (Item.Match);
            Off_Code : constant Natural := Tables.Highest_Bit (Off_Wire);
         begin
            Lit_Codes (Index) := Lit_Code;
            Mat_Codes (Index) := Mat_Code;
            Off_Codes (Index) := Off_Code;

            Lit_Freq (Lit_Code) := Lit_Freq (Lit_Code) + 1;
            Mat_Freq (Mat_Code) := Mat_Freq (Mat_Code) + 1;
            Off_Freq (Off_Code) := Off_Freq (Off_Code) + 1;
         end;
      end loop;

      --  Number of sequences. The two-byte form reaches 32511 -- its lead byte
      --  is 128 + Count / 256 and may not exceed 254 -- and only past that does
      --  the three-byte form apply, which biases by 16#7F00# and would go
      --  negative if used any earlier.
      if Count < 128 then
         Target.Append (Byte (Count));
      elsif Count < 16#7F00# then
         Target.Append (Byte (128 + Count / 256));
         Target.Append (Byte (Count mod 256));
      else
         Target.Append (255);
         Put_LE (Target, Interfaces.Unsigned_64 (Count - 16#7F00#), 2);
      end if;

      --  All three tables are described in full: mode 2 for each.
      Target.Append (2 * 64 + 2 * 16 + 2 * 4);

      declare
         Lit_Max : Natural := 0;
         Off_Max : Natural := 0;
         Mat_Max : Natural := 0;
      begin
         for Code in 0 .. Tables.Max_Literal_Code loop
            if Lit_Freq (Code) > 0 then
               Lit_Max := Code;
            end if;
         end loop;
         for Code in 0 .. 31 loop
            if Off_Freq (Code) > 0 then
               Off_Max := Code;
            end if;
         end loop;
         for Code in 0 .. Tables.Max_Match_Code loop
            if Mat_Freq (Code) > 0 then
               Mat_Max := Code;
            end if;
         end loop;

         declare
            Lit_Log : constant Natural :=
              Pick_Log (Lit_Freq, Tables.Max_Literal_Code, 9);
            Off_Log : constant Natural := Pick_Log (Off_Freq, 31, 8);
            Mat_Log : constant Natural :=
              Pick_Log (Mat_Freq, Tables.Max_Match_Code, 9);

            Lit_Counts : Tables.Count_Array (0 .. Lit_Max);
            Off_Counts : Tables.Count_Array (0 .. Off_Max);
            Mat_Counts : Tables.Count_Array (0 .. Mat_Max);

            Lit_Table : FSE.Encode_Table;
            Off_Table : FSE.Encode_Table;
            Mat_Table : FSE.Encode_Table;

            Description : Byte_Array (1 .. 512);
            Length      : Natural;
         begin
            FSE.Normalize
              (Lit_Freq, Count, Lit_Max, Lit_Log, Lit_Counts, Status);
            if Status /= Ok then
               return;
            end if;
            FSE.Normalize
              (Off_Freq, Count, Off_Max, Off_Log, Off_Counts, Status);
            if Status /= Ok then
               return;
            end if;
            FSE.Normalize
              (Mat_Freq, Count, Mat_Max, Mat_Log, Mat_Counts, Status);
            if Status /= Ok then
               return;
            end if;

            --  Descriptions go out in the order the decoder reads them:
            --  literal lengths, then offsets, then match lengths.
            FSE.Write_Counts
              (Lit_Counts, Lit_Log, Lit_Max, Description, Length, Status);
            if Status /= Ok then
               return;
            end if;
            for Index in 1 .. Length loop
               Target.Append (Description (Index));
            end loop;

            FSE.Write_Counts
              (Off_Counts, Off_Log, Off_Max, Description, Length, Status);
            if Status /= Ok then
               return;
            end if;
            for Index in 1 .. Length loop
               Target.Append (Description (Index));
            end loop;

            FSE.Write_Counts
              (Mat_Counts, Mat_Log, Mat_Max, Description, Length, Status);
            if Status /= Ok then
               return;
            end if;
            for Index in 1 .. Length loop
               Target.Append (Description (Index));
            end loop;

            FSE.Build_Encode (Lit_Counts, Lit_Log, Lit_Table, Status);
            if Status /= Ok then
               return;
            end if;
            FSE.Build_Encode (Off_Counts, Off_Log, Off_Table, Status);
            if Status /= Ok then
               return;
            end if;
            FSE.Build_Encode (Mat_Counts, Mat_Log, Mat_Table, Status);
            if Status /= Ok then
               return;
            end if;

            --  The bitstream. Everything below is written in reverse of the
            --  order the decoder reads it, because an FSE state depends on the
            --  symbols that come after it: the encoder must walk the sequences
            --  backwards, and the backward writer undoes that.
            declare
               W : Stream_Bits.Backward_Writer;

               Lit_State : Natural;
               Off_State : Natural;
               Mat_State : Natural;

               Last : constant Natural := Count - 1;

               procedure Put_Extras (Index : Natural);

               procedure Put_Extras (Index : Natural) is
                  Item     : constant Sequence := Seqs (Index);
                  Off_Wire : constant Natural := Item.Offset + 3;
                  Lit_Code : constant Natural := Lit_Codes (Index);
                  Mat_Code : constant Natural := Mat_Codes (Index);
                  Off_Code : constant Natural := Off_Codes (Index);
               begin
                  --  Read order is offset, match, literal -- so write the
                  --  reverse.
                  Stream_Bits.Write
                    (W,
                     Interfaces.Unsigned_32
                       (Item.Literals - Tables.Literal_Baseline (Lit_Code)),
                     Tables.Literal_Extra_Bits (Lit_Code));
                  Stream_Bits.Write
                    (W,
                     Interfaces.Unsigned_32
                       (Item.Match - Tables.Match_Baseline (Mat_Code)),
                     Tables.Match_Extra_Bits (Mat_Code));
                  Stream_Bits.Write
                    (W,
                     Interfaces.Unsigned_32 (Off_Wire - 2 ** Off_Code),
                     Off_Code);
               end Put_Extras;

            begin
               Stream_Bits.Reset (W);

               --  The states start on the LAST sequence, which is the first one
               --  the decoder will meet.
               FSE.Init_Encode (Lit_Table, Lit_Codes (Last), Lit_State, W);
               FSE.Init_Encode (Off_Table, Off_Codes (Last), Off_State, W);
               FSE.Init_Encode (Mat_Table, Mat_Codes (Last), Mat_State, W);

               Put_Extras (Last);

               for Index in reverse 0 .. Last - 1 loop
                  --  Transitions, written in reverse of the decoder's update
                  --  order (literal, match, offset).
                  FSE.Encode (Off_Table, Off_Codes (Index), Off_State, W);
                  FSE.Encode (Mat_Table, Mat_Codes (Index), Mat_State, W);
                  FSE.Encode (Lit_Table, Lit_Codes (Index), Lit_State, W);

                  Put_Extras (Index);
               end loop;

               --  Initial states, again reversed: the decoder reads literal,
               --  offset, match.
               FSE.Flush_Encode (Mat_Table, Mat_State, W);
               FSE.Flush_Encode (Off_Table, Off_State, W);
               FSE.Flush_Encode (Lit_Table, Lit_State, W);

               declare
                  Stream : constant Byte_Array := Stream_Bits.Finish (W);
               begin
                  for Item of Stream loop
                     Target.Append (Item);
                  end loop;
               end;
            end;
         end;
      end;
   end Write_Sequences;

   --------------------------------------------------------------------------

   function Encode
     (Plain  : Byte_Array;
      Status : out Status_Code) return Byte_Array
   is
      Frame : Byte_Vectors.Vector;

      Head : Position_Access := new Position_Array (0 .. Hash_Size - 1);
      Prev : Position_Access :=
        new Position_Array (0 .. Natural'Max (Plain'Length, 1) - 1);

      function Hash_At (Index : Natural) return Natural;

      function Hash_At (Index : Natural) return Natural is
         Value : Interfaces.Unsigned_32;
      begin
         Value :=
           Interfaces.Unsigned_32 (Plain (Index))
           or Interfaces.Shift_Left
                (Interfaces.Unsigned_32 (Plain (Index + 1)), 8)
           or Interfaces.Shift_Left
                (Interfaces.Unsigned_32 (Plain (Index + 2)), 16);
         Value := Value * 2_654_435_761;
         return
           Natural (Interfaces.Shift_Right (Value, 32 - Hash_Bits));
      end Hash_At;

   begin
      Status := Ok;
      Head.all := [others => 0];
      Prev.all := [others => 0];

      --  Frame header: single segment, so the window is the content itself; a
      --  four-byte content size; and a content checksum.
      Put_LE (Frame, 16#FD2F_B528#, 4);
      Frame.Append (2 * 64 + 32 + 4);
      Put_LE (Frame, Interfaces.Unsigned_64 (Plain'Length), 4);

      declare
         Position : Natural := Plain'First;
      begin
         loop
            declare
               Stop : constant Natural :=
                 Natural'Min (Position + Block_Max - 1, Plain'Last);
               Last_Block : constant Boolean := Stop = Plain'Last;

               Seqs   : Sequence_Vectors.Vector;
               Lits   : Byte_Vectors.Vector;
               Cursor : Natural := Position;
               Run    : Natural := 0;

               Body_Bytes : Byte_Vectors.Vector;
            begin
               exit when Plain'Length = 0;

               --  Find matches over this block.
               while Cursor <= Stop loop
                  declare
                     Best_Length : Natural := 0;
                     Best_Source : Natural := 0;
                  begin
                     if Cursor + Min_Match - 1 <= Stop then
                        declare
                           Slot      : constant Natural := Hash_At (Cursor);
                           Candidate : Natural := Head (Slot);
                           Depth     : Natural := 0;
                        begin
                           while Candidate /= 0
                             and then Depth < Chain_Depth
                           loop
                              declare
                                 Source : constant Natural := Candidate - 1;
                                 Length : Natural := 0;
                              begin
                                 while Cursor + Length <= Stop
                                   and then Plain (Source + Length)
                                            = Plain (Cursor + Length)
                                   and then Length < 65_535
                                 loop
                                    Length := Length + 1;
                                 end loop;

                                 if Length >= Min_Match
                                   and then Length > Best_Length
                                 then
                                    Best_Length := Length;
                                    Best_Source := Source;
                                 end if;

                                 Candidate := Prev (Source - Plain'First);
                              end;
                              Depth := Depth + 1;
                           end loop;

                           --  Record this position for later searches.
                           Prev (Cursor - Plain'First) := Head (Slot);
                           Head (Slot) := Cursor + 1;
                        end;
                     end if;

                     if Best_Length >= Min_Match then
                        Seqs.Append
                          (Sequence'
                             (Literals => Run,
                              Match    => Best_Length,
                              Offset   => Cursor - Best_Source));
                        Run := 0;

                        --  Index the bytes the match covers, then skip them.
                        for Step in 1 .. Best_Length - 1 loop
                           if Cursor + Step + Min_Match - 1 <= Stop then
                              declare
                                 Slot : constant Natural :=
                                   Hash_At (Cursor + Step);
                              begin
                                 Prev (Cursor + Step - Plain'First) :=
                                   Head (Slot);
                                 Head (Slot) := Cursor + Step + 1;
                              end;
                           end if;
                        end loop;

                        Cursor := Cursor + Best_Length;
                     else
                        Lits.Append (Plain (Cursor));
                        Run := Run + 1;
                        Cursor := Cursor + 1;
                     end if;
                  end;
               end loop;

               --  Literals with no match behind them trail the last sequence.
               declare
                  Lit_Array : constant Byte_Array := To_Array (Lits);
               begin
                  Write_Literals (Lit_Array, Body_Bytes, Status);
                  if Status /= Ok then
                     Free (Head);
                     Free (Prev);
                     return [1 .. 0 => 0];
                  end if;

                  Write_Sequences (Seqs, Body_Bytes, Status);
                  if Status /= Ok then
                     Free (Head);
                     Free (Prev);
                     return [1 .. 0 => 0];
                  end if;
               end;

               declare
                  Raw_Size  : constant Natural := Stop - Position + 1;
                  Body_Size : constant Natural := Natural (Body_Bytes.Length);
               begin
                  if Body_Size >= Raw_Size then
                     --  Compression did not pay: store the block.
                     Put_LE
                       (Frame,
                        Interfaces.Unsigned_64
                          ((if Last_Block then 1 else 0)
                           + Raw_Size * 8),
                        3);
                     for Index in Position .. Stop loop
                        Frame.Append (Plain (Index));
                     end loop;
                  else
                     Put_LE
                       (Frame,
                        Interfaces.Unsigned_64
                          ((if Last_Block then 1 else 0)
                           + 2 * 2
                           + Body_Size * 8),
                        3);
                     for Index in 0 .. Body_Size - 1 loop
                        Frame.Append (Body_Bytes (Index));
                     end loop;
                  end if;
               end;

               exit when Last_Block;
               Position := Stop + 1;
            end;
         end loop;

         if Plain'Length = 0 then
            --  An empty frame still needs one (empty, raw, last) block.
            Put_LE (Frame, 1, 3);
         end if;
      end;

      --  Content checksum: the low half of the XXH64 of the whole content.
      Put_LE
        (Frame,
         Zlib.Zstd_XXH64.Compute (Plain) and 16#FFFF_FFFF#,
         4);

      Free (Head);
      Free (Prev);
      return To_Array (Frame);

   exception
      when others =>
         Free (Head);
         Free (Prev);
         Status := Invalid_Block_Type;
         return [1 .. 0 => 0];
   end Encode;

end Zlib.Zstd_Encoder;
