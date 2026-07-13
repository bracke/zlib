with Zlib.BZip2_Lengths;
with Zlib.Zstd_Bits;
with Zlib.Zstd_FSE;

package body Zlib.Zstd_Huffman is

   use type Interfaces.Unsigned_32;

   package Stream_Bits renames Zlib.Zstd_Bits;
   package FSE renames Zlib.Zstd_FSE;
   package Tables renames Zlib.Zstd_Tables;

   Weight_Log    : constant Natural := 6;
   Max_Weight    : constant Natural := Max_Bits + 1;
   Direct_Limit  : constant Natural := 128;
   --  The packed-nibble form encodes its symbol count in a single byte as
   --  127 + count, so it cannot express more than 128 weights.

   procedure Finish_Weights
     (Weights : in out Length_Array;
      Count   : Natural;
      Log     : out Natural;
      Status  : out Status_Code);
   --  Infer the final symbol's weight and derive the code length ceiling.

   procedure Fill_Decode
     (Weights : Length_Array;
      Count   : Natural;
      Log     : Natural;
      Table   : out Decode_Table);

   procedure Finish_Weights
     (Weights : in out Length_Array;
      Count   : Natural;
      Log     : out Natural;
      Status  : out Status_Code)
   is
      Total : Natural := 0;
      Rest  : Natural;
   begin
      Log := 0;
      Status := Ok;

      for Index in 0 .. Count - 1 loop
         if Weights (Index) > Max_Weight then
            Status := Invalid_Huffman_Code;
            return;
         end if;
         if Weights (Index) > 0 then
            Total := Total + 2 ** (Weights (Index) - 1);
         end if;
      end loop;

      if Total = 0 then
         Status := Invalid_Huffman_Code;
         return;
      end if;

      --  The weights so far imply a Kraft sum; the last symbol takes up exactly
      --  the slack to the next power of two.
      Log := Tables.Highest_Bit (Total) + 1;
      if Log > Max_Bits then
         Status := Invalid_Huffman_Code;
         return;
      end if;

      Rest := 2 ** Log - Total;
      if Rest = 0 or else 2 ** Tables.Highest_Bit (Rest) /= Rest then
         Status := Invalid_Huffman_Code;
         return;
      end if;

      Weights (Count) := Tables.Highest_Bit (Rest) + 1;
   end Finish_Weights;

   procedure Fill_Decode
     (Weights : Length_Array;
      Count   : Natural;
      Log     : Natural;
      Table   : out Decode_Table)
   is
      Rank_Start : array (0 .. Max_Weight) of Natural := [others => 0];
      Cursor     : Natural := 0;
   begin
      Table.Log := Log;
      Table.Entries := [others => (0, 0)];

      --  Slots are laid out by ascending weight, i.e. descending code length.
      for Weight in 1 .. Log loop
         Rank_Start (Weight) := Cursor;
         for Symbol in 0 .. Count loop
            if Weights (Symbol) = Weight then
               Cursor := Cursor + 2 ** (Weight - 1);
            end if;
         end loop;
      end loop;

      for Symbol in 0 .. Count loop
         declare
            Weight : constant Natural := Weights (Symbol);
         begin
            if Weight > 0 then
               declare
                  Span   : constant Natural := 2 ** (Weight - 1);
                  Start  : constant Natural := Rank_Start (Weight);
                  Length : constant Natural := Log + 1 - Weight;
               begin
                  for Slot in Start .. Start + Span - 1 loop
                     Table.Entries (Slot) :=
                       (Symbol => Byte (Symbol), Bits => Length);
                  end loop;
                  Rank_Start (Weight) := Start + Span;
               end;
            end if;
         end;
      end loop;
   end Fill_Decode;

   procedure Read_Table
     (Data   : Byte_Array;
      First  : Natural;
      Table  : out Decode_Table;
      Used   : out Natural;
      Status : out Status_Code)
   is
      Weights : Length_Array := [others => 0];
      Count   : Natural := 0;
      Log     : Natural := 0;
      Header  : Byte;
   begin
      Table := (Entries => [others => (0, 0)], Log => 0);
      Used := 0;
      Status := Ok;

      if First > Data'Last then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      Header := Data (First);

      if Natural (Header) >= Direct_Limit then
         --  Packed nibbles, most significant first.
         Count := Natural (Header) - 127;
         Used := 1 + (Count + 1) / 2;

         if First + Used - 1 > Data'Last then
            Status := Unexpected_End_Of_Input;
            return;
         end if;

         for Index in 0 .. Count - 1 loop
            declare
               Item : constant Byte := Data (First + 1 + Index / 2);
            begin
               if Index mod 2 = 0 then
                  Weights (Index) := Natural (Item) / 16;
               else
                  Weights (Index) := Natural (Item) mod 16;
               end if;
            end;
         end loop;

      else
         --  FSE-compressed weights, two interleaved states.
         declare
            Size : constant Natural := Natural (Header);
         begin
            Used := 1 + Size;
            if Size = 0 or else First + Used - 1 > Data'Last then
               Status := Unexpected_End_Of_Input;
               return;
            end if;

            declare
               Counts     : Tables.Count_Array (0 .. Max_Weight) :=
                 [others => 0];
               Table_Log  : Natural;
               Last_Code  : Natural;
               Header_Len : Natural;
               Decode     : FSE.Decode_Table;
               R          : Stream_Bits.Backward_Reader;
               State_1    : Natural;
               State_2    : Natural;
            begin
               FSE.Read_Counts
                 (Data      => Data,
                  First     => First + 1,
                  Max_Code  => Max_Weight,
                  Counts    => Counts,
                  Log       => Table_Log,
                  Last_Code => Last_Code,
                  Used      => Header_Len,
                  Status    => Status);
               if Status /= Ok then
                  return;
               end if;

               FSE.Build_Decode (Counts, Table_Log, Decode, Status);
               if Status /= Ok then
                  return;
               end if;

               declare
                  Stream : constant Byte_Array :=
                    Data (First + 1 + Header_Len .. First + Used - 1);
               begin
                  if Stream'Length = 0 then
                     Status := Unexpected_End_Of_Input;
                     return;
                  end if;

                  Stream_Bits.Start (R, Stream, Status);
                  if Status /= Ok then
                     return;
                  end if;

                  FSE.Init_Decode (Decode, R, Stream, State_1, Status);
                  if Status /= Ok then
                     return;
                  end if;
                  FSE.Init_Decode (Decode, R, Stream, State_2, Status);
                  if Status /= Ok then
                     return;
                  end if;

                  --  The two states take turns. The count is not stored: the
                  --  stream simply runs out, and when it does BOTH states still
                  --  hold an undecoded symbol, so two more are emitted. Checking
                  --  exhaustion before the transition, not after, is what makes
                  --  the count come out right.
                  Count := 0;
                  loop
                     if Count > Max_Symbol - 1 then
                        Status := Invalid_Huffman_Code;
                        return;
                     end if;

                     Weights (Count) := FSE.Symbol (Decode, State_1);
                     Count := Count + 1;

                     if Stream_Bits.Exhausted (R) then
                        Weights (Count) := FSE.Symbol (Decode, State_2);
                        Count := Count + 1;
                        exit;
                     end if;

                     FSE.Advance (Decode, R, Stream, State_1, Status);
                     if Status /= Ok then
                        return;
                     end if;

                     Weights (Count) := FSE.Symbol (Decode, State_2);
                     Count := Count + 1;

                     if Stream_Bits.Exhausted (R) then
                        Weights (Count) := FSE.Symbol (Decode, State_1);
                        Count := Count + 1;
                        exit;
                     end if;

                     FSE.Advance (Decode, R, Stream, State_2, Status);
                     if Status /= Ok then
                        return;
                     end if;
                  end loop;

               end;
            end;
         end;
      end if;

      if Count = 0 or else Count > Max_Symbol then
         Status := Invalid_Huffman_Code;
         return;
      end if;

      Finish_Weights (Weights, Count, Log, Status);
      if Status /= Ok then
         return;
      end if;

      Fill_Decode (Weights, Count, Log, Table);
   end Read_Table;

   procedure Decode_Stream
     (Table  : Decode_Table;
      Data   : Byte_Array;
      Output : out Byte_Array;
      Status : out Status_Code)
   is
      R : Stream_Bits.Backward_Reader;
   begin
      Output := [others => 0];

      Stream_Bits.Start (R, Data, Status);
      if Status /= Ok then
         return;
      end if;

      for Index in Output'Range loop
         declare
            Slot : constant Natural :=
              Natural (Stream_Bits.Peek (R, Data, Table.Log));
            Item : constant Entry_Record := Table.Entries (Slot);
         begin
            if Item.Bits = 0 then
               Status := Invalid_Huffman_Code;
               return;
            end if;

            Output (Index) := Item.Symbol;
            Stream_Bits.Skip (R, Item.Bits, Status);
            if Status /= Ok then
               return;
            end if;
         end;
      end loop;
   end Decode_Stream;

   procedure Build_Encode
     (Frequencies : Tables.Value_Array;
      Table       : out Encode_Table;
      Usable      : out Boolean;
      Status      : out Status_Code)
   is
      Present : Natural := 0;
      Highest : Natural := 0;
      Log     : Natural := 0;
   begin
      Table := (Lengths => [others => 0],
                Codes => [others => 0],
                Weights => [others => 0],
                Log => 0,
                Last_Used => 0);
      Usable := False;
      Status := Ok;

      for Symbol in 0 .. Max_Symbol loop
         if Frequencies (Symbol) > 0 then
            Present := Present + 1;
            Highest := Symbol;
         end if;
      end loop;

      if Present < 2 then
         --  A single symbol has no Huffman code; the caller sends raw literals.
         return;
      end if;

      --  Build bounded Huffman lengths over just the symbols that occur. The
      --  bzip2 length builder does exactly this job -- a real Huffman tree with a
      --  hard length cap -- so it is reused rather than written twice.
      declare
         Compact : Zlib.BZip2_Lengths.Frequency_Array (0 .. Present - 1);
         Lengths : Zlib.BZip2_Lengths.Length_Array (0 .. Present - 1);
         Symbols : array (0 .. Present - 1) of Natural;
         Cursor  : Natural := 0;
      begin
         for Symbol in 0 .. Max_Symbol loop
            if Frequencies (Symbol) > 0 then
               Compact (Cursor) := Frequencies (Symbol);
               Symbols (Cursor) := Symbol;
               Cursor := Cursor + 1;
            end if;
         end loop;

         Zlib.BZip2_Lengths.Make_Code_Lengths (Compact, Lengths, Max_Bits);

         for Index in Lengths'Range loop
            Table.Lengths (Symbols (Index)) := Lengths (Index);
            Log := Natural'Max (Log, Lengths (Index));
         end loop;
      end;

      if Log = 0 or else Log > Max_Bits then
         Status := Invalid_Huffman_Code;
         return;
      end if;

      Table.Log := Log;
      Table.Last_Used := Highest;

      for Symbol in 0 .. Max_Symbol loop
         if Table.Lengths (Symbol) > 0 then
            Table.Weights (Symbol) := Log + 1 - Table.Lengths (Symbol);
         end if;
      end loop;

      --  Codes must agree with how the decode table is laid out: ascending
      --  weight, and ascending symbol within a weight.
      declare
         Rank_Start : array (0 .. Max_Weight) of Natural := [others => 0];
         Cursor     : Natural := 0;
      begin
         for Weight in 1 .. Log loop
            Rank_Start (Weight) := Cursor;
            for Symbol in 0 .. Max_Symbol loop
               if Table.Weights (Symbol) = Weight then
                  Cursor := Cursor + 2 ** (Weight - 1);
               end if;
            end loop;
         end loop;

         for Symbol in 0 .. Max_Symbol loop
            declare
               Weight : constant Natural := Table.Weights (Symbol);
            begin
               if Weight > 0 then
                  Table.Codes (Symbol) :=
                    Interfaces.Unsigned_32
                      (Rank_Start (Weight) / 2 ** (Weight - 1));
                  Rank_Start (Weight) :=
                    Rank_Start (Weight) + 2 ** (Weight - 1);
               end if;
            end;
         end loop;
      end;

      Usable := True;
   end Build_Encode;

   procedure Write_Table
     (Table  : Encode_Table;
      Output : out Byte_Array;
      Length : out Natural;
      Usable : out Boolean;
      Status : out Status_Code)
   is
      Count : constant Natural := Table.Last_Used;
      --  The final symbol's weight is inferred, so only the ones below it are
      --  written.
   begin
      Output := [others => 0];
      Length := 0;
      Usable := False;
      Status := Ok;

      if Count = 0 then
         Status := Invalid_Huffman_Code;
         return;
      end if;

      if Count <= Direct_Limit then
         Length := 1 + (Count + 1) / 2;
         if Length > Output'Length then
            Status := Invalid_Huffman_Code;
            Length := 0;
            return;
         end if;

         Output (Output'First) := Byte (127 + Count);

         for Index in 0 .. Count - 1 loop
            declare
               Slot : constant Natural := Output'First + 1 + Index / 2;
            begin
               if Index mod 2 = 0 then
                  Output (Slot) :=
                    Output (Slot) or Byte (Table.Weights (Index) * 16);
               else
                  Output (Slot) :=
                    Output (Slot) or Byte (Table.Weights (Index));
               end if;
            end;
         end loop;

         Usable := True;
         return;
      end if;

      --  Too many weights for the packed form: FSE-compress them.
      declare
         Frequencies : Tables.Value_Array (0 .. Max_Weight) := [others => 0];
         Counts      : Tables.Count_Array (0 .. Max_Weight) := [others => 0];
         Highest     : Natural := 0;
         Encode      : FSE.Encode_Table;
         Header      : Byte_Array (1 .. 64);
         Header_Len  : Natural;
         W           : Stream_Bits.Backward_Writer;
         State_1     : Natural;
         State_2     : Natural;
         Cursor      : Integer;
      begin
         for Index in 0 .. Count - 1 loop
            Frequencies (Table.Weights (Index)) :=
              Frequencies (Table.Weights (Index)) + 1;
            Highest := Natural'Max (Highest, Table.Weights (Index));
         end loop;

         --  A single weight value costs zero bits per symbol, and the decoder
         --  recovers the count from where the bits run out -- so such a stream
         --  is undecodable. Refuse, and let the caller send raw literals.
         declare
            Distinct : Natural := 0;
         begin
            for Weight in 0 .. Max_Weight loop
               if Frequencies (Weight) > 0 then
                  Distinct := Distinct + 1;
               end if;
            end loop;

            if Distinct < 2 then
               return;
            end if;
         end;

         FSE.Normalize
           (Frequencies => Frequencies,
            Total       => Count,
            Max_Code    => Highest,
            Log         => Weight_Log,
            Counts      => Counts,
            Status      => Status);
         if Status /= Ok then
            return;
         end if;

         FSE.Write_Counts
           (Counts   => Counts,
            Log      => Weight_Log,
            Max_Code => Highest,
            Output   => Header,
            Length   => Header_Len,
            Status   => Status);
         if Status /= Ok then
            return;
         end if;

         FSE.Build_Encode (Counts, Weight_Log, Encode, Status);
         if Status /= Ok then
            return;
         end if;

         --  Encode backwards, with the two states taking alternate symbols so
         --  that the decoder, reading forwards, sees state one on even indices.
         Stream_Bits.Reset (W);
         Cursor := Count - 1;

         if Count mod 2 = 1 then
            FSE.Init_Encode (Encode, Table.Weights (Cursor), State_1, W);
            Cursor := Cursor - 1;
            FSE.Init_Encode (Encode, Table.Weights (Cursor), State_2, W);
            Cursor := Cursor - 1;
            FSE.Encode (Encode, Table.Weights (Cursor), State_1, W);
            Cursor := Cursor - 1;
         else
            FSE.Init_Encode (Encode, Table.Weights (Cursor), State_2, W);
            Cursor := Cursor - 1;
            FSE.Init_Encode (Encode, Table.Weights (Cursor), State_1, W);
            Cursor := Cursor - 1;
         end if;

         while Cursor >= 0 loop
            FSE.Encode (Encode, Table.Weights (Cursor), State_2, W);
            Cursor := Cursor - 1;
            exit when Cursor < 0;
            FSE.Encode (Encode, Table.Weights (Cursor), State_1, W);
            Cursor := Cursor - 1;
         end loop;

         FSE.Flush_Encode (Encode, State_2, W);
         FSE.Flush_Encode (Encode, State_1, W);

         declare
            Stream : constant Byte_Array := Stream_Bits.Finish (W);
            Total  : constant Natural := Header_Len + Stream'Length;
         begin
            if Total >= Direct_Limit or else 1 + Total > Output'Length then
               --  The description must fit in a header byte below 128.
               return;
            end if;

            Output (Output'First) := Byte (Total);
            for Index in 1 .. Header_Len loop
               Output (Output'First + Index) := Header (Index);
            end loop;
            for Index in Stream'Range loop
               Output (Output'First + Header_Len + Index) := Stream (Index);
            end loop;

            Length := 1 + Total;
            Usable := True;
         end;
      end;
   end Write_Table;

   function Coded_Bits
     (Table : Encode_Table;
      Plain : Byte_Array) return Natural
   is
      Total : Natural := 0;
   begin
      for Item of Plain loop
         Total := Total + Table.Lengths (Natural (Item));
      end loop;
      return Total;
   end Coded_Bits;

   procedure Encode_Stream
     (Table  : Encode_Table;
      Plain  : Byte_Array;
      Output : out Byte_Array;
      Length : out Natural;
      Status : out Status_Code)
   is
      W : Stream_Bits.Backward_Writer;
   begin
      Output := [others => 0];
      Length := 0;
      Status := Ok;

      Stream_Bits.Reset (W);

      --  Written back to front, so the decoder reads the literals in order.
      for Index in reverse Plain'Range loop
         declare
            Symbol : constant Natural := Natural (Plain (Index));
         begin
            if Table.Lengths (Symbol) = 0 then
               Status := Invalid_Huffman_Code;
               return;
            end if;

            Stream_Bits.Write (W, Table.Codes (Symbol), Table.Lengths (Symbol));
         end;
      end loop;

      declare
         Stream : constant Byte_Array := Stream_Bits.Finish (W);
      begin
         if Stream'Length > Output'Length then
            Status := Invalid_Huffman_Code;
            return;
         end if;

         for Index in Stream'Range loop
            Output (Output'First + Index - Stream'First) := Stream (Index);
         end loop;
         Length := Stream'Length;
      end;
   end Encode_Stream;

end Zlib.Zstd_Huffman;
