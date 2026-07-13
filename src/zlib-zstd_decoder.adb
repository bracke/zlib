with Ada.Containers.Vectors;

with Interfaces;

with Zlib.Zstd_Bits;
with Zlib.Zstd_FSE;
with Zlib.Zstd_Huffman;
with Zlib.Zstd_Tables;
with Zlib.Zstd_XXH64;

package body Zlib.Zstd_Decoder is

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   package Stream_Bits renames Zlib.Zstd_Bits;
   package FSE renames Zlib.Zstd_FSE;
   package Huffman renames Zlib.Zstd_Huffman;
   package Tables renames Zlib.Zstd_Tables;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Byte);

   Magic          : constant Interfaces.Unsigned_32 := 16#FD2F_B528#;
   Skip_Magic_Low : constant Interfaces.Unsigned_32 := 16#184D_2A50#;

   type Mode_Kind is (Predefined, Single, Compressed_Table, Repeat);

   type Sequence_Tables is record
      Literal : FSE.Decode_Table;
      Offset  : FSE.Decode_Table;
      Match   : FSE.Decode_Table;
      Have    : Boolean := False;
   end record;

   function To_Array (Source : Byte_Vectors.Vector) return Byte_Array;

   function Read_LE
     (Data  : Byte_Array;
      First : Natural;
      Count : Natural) return Interfaces.Unsigned_64;

   function To_Array (Source : Byte_Vectors.Vector) return Byte_Array is
      Result : Byte_Array (1 .. Natural (Source.Length));
   begin
      for Index in Result'Range loop
         Result (Index) := Source (Index - 1);
      end loop;
      return Result;
   end To_Array;

   function Read_LE
     (Data  : Byte_Array;
      First : Natural;
      Count : Natural) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Offset in reverse 0 .. Count - 1 loop
         Result :=
           Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_64 (Data (First + Offset));
      end loop;
      return Result;
   end Read_LE;

   function Decode
     (Payload : Byte_Array;
      Status  : out Status_Code) return Byte_Array
   is
      Empty  : constant Byte_Array (1 .. 0) := [others => 0];
      Output : Byte_Vectors.Vector;

      Position : Natural := Payload'First;

      --  Carried across the blocks of one frame.
      Repeat_1 : Natural := 1;
      Repeat_2 : Natural := 4;
      Repeat_3 : Natural := 8;
      Seq_Prev : Sequence_Tables;
      Huff_Prev : Huffman.Decode_Table;
      Have_Huff : Boolean := False;

      Frame_Start : Natural := 0;
      Skippable   : Boolean := False;

      procedure Decode_Block (Size : Natural; Status : out Status_Code);
      procedure Decode_Sequences
        (Data   : Byte_Array;
         Lits   : Byte_Array;
         Status : out Status_Code);

      ------------------------------------------------------------------------

      procedure Decode_Sequences
        (Data   : Byte_Array;
         Lits   : Byte_Array;
         Status : out Status_Code)
      is
         Cursor    : Natural := Data'First;
         Count     : Natural := 0;
         Lit_Taken : Natural := Lits'First;
      begin
         Status := Ok;

         if Data'Length = 0 then
            --  No sequences section at all: the literals are the whole block.
            for Item of Lits loop
               Output.Append (Item);
            end loop;
            return;
         end if;

         declare
            First : constant Natural := Natural (Data (Cursor));
         begin
            if First = 0 then
               Cursor := Cursor + 1;
               for Item of Lits loop
                  Output.Append (Item);
               end loop;
               if Cursor <= Data'Last then
                  Status := Invalid_Block_Type;
               end if;
               return;

            elsif First < 128 then
               Count := First;
               Cursor := Cursor + 1;

            elsif First < 255 then
               if Cursor + 1 > Data'Last then
                  Status := Unexpected_End_Of_Input;
                  return;
               end if;
               Count :=
                 (First - 128) * 256 + Natural (Data (Cursor + 1));
               Cursor := Cursor + 2;

            else
               if Cursor + 2 > Data'Last then
                  Status := Unexpected_End_Of_Input;
                  return;
               end if;
               Count :=
                 Natural (Data (Cursor + 1))
                 + Natural (Data (Cursor + 2)) * 256
                 + 16#7F00#;
               Cursor := Cursor + 3;
            end if;
         end;

         if Cursor > Data'Last then
            Status := Unexpected_End_Of_Input;
            return;
         end if;

         --  One byte selects how each of the three symbol tables is described.
         declare
            Modes    : constant Natural := Natural (Data (Cursor));
            Lit_Mode : constant Mode_Kind :=
              Mode_Kind'Val ((Modes / 64) mod 4);
            Off_Mode : constant Mode_Kind :=
              Mode_Kind'Val ((Modes / 16) mod 4);
            Mat_Mode : constant Mode_Kind :=
              Mode_Kind'Val ((Modes / 4) mod 4);

            Current : Sequence_Tables := Seq_Prev;

            procedure Load
              (Mode    : Mode_Kind;
               Default : Tables.Count_Array;
               Default_Log : Natural;
               Max_Code    : Natural;
               Table       : in out FSE.Decode_Table;
               Status      : out Status_Code);

            procedure Load
              (Mode    : Mode_Kind;
               Default : Tables.Count_Array;
               Default_Log : Natural;
               Max_Code    : Natural;
               Table       : in out FSE.Decode_Table;
               Status      : out Status_Code) is
            begin
               Status := Ok;

               case Mode is
                  when Predefined =>
                     FSE.Build_Decode (Default, Default_Log, Table, Status);

                  when Single =>
                     --  A single symbol, given literally; every state emits it.
                     if Cursor > Data'Last then
                        Status := Unexpected_End_Of_Input;
                        return;
                     end if;
                     declare
                        Only   : constant Natural := Natural (Data (Cursor));
                        Counts : Tables.Count_Array (0 .. Max_Code) :=
                          [others => 0];
                     begin
                        if Only > Max_Code then
                           Status := Invalid_Huffman_Code;
                           return;
                        end if;
                        Counts (Only) := 1;
                        Cursor := Cursor + 1;
                        FSE.Build_Decode (Counts, 0, Table, Status);
                     end;

                  when Compressed_Table =>
                     declare
                        Counts    : Tables.Count_Array (0 .. Max_Code) :=
                          [others => 0];
                        Log       : Natural;
                        Last_Code : Natural;
                        Used      : Natural;
                     begin
                        FSE.Read_Counts
                          (Data      => Data,
                           First     => Cursor,
                           Max_Code  => Max_Code,
                           Counts    => Counts,
                           Log       => Log,
                           Last_Code => Last_Code,
                           Used      => Used,
                           Status    => Status);
                        if Status /= Ok then
                           return;
                        end if;
                        Cursor := Cursor + Used;
                        FSE.Build_Decode (Counts, Log, Table, Status);
                     end;

                  when Repeat =>
                     if not Current.Have then
                        Status := Invalid_Huffman_Code;
                     end if;
               end case;
            end Load;

         begin
            Cursor := Cursor + 1;

            Load (Lit_Mode, Tables.Literal_Default, Tables.Literal_Log,
                  Tables.Max_Literal_Code, Current.Literal, Status);
            if Status /= Ok then
               return;
            end if;

            Load (Off_Mode, Tables.Offset_Default, Tables.Offset_Log,
                  Tables.Max_Offset_Code, Current.Offset, Status);
            if Status /= Ok then
               return;
            end if;

            Load (Mat_Mode, Tables.Match_Default, Tables.Match_Log,
                  Tables.Max_Match_Code, Current.Match, Status);
            if Status /= Ok then
               return;
            end if;

            Current.Have := True;
            Seq_Prev := Current;

            if Cursor > Data'Last then
               Status := Unexpected_End_Of_Input;
               return;
            end if;

            --  The sequence bitstream runs to the end of the section.
            declare
               Stream : constant Byte_Array := Data (Cursor .. Data'Last);
               R      : Stream_Bits.Backward_Reader;

               Lit_State : Natural;
               Off_State : Natural;
               Mat_State : Natural;
            begin
               Stream_Bits.Start (R, Stream, Status);
               if Status /= Ok then
                  return;
               end if;

               --  States are initialised literal, offset, match -- in that
               --  order, which is not the order they are then updated in.
               FSE.Init_Decode (Current.Literal, R, Stream, Lit_State, Status);
               if Status /= Ok then
                  return;
               end if;
               FSE.Init_Decode (Current.Offset, R, Stream, Off_State, Status);
               if Status /= Ok then
                  return;
               end if;
               FSE.Init_Decode (Current.Match, R, Stream, Mat_State, Status);
               if Status /= Ok then
                  return;
               end if;

               for Index in 1 .. Count loop
                  declare
                     Lit_Code : constant Natural :=
                       FSE.Symbol (Current.Literal, Lit_State);
                     Off_Code : constant Natural :=
                       FSE.Symbol (Current.Offset, Off_State);
                     Mat_Code : constant Natural :=
                       FSE.Symbol (Current.Match, Mat_State);

                     Offset_Value : Natural;
                     Match_Length : Natural;
                     Lit_Length   : Natural;
                     Offset       : Natural;
                  begin
                     if Lit_Code > Tables.Max_Literal_Code
                       or else Mat_Code > Tables.Max_Match_Code
                       or else Off_Code > 31
                     then
                        Status := Invalid_Huffman_Code;
                        return;
                     end if;

                     --  Extra bits are read offset first, then match, then
                     --  literal -- the reverse of how the codes were listed.
                     declare
                        Raw : Interfaces.Unsigned_32;
                     begin
                        Raw :=
                          Stream_Bits.Read (R, Stream, Off_Code, Status);
                        if Status /= Ok then
                           return;
                        end if;
                        Offset_Value := 2 ** Off_Code + Natural (Raw);

                        Raw :=
                          Stream_Bits.Read
                            (R, Stream,
                             Tables.Match_Extra_Bits (Mat_Code), Status);
                        if Status /= Ok then
                           return;
                        end if;
                        Match_Length :=
                          Tables.Match_Baseline (Mat_Code) + Natural (Raw);

                        Raw :=
                          Stream_Bits.Read
                            (R, Stream,
                             Tables.Literal_Extra_Bits (Lit_Code), Status);
                        if Status /= Ok then
                           return;
                        end if;
                        Lit_Length :=
                          Tables.Literal_Baseline (Lit_Code) + Natural (Raw);
                     end;

                     --  Offsets 1 .. 3 name one of the three remembered
                     --  offsets rather than a literal distance, and a zero
                     --  literal length shifts which one they name.
                     if Offset_Value > 3 then
                        Offset := Offset_Value - 3;
                        Repeat_3 := Repeat_2;
                        Repeat_2 := Repeat_1;
                        Repeat_1 := Offset;
                     else
                        declare
                           Slot : Natural := Offset_Value;
                        begin
                           if Lit_Length = 0 then
                              Slot := Slot + 1;
                           end if;

                           case Slot is
                              when 1 =>
                                 Offset := Repeat_1;
                              when 2 =>
                                 Offset := Repeat_2;
                                 Repeat_2 := Repeat_1;
                                 Repeat_1 := Offset;
                              when 3 =>
                                 Offset := Repeat_3;
                                 Repeat_3 := Repeat_2;
                                 Repeat_2 := Repeat_1;
                                 Repeat_1 := Offset;
                              when 4 =>
                                 if Repeat_1 <= 1 then
                                    Status := Invalid_Distance;
                                    return;
                                 end if;
                                 Offset := Repeat_1 - 1;
                                 Repeat_3 := Repeat_2;
                                 Repeat_2 := Repeat_1;
                                 Repeat_1 := Offset;
                              when others =>
                                 Status := Invalid_Distance;
                                 return;
                           end case;
                        end;
                     end if;

                     if Lit_Taken + Lit_Length - 1 > Lits'Last then
                        Status := Unexpected_End_Of_Input;
                        return;
                     end if;

                     --  The literals land first: a match may legitimately reach
                     --  back into them, so the offset can only be checked once
                     --  they are in place.
                     for Unused_Step in 1 .. Lit_Length loop
                        Output.Append (Lits (Lit_Taken));
                        Lit_Taken := Lit_Taken + 1;
                     end loop;

                     if Offset = 0
                       or else Offset > Natural (Output.Length)
                     then
                        Status := Invalid_Distance;
                        return;
                     end if;


                     --  Overlapping copies are allowed and common; copy one byte
                     --  at a time so a match can repeat what it just produced.
                     --  The byte is lifted out first: reading the vector inside
                     --  its own Append is a tampering error.
                     for Unused_Step in 1 .. Match_Length loop
                        declare
                           Item : constant Byte :=
                             Output (Natural (Output.Length) - Offset);
                        begin
                           Output.Append (Item);
                        end;
                     end loop;

                     if Index < Count then
                        --  Updated literal, match, offset -- a different order
                        --  again from the initialisation.
                        FSE.Advance
                          (Current.Literal, R, Stream, Lit_State, Status);
                        if Status /= Ok then
                           return;
                        end if;
                        FSE.Advance
                          (Current.Match, R, Stream, Mat_State, Status);
                        if Status /= Ok then
                           return;
                        end if;
                        FSE.Advance
                          (Current.Offset, R, Stream, Off_State, Status);
                        if Status /= Ok then
                           return;
                        end if;
                     end if;
                  end;
               end loop;
            end;
         end;

         --  Whatever literals the sequences did not consume trail the block.
         for Index in Lit_Taken .. Lits'Last loop
            Output.Append (Lits (Index));
         end loop;
      end Decode_Sequences;

      ------------------------------------------------------------------------

      procedure Decode_Block (Size : Natural; Status : out Status_Code) is
         Cursor : Natural := Position;
         Stop   : constant Natural := Position + Size - 1;
      begin
         Status := Ok;

         if Stop > Payload'Last then
            Status := Unexpected_End_Of_Input;
            return;
         end if;

         --  Literals section.
         declare
            Header    : constant Natural := Natural (Payload (Cursor));
            Kind      : constant Natural := Header mod 4;
            Format    : constant Natural := (Header / 4) mod 4;
            Regen     : Natural := 0;
            Comp_Size : Natural := 0;
            Streams   : Natural := 1;
         begin
            case Kind is
               when 0 | 1 =>
                  --  Raw or single-byte-run literals.
                  case Format is
                     when 0 | 2 =>
                        Regen := Header / 8;
                        Cursor := Cursor + 1;
                     when 1 =>
                        if Cursor + 1 > Stop then
                           Status := Unexpected_End_Of_Input;
                           return;
                        end if;
                        Regen :=
                          (Header / 16)
                          + Natural (Payload (Cursor + 1)) * 16;
                        Cursor := Cursor + 2;
                     when others =>
                        if Cursor + 2 > Stop then
                           Status := Unexpected_End_Of_Input;
                           return;
                        end if;
                        Regen :=
                          (Header / 16)
                          + Natural (Payload (Cursor + 1)) * 16
                          + Natural (Payload (Cursor + 2)) * 4_096;
                        Cursor := Cursor + 3;
                  end case;

                  declare
                     Lits : Byte_Array (1 .. Regen);
                  begin
                     if Kind = 0 then
                        if Cursor + Regen - 1 > Stop then
                           Status := Unexpected_End_Of_Input;
                           return;
                        end if;
                        for Index in Lits'Range loop
                           Lits (Index) := Payload (Cursor + Index - 1);
                        end loop;
                        Cursor := Cursor + Regen;
                     else
                        if Cursor > Stop then
                           Status := Unexpected_End_Of_Input;
                           return;
                        end if;
                        Lits := [others => Payload (Cursor)];
                        Cursor := Cursor + 1;
                     end if;

                     Decode_Sequences
                       (Payload (Cursor .. Stop), Lits, Status);
                     return;
                  end;

               when 2 | 3 =>
                  --  Huffman-coded literals; kind 3 reuses the previous tree.
                  case Format is
                     when 0 | 1 =>
                        if Cursor + 2 > Stop then
                           Status := Unexpected_End_Of_Input;
                           return;
                        end if;
                        declare
                           Raw : constant Natural :=
                             Natural (Read_LE (Payload, Cursor, 3));
                        begin
                           Regen := (Raw / 16) mod 1_024;
                           Comp_Size := (Raw / 16_384) mod 1_024;
                        end;
                        Streams := (if Format = 0 then 1 else 4);
                        Cursor := Cursor + 3;

                     when 2 =>
                        if Cursor + 3 > Stop then
                           Status := Unexpected_End_Of_Input;
                           return;
                        end if;
                        declare
                           Raw : constant Natural :=
                             Natural (Read_LE (Payload, Cursor, 4));
                        begin
                           Regen := (Raw / 16) mod 16_384;
                           Comp_Size := (Raw / 262_144) mod 16_384;
                        end;
                        Streams := 4;
                        Cursor := Cursor + 4;

                     when others =>
                        if Cursor + 4 > Stop then
                           Status := Unexpected_End_Of_Input;
                           return;
                        end if;
                        declare
                           Raw : constant Interfaces.Unsigned_64 :=
                             Read_LE (Payload, Cursor, 5);
                        begin
                           Regen :=
                             Natural
                               (Interfaces.Shift_Right (Raw, 4)
                                mod 262_144);
                           Comp_Size :=
                             Natural
                               (Interfaces.Shift_Right (Raw, 22)
                                mod 262_144);
                        end;
                        Streams := 4;
                        Cursor := Cursor + 5;
                  end case;

                  if Cursor + Comp_Size - 1 > Stop then
                     Status := Unexpected_End_Of_Input;
                     return;
                  end if;

                  declare
                     Section : constant Byte_Array :=
                       Payload (Cursor .. Cursor + Comp_Size - 1);
                     Table   : Huffman.Decode_Table;
                     Used    : Natural := 0;
                     Lits    : Byte_Array (1 .. Regen);
                  begin
                     if Kind = 2 then
                        Huffman.Read_Table
                          (Section, Section'First, Table, Used, Status);
                        if Status /= Ok then
                           return;
                        end if;
                        Huff_Prev := Table;
                        Have_Huff := True;
                     else
                        if not Have_Huff then
                           Status := Invalid_Huffman_Code;
                           return;
                        end if;
                        Table := Huff_Prev;
                     end if;

                     declare
                        Body_First : constant Natural :=
                          Section'First + Used;
                     begin
                        if Body_First > Section'Last then
                           Status := Unexpected_End_Of_Input;
                           return;
                        end if;

                        if Streams = 1 then
                           Huffman.Decode_Stream
                             (Table,
                              Section (Body_First .. Section'Last),
                              Lits, Status);
                           if Status /= Ok then
                              return;
                           end if;
                        else
                           --  Four streams, preceded by a jump table giving the
                           --  first three compressed sizes.
                           if Body_First + 5 > Section'Last then
                              Status := Unexpected_End_Of_Input;
                              return;
                           end if;

                           declare
                              S1 : constant Natural :=
                                Natural (Read_LE (Section, Body_First, 2));
                              S2 : constant Natural :=
                                Natural (Read_LE (Section, Body_First + 2, 2));
                              S3 : constant Natural :=
                                Natural (Read_LE (Section, Body_First + 4, 2));
                              Start : constant Natural := Body_First + 6;
                              Total : constant Natural :=
                                Section'Last - Start + 1;
                              S4    : Integer;

                              Quarter : constant Natural := (Regen + 3) / 4;
                              Offsets : array (1 .. 4) of Natural;
                              Sizes   : array (1 .. 4) of Natural;
                           begin
                              S4 := Total - S1 - S2 - S3;
                              if S4 < 0 then
                                 Status := Unexpected_End_Of_Input;
                                 return;
                              end if;

                              Sizes := [S1, S2, S3, Natural (S4)];
                              Offsets (1) := Start;
                              Offsets (2) := Offsets (1) + S1;
                              Offsets (3) := Offsets (2) + S2;
                              Offsets (4) := Offsets (3) + S3;

                              for Part in 1 .. 4 loop
                                 declare
                                    From : constant Natural :=
                                      (Part - 1) * Quarter + 1;
                                    To   : constant Natural :=
                                      (if Part = 4 then Regen
                                       else Natural'Min (Part * Quarter,
                                                         Regen));
                                 begin
                                    if From > Regen then
                                       exit;
                                    end if;

                                    Huffman.Decode_Stream
                                      (Table,
                                       Section
                                         (Offsets (Part)
                                          .. Offsets (Part)
                                             + Sizes (Part) - 1),
                                       Lits (From .. To),
                                       Status);
                                    if Status /= Ok then
                                       return;
                                    end if;
                                 end;
                              end loop;
                           end;
                        end if;
                     end;

                     Cursor := Cursor + Comp_Size;
                     Decode_Sequences
                       (Payload (Cursor .. Stop), Lits, Status);
                     return;
                  end;

               when others =>
                  Status := Invalid_Block_Type;
                  return;
            end case;
         end;
      end Decode_Block;

   begin
      Status := Ok;

      if Payload'Length < 4 then
         Status := Unexpected_End_Of_Input;
         return Empty;
      end if;

      while Position + 3 <= Payload'Last loop
         Skippable := False;

         declare
            Signature : constant Interfaces.Unsigned_32 :=
              Interfaces.Unsigned_32 (Read_LE (Payload, Position, 4));
         begin
            --  Skippable frames carry a size and no content.
            if (Signature and 16#FFFF_FFF0#) = Skip_Magic_Low then
               if Position + 7 > Payload'Last then
                  Status := Unexpected_End_Of_Input;
                  return Empty;
               end if;
               declare
                  Size : constant Natural :=
                    Natural (Read_LE (Payload, Position + 4, 4));
               begin
                  Position := Position + 8 + Size;
               end;
               Skippable := True;

            elsif Signature /= Magic then
               Status := Invalid_Header;
               return Empty;
            end if;
         end;

         if not Skippable then
            Position := Position + 4;
            Frame_Start := Natural (Output.Length);

            --  Frame header.
            declare
               Descriptor : Natural;
               Size_Flag  : Natural;
               Single_Seg : Boolean;
               Check_Flag : Boolean;
               Dict_Flag  : Natural;
               Size_Width : Natural;
               Has_Check  : Boolean;
            begin
               if Position > Payload'Last then
                  Status := Unexpected_End_Of_Input;
                  return Empty;
               end if;

               Descriptor := Natural (Payload (Position));
               Position := Position + 1;

               Size_Flag := Descriptor / 64;
               Single_Seg := (Descriptor / 32) mod 2 = 1;
               Check_Flag := (Descriptor / 4) mod 2 = 1;
               Dict_Flag := Descriptor mod 4;
               Has_Check := Check_Flag;

               if (Descriptor / 8) mod 2 = 1 then
                  --  Reserved bit; a frame that sets it is not one we understand.
                  Status := Invalid_Header;
                  return Empty;
               end if;

               if Dict_Flag /= 0 then
                  --  A dictionary we do not have; refuse rather than decode wrong.
                  Status := Unsupported_Method;
                  return Empty;
               end if;

               if not Single_Seg then
                  --  Window descriptor; the window only bounds memory, and the
                  --  whole output is kept, so nothing here needs acting on.
                  if Position > Payload'Last then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;
                  Position := Position + 1;
               end if;

               Size_Width :=
                 (case Size_Flag is
                    when 0 => (if Single_Seg then 1 else 0),
                    when 1 => 2,
                    when 2 => 4,
                    when others => 8);

               if Size_Width > 0 then
                  if Position + Size_Width - 1 > Payload'Last then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;
                  Position := Position + Size_Width;
               end if;

               --  Blocks.
               loop
                  if Position + 2 > Payload'Last then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;

                  declare
                     Header : constant Natural :=
                       Natural (Read_LE (Payload, Position, 3));
                     Last   : constant Boolean := Header mod 2 = 1;
                     Kind   : constant Natural := (Header / 2) mod 4;
                     Size   : constant Natural := Header / 8;
                  begin
                     Position := Position + 3;

                     case Kind is
                        when 0 =>
                           if Position + Size - 1 > Payload'Last then
                              Status := Unexpected_End_Of_Input;
                              return Empty;
                           end if;
                           for Index in 0 .. Size - 1 loop
                              Output.Append (Payload (Position + Index));
                           end loop;
                           Position := Position + Size;

                        when 1 =>
                           if Position > Payload'Last then
                              Status := Unexpected_End_Of_Input;
                              return Empty;
                           end if;
                           for Unused_Index in 1 .. Size loop
                              Output.Append (Payload (Position));
                           end loop;
                           Position := Position + 1;

                        when 2 =>
                           Decode_Block (Size, Status);
                           if Status /= Ok then
                              return Empty;
                           end if;
                           Position := Position + Size;

                        when others =>
                           Status := Invalid_Block_Type;
                           return Empty;
                     end case;

                     exit when Last;
                  end;
               end loop;

               if Has_Check then
                  if Position + 3 > Payload'Last then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;

                  declare
                     Stored : constant Interfaces.Unsigned_32 :=
                       Interfaces.Unsigned_32 (Read_LE (Payload, Position, 4));
                     Content : constant Byte_Array :=
                       To_Array (Output) (Frame_Start + 1 .. Natural (Output.Length));
                     Actual : constant Interfaces.Unsigned_32 :=
                       Interfaces.Unsigned_32
                         (Zlib.Zstd_XXH64.Compute (Content)
                          and 16#FFFF_FFFF#);
                  begin
                     if Stored /= Actual then
                        Status := Invalid_Checksum;
                        return Empty;
                     end if;
                  end;

                  Position := Position + 4;
               end if;
            end;
         end if;

         exit when Position > Payload'Last;
      end loop;

      Status := Ok;
      return To_Array (Output);
   end Decode;

end Zlib.Zstd_Decoder;
