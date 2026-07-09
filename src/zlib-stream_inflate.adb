with Zlib.Deflate_Tables;

package body Zlib.Stream_Inflate is
   use type Ada.Streams.Stream_Element;
   use type Interfaces.Unsigned_32;
   use type Zlib.Stream_Bits.Read_Status;
   use type Zlib.Sliding_Window.Write_Status;

   Pending_Capacity : constant Natural := 64;

   procedure Fail
     (D            : in out Decoder;
      Status       : out Decode_Status;
      Kind         : Decode_Status;
      Public_Status : Zlib.Status_Code)
   is
   begin
      D.Inflate := Failed;
      D.Wrapper := Failed;
      D.Last_Status := Public_Status;
      Status := Kind;
   end Fail;

   function Has_Non_Zero_Length
     (Lengths : Zlib.Huffman.Code_Length_Array)
      return Boolean
      with SPARK_Mode => On
   is
   begin
      for I in Lengths'Range loop
         if Lengths (I) /= 0 then
            return True;
         end if;
      end loop;

      return False;
   end Has_Non_Zero_Length;

   procedure Reset_Dynamic_State
     (D : in out Decoder)
   is
   begin
      D.Dynamic_HLIT := 0;
      D.Dynamic_HDIST := 0;
      D.Dynamic_HCLEN := 0;
      D.Dynamic_Code_Length_Index := 0;
      D.Dynamic_Length_Index := 0;
      D.Dynamic_Total_Lengths := 0;
      D.Code_Length_Lengths := [others => 0];
      D.All_Lengths := [others => 0];
      Zlib.Huffman.Clear (D.Code_Length_Table);
      D.Previous_Code_Length := 0;
      D.Have_Previous_Length := False;
      D.Pending_Repeat_Symbol := 0;
      D.Have_Pending_Repeat := False;
   end Reset_Dynamic_State;

   procedure Reset
     (D : in out Decoder)
   is
   begin
      D.Inflate := Need_Block_Header;
      D.Wrapper := Need_CMF;
      D.Active_Header := Zlib.Default;
      D.BFinal := False;
      D.CMF := 0;
      D.FLG := 0;
      D.Len := 0;
      D.NLen := 0;
      D.Stored_Left := 0;
      D.Dist_Table_Empty := False;
      Zlib.Huffman.Clear (D.Lit_Len_Table);
      Zlib.Huffman.Clear (D.Dist_Table);
      Reset_Dynamic_State (D);
      D.Huff_Code := 0;
      D.Huff_Length := 0;
      D.Symbol := 0;
      D.Length_Value := 0;
      D.Distance_Value := 0;
      D.Expected_Adler := 0;
      D.Expected_Dictionary_ID := 0;
      D.Dictionary_ID := 0;
      D.Dictionary_Supplied := False;
      CryptoLib.Checksums.Adler32_Reset (D.Adler);
      D.GZip_FLG := 0;
      D.GZip_XLEN := 0;
      D.GZip_Extra_Left := 0;
      CryptoLib.Checksums.CRC32_Reset (D.GZip_Header_CRC);
      CryptoLib.Checksums.CRC32_Reset (D.GZip_Data_CRC);
      D.GZip_HCRC := 0;
      D.GZip_Expected_CRC := 0;
      D.GZip_Expected_ISIZE := 0;
      D.GZip_ISIZE := 0;
      D.Last_Status := Zlib.Ok;
   end Reset;

   procedure Reset_GZip_Member
     (D : in out Decoder)
   is
   begin
      D.Inflate := Need_Block_Header;
      D.Wrapper := Need_GZip_ID1;
      D.Active_Header := Zlib.GZip;
      D.BFinal := False;
      D.CMF := 0;
      D.FLG := 0;
      D.Len := 0;
      D.NLen := 0;
      D.Stored_Left := 0;
      D.Dist_Table_Empty := False;
      Zlib.Huffman.Clear (D.Lit_Len_Table);
      Zlib.Huffman.Clear (D.Dist_Table);
      Reset_Dynamic_State (D);
      D.Huff_Code := 0;
      D.Huff_Length := 0;
      D.Symbol := 0;
      D.Length_Value := 0;
      D.Distance_Value := 0;
      D.Expected_Adler := 0;
      CryptoLib.Checksums.Adler32_Reset (D.Adler);
      D.GZip_FLG := 0;
      D.GZip_XLEN := 0;
      D.GZip_Extra_Left := 0;
      CryptoLib.Checksums.CRC32_Reset (D.GZip_Header_CRC);
      CryptoLib.Checksums.CRC32_Reset (D.GZip_Data_CRC);
      D.GZip_HCRC := 0;
      D.GZip_Expected_CRC := 0;
      D.GZip_Expected_ISIZE := 0;
      D.GZip_ISIZE := 0;
      D.Last_Status := Zlib.Ok;
   end Reset_GZip_Member;

   function Read_Byte
     (Source : in out Zlib.Stream_Bits.Bit_Source;
      Status : out Decode_Status)
      return Ada.Streams.Stream_Element
   is
      Read_Status : Zlib.Stream_Bits.Read_Status;
      B           : constant Ada.Streams.Stream_Element :=
        Zlib.Stream_Bits.Read_Byte_Aligned (Source, Read_Status);
   begin
      case Read_Status is
         when Zlib.Stream_Bits.Ok =>
            Status := Ok;
         when Zlib.Stream_Bits.Need_Input =>
            Status := Need_Input;
         when Zlib.Stream_Bits.Invalid_State =>
            Status := Malformed;
      end case;

      return B;
   end Read_Byte;

   function Header_Valid
     (CMF : Ada.Streams.Stream_Element;
      FLG : Ada.Streams.Stream_Element)
      return Boolean
     with SPARK_Mode => On
   is
      Combined : constant Natural := Natural (CMF) * 256 + Natural (FLG);
      CM       : constant Natural := Natural (CMF) mod 16;
      CINFO    : constant Natural := Natural (CMF) / 16;
   begin
      return CM = 8
        and then CINFO <= 7
        and then Combined mod 31 = 0;
   end Header_Valid;

   function FDICT_Set
     (FLG : Ada.Streams.Stream_Element)
      return Boolean
     with SPARK_Mode => On
   is
   begin
      return (Natural (FLG) / 32) mod 2 = 1;
   end FDICT_Set;

   procedure Set_Dictionary_ID
     (D       : in out Decoder;
      Dict_ID : Interfaces.Unsigned_32)
   is
   begin
      D.Dictionary_ID := Dict_ID;
      D.Dictionary_Supplied := True;
   end Set_Dictionary_ID;

   function Can_Set_Dictionary
     (D : Decoder)
      return Boolean
   is
   begin
      return D.Wrapper = Need_CMF and then D.Inflate = Need_Block_Header;
   end Can_Set_Dictionary;

   procedure Read_Bits_Incremental
     (D      : in out Decoder;
      Source : in out Zlib.Stream_Bits.Bit_Source;
      Count  : Natural;
      Value  : out Natural;
      Status : out Decode_Status)
   is
      Read_Status : Zlib.Stream_Bits.Read_Status;
      Chunk       : Natural;
   begin
      if Count = 0 then
         Value := 0;
         Status := Ok;
         return;
      end if;

      if D.Huff_Length = 0 then
         D.Huff_Code := 0;
      end if;

      while D.Huff_Length < Count loop
         Chunk := Zlib.Stream_Bits.Read_Bits (Source, 1, Read_Status);
         case Read_Status is
            when Zlib.Stream_Bits.Ok =>
               if Chunk = 1 then
                  D.Huff_Code := D.Huff_Code + 2 ** D.Huff_Length;
               end if;
               D.Huff_Length := D.Huff_Length + 1;
            when Zlib.Stream_Bits.Need_Input =>
               Value := 0;
               Status := Need_Input;
               return;
            when Zlib.Stream_Bits.Invalid_State =>
               D.Huff_Code := 0;
               D.Huff_Length := 0;
               Value := 0;
               Status := Malformed;
               return;
         end case;
      end loop;

      Value := D.Huff_Code;
      D.Huff_Code := 0;
      D.Huff_Length := 0;
      Status := Ok;
   end Read_Bits_Incremental;

   procedure Decode_Huffman_Symbol
     (D      : in out Decoder;
      Source : in out Zlib.Stream_Bits.Bit_Source;
      Table  : Zlib.Huffman.Decode_Table;
      Symbol : out Natural;
      Status : out Decode_Status)
   is
      Read_Status   : Zlib.Stream_Bits.Read_Status;
      Symbol_Status : Zlib.Status_Code;
      S             : Zlib.Huffman.Symbol_Value;
   begin
      S := Zlib.Huffman.Decode_Streaming
        (Source      => Source,
         Table       => Table,
         Code        => D.Huff_Code,
         Length      => D.Huff_Length,
         Read_Status => Read_Status,
         Status      => Symbol_Status);

      if Read_Status = Zlib.Stream_Bits.Need_Input then
         Symbol := 0;
         Status := Need_Input;
         return;
      elsif Read_Status = Zlib.Stream_Bits.Invalid_State
        or else Symbol_Status /= Zlib.Ok
      then
         Symbol := 0;
         Status := Malformed;
         return;
      end if;

      Symbol := Natural (S);
      Status := Ok;
   end Decode_Huffman_Symbol;

   procedure Decode_Code_Length_Symbol
     (D      : in out Decoder;
      Source : in out Zlib.Stream_Bits.Bit_Source;
      Status : out Decode_Status)
   is
      Extra          : Natural;
      Repeat         : Natural;
      Repeat_Symbol  : Natural;
      Decoded_Symbol : Natural;
   begin
      if D.Have_Pending_Repeat then
         Repeat_Symbol := D.Pending_Repeat_Symbol;
      else
         declare
            Table : Zlib.Huffman.Decode_Table renames D.Code_Length_Table;
         begin
            Decode_Huffman_Symbol
              (D, Source, Table, Decoded_Symbol, Status);
         end;
         if Status /= Ok then
            return;
         end if;

         D.Symbol := Decoded_Symbol;
         if Decoded_Symbol <= 15 then
            D.All_Lengths (D.Dynamic_Length_Index) :=
              Zlib.Huffman.Code_Length (Decoded_Symbol);
            D.Previous_Code_Length := Zlib.Huffman.Code_Length (Decoded_Symbol);
            D.Have_Previous_Length := True;
            D.Dynamic_Length_Index := D.Dynamic_Length_Index + 1;
            Status := Ok;
            return;
         end if;

         if Decoded_Symbol > 18 then
            Status := Malformed;
            return;
         end if;

         if Decoded_Symbol = 16 and then not D.Have_Previous_Length then
            Status := Malformed;
            return;
         end if;

         D.Pending_Repeat_Symbol := Decoded_Symbol;
         D.Have_Pending_Repeat := True;
         Repeat_Symbol := Decoded_Symbol;
      end if;

      if Repeat_Symbol = 16 then
         Read_Bits_Incremental (D, Source, 2, Extra, Status);
         if Status /= Ok then
            return;
         end if;

         Repeat := 3 + Extra;
         if D.Dynamic_Length_Index + Repeat > D.Dynamic_Total_Lengths then
            Status := Malformed;
            return;
         end if;

         for I in 1 .. Repeat loop
            D.All_Lengths (D.Dynamic_Length_Index) := D.Previous_Code_Length;
            D.Dynamic_Length_Index := D.Dynamic_Length_Index + 1;
         end loop;

      elsif Repeat_Symbol = 17 then
         Read_Bits_Incremental (D, Source, 3, Extra, Status);
         if Status /= Ok then
            return;
         end if;

         Repeat := 3 + Extra;
         if D.Dynamic_Length_Index + Repeat > D.Dynamic_Total_Lengths then
            Status := Malformed;
            return;
         end if;

         for I in 1 .. Repeat loop
            D.All_Lengths (D.Dynamic_Length_Index) := 0;
            D.Dynamic_Length_Index := D.Dynamic_Length_Index + 1;
         end loop;
         D.Previous_Code_Length := 0;
         D.Have_Previous_Length := True;

      elsif Repeat_Symbol = 18 then
         Read_Bits_Incremental (D, Source, 7, Extra, Status);
         if Status /= Ok then
            return;
         end if;

         Repeat := 11 + Extra;
         if D.Dynamic_Length_Index + Repeat > D.Dynamic_Total_Lengths then
            Status := Malformed;
            return;
         end if;

         for I in 1 .. Repeat loop
            D.All_Lengths (D.Dynamic_Length_Index) := 0;
            D.Dynamic_Length_Index := D.Dynamic_Length_Index + 1;
         end loop;
         D.Previous_Code_Length := 0;
         D.Have_Previous_Length := True;

      else
         Status := Malformed;
         return;
      end if;

      D.Have_Pending_Repeat := False;
      D.Pending_Repeat_Symbol := 0;
      Status := Ok;
   end Decode_Code_Length_Symbol;

   procedure Build_Dynamic_Tables
     (D      : in out Decoder;
      Status : out Decode_Status)
   is
      Build_Status : Zlib.Status_Code;
      Lit_Lengths  : Zlib.Huffman.Code_Length_Array (0 .. 285) := [others => 0];
      Dist_Lengths : Zlib.Huffman.Code_Length_Array (0 .. 31) := [others => 0];
   begin
      for I in 0 .. D.Dynamic_HLIT - 1 loop
         Lit_Lengths (I) := D.All_Lengths (I);
      end loop;

      for I in 0 .. D.Dynamic_HDIST - 1 loop
         Dist_Lengths (I) := D.All_Lengths (D.Dynamic_HLIT + I);
      end loop;

      if Lit_Lengths (256) = 0 then
         Status := Malformed;
         return;
      end if;

      Zlib.Huffman.Build (Lit_Lengths, D.Lit_Len_Table, Build_Status);
      if Build_Status /= Zlib.Ok then
         Status := Malformed;
         return;
      end if;

      if Dist_Lengths (30) /= 0 or else Dist_Lengths (31) /= 0 then
         --  Deflate defines usable distance symbols 0 .. 29.  Dynamic
         --  headers may encode up to 32 distance-code lengths, but reserved
         --  symbols 30 and 31 must not be assigned usable codes.
         Status := Malformed;
         return;
      end if;

      if Has_Non_Zero_Length (Dist_Lengths) then
         Zlib.Huffman.Build (Dist_Lengths, D.Dist_Table, Build_Status);
         if Build_Status /= Zlib.Ok then
            Status := Malformed;
            return;
         end if;
         D.Dist_Table_Empty := False;
      else
         Zlib.Huffman.Clear (D.Dist_Table);
         D.Dist_Table_Empty := True;
      end if;

      D.Huff_Code := 0;
      D.Huff_Length := 0;
      Status := Ok;
   end Build_Dynamic_Tables;

   procedure Note_Output
     (D      : in out Decoder;
      Header : Zlib.Header_Type;
      B      : Ada.Streams.Stream_Element)
   is
   begin
      if Header = Zlib.GZip then
         CryptoLib.Checksums.CRC32_Update (D.GZip_Data_CRC, B);
         D.GZip_ISIZE := D.GZip_ISIZE + 1;
      elsif Header = Zlib.Raw_Deflate then
         null;
      else
         CryptoLib.Checksums.Adler32_Update (D.Adler, B);
      end if;
   end Note_Output;

   procedure Step_Deflate
     (D      : in out Decoder;
      Header : Zlib.Header_Type;
      Source : in out Zlib.Stream_Bits.Bit_Source;
      Window : in out Zlib.Sliding_Window.Window;
      Status : out Decode_Status)
   is
      Read_Status  : Zlib.Stream_Bits.Read_Status;
      Write_Status : Zlib.Sliding_Window.Write_Status;
      Build_Status : Zlib.Status_Code;
      Bits         : Natural;
      B            : Ada.Streams.Stream_Element;
      Extra        : Natural;
      Dist_Symbol  : Natural;
   begin
      loop
         case D.Inflate is
            when Need_Block_Header =>
               D.Huff_Code := 0;
               D.Huff_Length := 0;
               Bits := Zlib.Stream_Bits.Read_Bits (Source, 3, Read_Status);

               case Read_Status is
                  when Zlib.Stream_Bits.Need_Input =>
                     Status := Need_Input;
                     return;
                  when Zlib.Stream_Bits.Invalid_State =>
                     Fail (D, Status, Malformed, Zlib.Invalid_Block_Type);
                     return;
                  when Zlib.Stream_Bits.Ok =>
                     null;
               end case;

               D.BFinal := Bits mod 2 = 1;

               case Bits / 2 is
                  when 0 =>
                     D.Inflate := Stored_Align;
                  when 1 =>
                     D.Inflate := Fixed_Init;
                  when 2 =>
                     Reset_Dynamic_State (D);
                     D.Inflate := Dynamic_Header_HLIT;
                  when others =>
                     Fail (D, Status, Malformed, Zlib.Invalid_Block_Type);
                     return;
               end case;

            when Stored_Align =>
               Zlib.Stream_Bits.Align_To_Byte (Source);
               D.Len := 0;
               D.NLen := 0;
               D.Inflate := Stored_Len_Lo;

            when Stored_Len_Lo =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Len := Natural (B);
               D.Inflate := Stored_Len_Hi;

            when Stored_Len_Hi =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Len := D.Len + Natural (B) * 256;
               D.Inflate := Stored_NLen_Lo;

            when Stored_NLen_Lo =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.NLen := Natural (B);
               D.Inflate := Stored_NLen_Hi;

            when Stored_NLen_Hi =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.NLen := D.NLen + Natural (B) * 256;

               if D.Len + D.NLen /= 16#FFFF# then
                  Fail (D, Status, Malformed, Zlib.Invalid_Stored_Block);
                  return;
               end if;

               D.Stored_Left := D.Len;
               if D.Stored_Left = 0 then
                  if D.BFinal then
                     D.Inflate := Finished;
                     Status := Ok;
                     return;
                  else
                     D.Inflate := Need_Block_Header;
                  end if;
               else
                  D.Inflate := Stored_Data;
               end if;

            when Stored_Data =>
               while D.Stored_Left > 0 loop
                  if Zlib.Sliding_Window.Pending_Output (Window)
                    >= Pending_Capacity
                  then
                     Status := Need_Output;
                     return;
                  end if;

                  B := Read_Byte (Source, Status);
                  if Status /= Ok then
                     return;
                  end if;

                  Zlib.Sliding_Window.Put_Byte (Window, B, Write_Status);
                  case Write_Status is
                     when Zlib.Sliding_Window.Ok =>
                        Note_Output (D, Header, B);
                        D.Stored_Left := D.Stored_Left - 1;
                     when Zlib.Sliding_Window.Need_Output =>
                        Status := Need_Output;
                        return;
                     when others =>
                        Fail (D, Status, Malformed, Zlib.Invalid_Distance);
                        return;
                  end case;
               end loop;

               if D.BFinal then
                  D.Inflate := Finished;
                  Status := Ok;
                  return;
               else
                  D.Inflate := Need_Block_Header;
               end if;

            when Fixed_Init =>
               --  The active tables are shared by fixed and dynamic compressed
               --  blocks. A previous dynamic block may have overwritten them,
               --  so fixed blocks must rebuild the fixed tables whenever a
               --  fixed block starts rather than relying on a stale readiness
               --  flag.
               Zlib.Deflate_Tables.Build_Fixed_Tables
                 (D.Lit_Len_Table, D.Dist_Table, Build_Status);
               if Build_Status /= Zlib.Ok then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;
               D.Dist_Table_Empty := False;
               D.Huff_Code := 0;
               D.Huff_Length := 0;
               D.Inflate := Compressed_Symbol;

            when Dynamic_Header_HLIT =>
               Read_Bits_Incremental (D, Source, 5, Bits, Status);
               if Status = Need_Input then
                  return;
               elsif Status /= Ok then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;

               declare
                  Candidate_HLIT : constant Natural := Bits + 257;
               begin
                  if Candidate_HLIT > 286 then
                     Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                     return;
                  end if;

                  D.Dynamic_HLIT := Candidate_HLIT;
               end;

               D.Inflate := Dynamic_Header_HDIST;

            when Dynamic_Header_HDIST =>
               Read_Bits_Incremental (D, Source, 5, Bits, Status);
               if Status = Need_Input then
                  return;
               elsif Status /= Ok then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;
               if Bits + 1 > 32 then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;
               D.Dynamic_HDIST := Bits + 1;
               D.Inflate := Dynamic_Header_HCLEN;

            when Dynamic_Header_HCLEN =>
               Read_Bits_Incremental (D, Source, 4, Bits, Status);
               if Status = Need_Input then
                  return;
               elsif Status /= Ok then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;
               D.Dynamic_HCLEN := Bits + 4;
               D.Dynamic_Code_Length_Index := 0;
               D.Code_Length_Lengths := [others => 0];
               D.Inflate := Dynamic_Code_Length_Code_Lengths;

            when Dynamic_Code_Length_Code_Lengths =>
               while D.Dynamic_Code_Length_Index < D.Dynamic_HCLEN loop
                  Read_Bits_Incremental (D, Source, 3, Bits, Status);
                  if Status = Need_Input then
                     return;
                  elsif Status /= Ok then
                     Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                     return;
                  end if;

                  D.Code_Length_Lengths
                    (Zlib.Deflate_Tables.Code_Length_Order (D.Dynamic_Code_Length_Index)) :=
                      Zlib.Huffman.Code_Length (Bits);
                  D.Dynamic_Code_Length_Index :=
                    D.Dynamic_Code_Length_Index + 1;
               end loop;
               D.Inflate := Dynamic_Code_Length_Table;

            when Dynamic_Code_Length_Table =>
               Zlib.Huffman.Build
                 (D.Code_Length_Lengths, D.Code_Length_Table, Build_Status);
               if Build_Status /= Zlib.Ok then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;

               D.Dynamic_Total_Lengths := D.Dynamic_HLIT + D.Dynamic_HDIST;
               D.Dynamic_Length_Index := 0;
               D.All_Lengths := [others => 0];
               D.Previous_Code_Length := 0;
               D.Have_Previous_Length := False;
               D.Pending_Repeat_Symbol := 0;
               D.Have_Pending_Repeat := False;
               D.Huff_Code := 0;
               D.Huff_Length := 0;
               D.Inflate := Dynamic_All_Code_Lengths;

            when Dynamic_All_Code_Lengths =>
               while D.Dynamic_Length_Index < D.Dynamic_Total_Lengths loop
                  Decode_Code_Length_Symbol (D, Source, Status);
                  if Status = Need_Input then
                     return;
                  elsif Status /= Ok then
                     Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                     return;
                  end if;
               end loop;
               D.Inflate := Dynamic_Build_Tables;

            when Dynamic_Build_Tables =>
               Build_Dynamic_Tables (D, Status);
               if Status /= Ok then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;
               D.Inflate := Compressed_Symbol;

            when Compressed_Symbol =>
               declare
                  Table          : Zlib.Huffman.Decode_Table
                                     renames D.Lit_Len_Table;
                  Decoded_Symbol : Natural;
               begin
                  Decode_Huffman_Symbol
                    (D, Source, Table, Decoded_Symbol, Status);
                  if Status = Need_Input then
                     return;
                  elsif Status /= Ok then
                     Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                     return;
                  end if;

                  D.Symbol := Decoded_Symbol;
               end;

               if D.Symbol <= 255 then
                  D.Inflate := Compressed_Literal;

               elsif D.Symbol = 256 then
                  if D.BFinal then
                     Zlib.Stream_Bits.Align_To_Byte (Source);
                     D.Inflate := Finished;
                     Status := Ok;
                     return;
                  else
                     D.Inflate := Need_Block_Header;
                  end if;

               elsif D.Symbol in 257 .. 285 then
                  D.Length_Value :=
                    Zlib.Deflate_Tables.Length_Base (D.Symbol);
                  D.Inflate := Length_Extra;

               else
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;

            when Compressed_Literal =>
               B := Ada.Streams.Stream_Element (D.Symbol);
               Zlib.Sliding_Window.Put_Byte (Window, B, Write_Status);
               case Write_Status is
                  when Zlib.Sliding_Window.Ok =>
                     Note_Output (D, Header, B);
                     D.Inflate := Compressed_Symbol;
                  when Zlib.Sliding_Window.Need_Output =>
                     Status := Need_Output;
                     return;
                  when others =>
                     Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                     return;
               end case;

            when Length_Extra =>
               Read_Bits_Incremental
                 (D,
                  Source,
                  Zlib.Deflate_Tables.Length_Extra (D.Symbol),
                  Extra,
                  Status);
               if Status = Need_Input then
                  return;
               elsif Status /= Ok then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;

               D.Length_Value := D.Length_Value + Extra;
               D.Inflate := Distance_Symbol;

            when Distance_Symbol =>
               if D.Dist_Table_Empty then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;

               declare
                  Table          : Zlib.Huffman.Decode_Table
                                     renames D.Dist_Table;
                  Decoded_Symbol : Natural;
               begin
                  Decode_Huffman_Symbol
                    (D, Source, Table, Decoded_Symbol, Status);
                  if Status = Need_Input then
                     return;
                  elsif Status /= Ok then
                     Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                     return;
                  end if;

                  Dist_Symbol := Decoded_Symbol;
               end;

               if Dist_Symbol > 29 then
                  Fail (D, Status, Malformed, Zlib.Invalid_Huffman_Code);
                  return;
               end if;

               D.Symbol := Dist_Symbol;
               D.Distance_Value :=
                 Zlib.Deflate_Tables.Distance_Base (Dist_Symbol);
               D.Inflate := Distance_Extra;

            when Distance_Extra =>
               Read_Bits_Incremental
                 (D,
                  Source,
                  Zlib.Deflate_Tables.Distance_Extra (D.Symbol),
                  Extra,
                  Status);
               if Status = Need_Input then
                  return;
               elsif Status /= Ok then
                  Fail (D, Status, Malformed, Zlib.Invalid_Distance);
                  return;
               end if;

               D.Distance_Value := D.Distance_Value + Extra;
               Zlib.Sliding_Window.Begin_Copy
                 (Window, D.Length_Value, D.Distance_Value, Write_Status);
               case Write_Status is
                  when Zlib.Sliding_Window.Ok =>
                     D.Inflate := Copying_Match;
                  when Zlib.Sliding_Window.Need_Output =>
                     Status := Need_Output;
                     return;
                  when Zlib.Sliding_Window.Invalid_Distance |
                       Zlib.Sliding_Window.Invalid_Length =>
                     Fail (D, Status, Malformed, Zlib.Invalid_Distance);
                     return;
               end case;

            when Copying_Match =>
               while Zlib.Sliding_Window.Copy_Active (Window) loop
                  Zlib.Sliding_Window.Emit_Copy_Byte (Window, B, Write_Status);
                  case Write_Status is
                     when Zlib.Sliding_Window.Ok =>
                        Note_Output (D, Header, B);
                     when Zlib.Sliding_Window.Need_Output =>
                        Status := Need_Output;
                        return;
                     when others =>
                        Fail (D, Status, Malformed, Zlib.Invalid_Distance);
                        return;
                  end case;
               end loop;
               D.Inflate := Compressed_Symbol;

            when Finished =>
               Status := Stream_End;
               return;

            when Failed =>
               Status := Malformed;
               return;
         end case;
      end loop;
   end Step_Deflate;

   procedure Header_Byte
     (D : in out Decoder;
      B : Ada.Streams.Stream_Element)
   is
   begin
      CryptoLib.Checksums.CRC32_Update (D.GZip_Header_CRC, B);
   end Header_Byte;

   function GZip_Flag_Set
     (D    : Decoder;
      Mask : Natural)
      return Boolean
     with SPARK_Mode => On
   is
   begin
      return (Interfaces.Unsigned_32 (D.GZip_FLG) and Interfaces.Unsigned_32 (Mask)) /= 0;
   end GZip_Flag_Set;

   procedure Select_Default_Header
     (D      : in out Decoder;
      Source : in out Zlib.Stream_Bits.Bit_Source;
      Status : out Decode_Status)
   is
      Peek_Status : Zlib.Stream_Bits.Read_Status;
      First       : Ada.Streams.Stream_Element;
      Second      : Ada.Streams.Stream_Element;
   begin
      First := Zlib.Stream_Bits.Peek_Byte_Aligned (Source, 0, Peek_Status);
      case Peek_Status is
         when Zlib.Stream_Bits.Ok =>
            null;
         when Zlib.Stream_Bits.Need_Input =>
            Status := Need_Input;
            return;
         when Zlib.Stream_Bits.Invalid_State =>
            Fail (D, Status, Malformed, Zlib.Invalid_Header);
            return;
      end case;

      Second := Zlib.Stream_Bits.Peek_Byte_Aligned (Source, 1, Peek_Status);
      case Peek_Status is
         when Zlib.Stream_Bits.Ok =>
            null;
         when Zlib.Stream_Bits.Need_Input =>
            Status := Need_Input;
            return;
         when Zlib.Stream_Bits.Invalid_State =>
            Fail (D, Status, Malformed, Zlib.Invalid_Header);
            return;
      end case;

      if First = 16#1F# and then Second = 16#8B# then
         D.Active_Header := Zlib.GZip;
         D.Wrapper := Need_GZip_ID1;
      elsif Header_Valid (First, Second) then
         D.Active_Header := Zlib.Zlib_Header;
         D.Wrapper := Need_CMF;
      else
         D.Active_Header := Zlib.Raw_Deflate;
         D.Wrapper := Deflate_Data;
      end if;

      Status := Ok;
   end Select_Default_Header;

   procedure Decode
     (D      : in out Decoder;
      Header : Zlib.Header_Type;
      Source : in out Zlib.Stream_Bits.Bit_Source;
      Window : in out Zlib.Sliding_Window.Window;
      Status : out Decode_Status)
   is
      B : Ada.Streams.Stream_Element;
   begin
      if Header = Zlib.Raw_Deflate and then D.Wrapper = Need_CMF then
         D.Active_Header := Zlib.Raw_Deflate;
         D.Wrapper := Deflate_Data;
      elsif Header = Zlib.GZip and then D.Wrapper = Need_CMF then
         D.Active_Header := Zlib.GZip;
         D.Wrapper := Need_GZip_ID1;
      elsif Header = Zlib.Zlib_Header and then D.Wrapper = Need_CMF then
         D.Active_Header := Zlib.Zlib_Header;
      elsif Header = Zlib.Default and then D.Wrapper = Need_CMF then
         Select_Default_Header (D, Source, Status);
         if Status /= Ok then
            return;
         end if;
      end if;

      loop
         case D.Wrapper is
            when Need_CMF =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.CMF := B;
               D.Wrapper := Need_FLG;

            when Need_FLG =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.FLG := B;

               if not Header_Valid (D.CMF, D.FLG) then
                  if Natural (D.CMF) mod 16 /= 8 then
                     Fail (D, Status, Malformed, Zlib.Unsupported_Method);
                  else
                     Fail (D, Status, Malformed, Zlib.Invalid_Header);
                  end if;
                  return;
               end if;

               if FDICT_Set (D.FLG) then
                  D.Expected_Dictionary_ID := 0;
                  D.Wrapper := Need_DICTID_1;
               else
                  --  A caller may have supplied a dictionary proactively, but
                  --  the zlib wrapper is authoritative: without FDICT, those
                  --  bytes must not participate in LZ77 history.
                  Zlib.Sliding_Window.Reset (Window);
                  D.Wrapper := Deflate_Data;
               end if;

            when Need_DICTID_1 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Expected_Dictionary_ID :=
                 Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 24);
               D.Wrapper := Need_DICTID_2;

            when Need_DICTID_2 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Expected_Dictionary_ID :=
                 D.Expected_Dictionary_ID
                 or Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 16);
               D.Wrapper := Need_DICTID_3;

            when Need_DICTID_3 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Expected_Dictionary_ID :=
                 D.Expected_Dictionary_ID
                 or Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 8);
               D.Wrapper := Need_DICTID_4;

            when Need_DICTID_4 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Expected_Dictionary_ID :=
                 D.Expected_Dictionary_ID or Interfaces.Unsigned_32 (B);

               if not D.Dictionary_Supplied then
                  Fail (D, Status, Malformed, Zlib.Unsupported_Preset_Dictionary);
                  return;
               elsif D.Dictionary_ID /= D.Expected_Dictionary_ID then
                  Fail (D, Status, Checksum_Error, Zlib.Invalid_Checksum);
                  return;
               end if;

               D.Wrapper := Deflate_Data;

            when Need_GZip_ID1 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               Header_Byte (D, B);
               if B /= 16#1F# then
                  Fail (D, Status, Malformed, Zlib.Invalid_Header);
                  return;
               end if;
               D.Wrapper := Need_GZip_ID2;

            when Need_GZip_ID2 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               Header_Byte (D, B);
               if B /= 16#8B# then
                  Fail (D, Status, Malformed, Zlib.Invalid_Header);
                  return;
               end if;
               D.Wrapper := Need_GZip_CM;

            when Need_GZip_CM =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               Header_Byte (D, B);
               if B /= 8 then
                  Fail (D, Status, Unsupported, Zlib.Unsupported_Method);
                  return;
               end if;
               D.Wrapper := Need_GZip_FLG;

            when Need_GZip_FLG =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               Header_Byte (D, B);
               if (Interfaces.Unsigned_32 (B) and 16#E0#) /= 0 then
                  Fail (D, Status, Malformed, Zlib.Invalid_Header);
                  return;
               end if;
               D.GZip_FLG := B;
               D.Wrapper := Need_GZip_MTIME_0;

            when Need_GZip_MTIME_0 | Need_GZip_MTIME_1 |
                 Need_GZip_MTIME_2 | Need_GZip_MTIME_3 |
                 Need_GZip_XFL | Need_GZip_OS =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               Header_Byte (D, B);

               case D.Wrapper is
                  when Need_GZip_MTIME_0 =>
                     D.Wrapper := Need_GZip_MTIME_1;
                  when Need_GZip_MTIME_1 =>
                     D.Wrapper := Need_GZip_MTIME_2;
                  when Need_GZip_MTIME_2 =>
                     D.Wrapper := Need_GZip_MTIME_3;
                  when Need_GZip_MTIME_3 =>
                     D.Wrapper := Need_GZip_XFL;
                  when Need_GZip_XFL =>
                     D.Wrapper := Need_GZip_OS;
                  when Need_GZip_OS =>
                     if GZip_Flag_Set (D, 16#04#) then
                        D.Wrapper := Need_GZip_XLEN_0;
                     elsif GZip_Flag_Set (D, 16#08#) then
                        D.Wrapper := GZip_File_Name;
                     elsif GZip_Flag_Set (D, 16#10#) then
                        D.Wrapper := GZip_Comment;
                     elsif GZip_Flag_Set (D, 16#02#) then
                        D.Wrapper := Need_GZip_HCRC_0;
                     else
                        D.Wrapper := Deflate_Data;
                     end if;
                  when others =>
                     null;
               end case;

            when Need_GZip_XLEN_0 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               Header_Byte (D, B);
               D.GZip_XLEN := Natural (B);
               D.Wrapper := Need_GZip_XLEN_1;

            when Need_GZip_XLEN_1 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               Header_Byte (D, B);
               D.GZip_XLEN := D.GZip_XLEN + Natural (B) * 256;
               D.GZip_Extra_Left := D.GZip_XLEN;
               if D.GZip_Extra_Left = 0 then
                  if GZip_Flag_Set (D, 16#08#) then
                     D.Wrapper := GZip_File_Name;
                  elsif GZip_Flag_Set (D, 16#10#) then
                     D.Wrapper := GZip_Comment;
                  elsif GZip_Flag_Set (D, 16#02#) then
                     D.Wrapper := Need_GZip_HCRC_0;
                  else
                     D.Wrapper := Deflate_Data;
                  end if;
               else
                  D.Wrapper := GZip_Extra_Data;
               end if;

            when GZip_Extra_Data =>
               while D.GZip_Extra_Left > 0 loop
                  B := Read_Byte (Source, Status);
                  if Status /= Ok then
                     return;
                  end if;
                  Header_Byte (D, B);
                  D.GZip_Extra_Left := D.GZip_Extra_Left - 1;
               end loop;

               if GZip_Flag_Set (D, 16#08#) then
                  D.Wrapper := GZip_File_Name;
               elsif GZip_Flag_Set (D, 16#10#) then
                  D.Wrapper := GZip_Comment;
               elsif GZip_Flag_Set (D, 16#02#) then
                  D.Wrapper := Need_GZip_HCRC_0;
               else
                  D.Wrapper := Deflate_Data;
               end if;

            when GZip_File_Name =>
               loop
                  B := Read_Byte (Source, Status);
                  if Status /= Ok then
                     return;
                  end if;
                  Header_Byte (D, B);
                  exit when B = 0;
               end loop;

               if GZip_Flag_Set (D, 16#10#) then
                  D.Wrapper := GZip_Comment;
               elsif GZip_Flag_Set (D, 16#02#) then
                  D.Wrapper := Need_GZip_HCRC_0;
               else
                  D.Wrapper := Deflate_Data;
               end if;

            when GZip_Comment =>
               loop
                  B := Read_Byte (Source, Status);
                  if Status /= Ok then
                     return;
                  end if;
                  Header_Byte (D, B);
                  exit when B = 0;
               end loop;

               if GZip_Flag_Set (D, 16#02#) then
                  D.Wrapper := Need_GZip_HCRC_0;
               else
                  D.Wrapper := Deflate_Data;
               end if;

            when Need_GZip_HCRC_0 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_HCRC := Interfaces.Unsigned_32 (B);
               D.Wrapper := Need_GZip_HCRC_1;

            when Need_GZip_HCRC_1 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_HCRC := D.GZip_HCRC or
                 Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 8);
               if D.GZip_HCRC /= (CryptoLib.Checksums.CRC32_Value (D.GZip_Header_CRC) and 16#FFFF#) then
                  Fail (D, Status, Checksum_Error, Zlib.Invalid_Checksum);
                  return;
               end if;
               D.Wrapper := Deflate_Data;

            when Deflate_Data =>
               Step_Deflate (D, D.Active_Header, Source, Window, Status);
               if Status = Ok and then D.Inflate = Finished then
                  if D.Active_Header = Zlib.GZip then
                     D.GZip_Expected_CRC := 0;
                     D.GZip_Expected_ISIZE := 0;
                     D.Wrapper := Need_GZip_CRC_0;
                  elsif D.Active_Header = Zlib.Raw_Deflate then
                     D.Wrapper := Done;
                     Status := Stream_End;
                     return;
                  else
                     D.Expected_Adler := 0;
                     D.Wrapper := Need_Adler_1;
                  end if;
               elsif Status /= Ok then
                  return;
               end if;

            when Need_Adler_1 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Expected_Adler :=
                 Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 24);
               D.Wrapper := Need_Adler_2;

            when Need_Adler_2 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Expected_Adler :=
                 D.Expected_Adler
                 or Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 16);
               D.Wrapper := Need_Adler_3;

            when Need_Adler_3 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Expected_Adler :=
                 D.Expected_Adler
                 or Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 8);
               D.Wrapper := Need_Adler_4;

            when Need_Adler_4 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.Expected_Adler :=
                 D.Expected_Adler or Interfaces.Unsigned_32 (B);

               if D.Expected_Adler /= CryptoLib.Checksums.Adler32_Value (D.Adler) then
                  Fail (D, Status, Checksum_Error, Zlib.Invalid_Checksum);
                  return;
               end if;

               D.Wrapper := Done;
               Status := Stream_End;
               return;

            when Need_GZip_CRC_0 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_Expected_CRC := Interfaces.Unsigned_32 (B);
               D.Wrapper := Need_GZip_CRC_1;

            when Need_GZip_CRC_1 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_Expected_CRC := D.GZip_Expected_CRC or
                 Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 8);
               D.Wrapper := Need_GZip_CRC_2;

            when Need_GZip_CRC_2 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_Expected_CRC := D.GZip_Expected_CRC or
                 Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 16);
               D.Wrapper := Need_GZip_CRC_3;

            when Need_GZip_CRC_3 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_Expected_CRC := D.GZip_Expected_CRC or
                 Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 24);
               if D.GZip_Expected_CRC /= CryptoLib.Checksums.CRC32_Value (D.GZip_Data_CRC) then
                  Fail (D, Status, Checksum_Error, Zlib.Invalid_Checksum);
                  return;
               end if;
               D.Wrapper := Need_GZip_ISIZE_0;

            when Need_GZip_ISIZE_0 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_Expected_ISIZE := Interfaces.Unsigned_32 (B);
               D.Wrapper := Need_GZip_ISIZE_1;

            when Need_GZip_ISIZE_1 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_Expected_ISIZE := D.GZip_Expected_ISIZE or
                 Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 8);
               D.Wrapper := Need_GZip_ISIZE_2;

            when Need_GZip_ISIZE_2 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_Expected_ISIZE := D.GZip_Expected_ISIZE or
                 Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 16);
               D.Wrapper := Need_GZip_ISIZE_3;

            when Need_GZip_ISIZE_3 =>
               B := Read_Byte (Source, Status);
               if Status /= Ok then
                  return;
               end if;
               D.GZip_Expected_ISIZE := D.GZip_Expected_ISIZE or
                 Interfaces.Shift_Left (Interfaces.Unsigned_32 (B), 24);
               if D.GZip_Expected_ISIZE /= D.GZip_ISIZE then
                  Fail (D, Status, Checksum_Error, Zlib.Invalid_Checksum);
                  return;
               end if;
               D.Wrapper := Done;
               Status := Member_End;
               return;

            when Done =>
               if D.Active_Header = Zlib.GZip then
                  Status := Member_End;
               else
                  Status := Stream_End;
               end if;
               return;

            when Failed =>
               Status := Malformed;
               return;
         end case;
      end loop;
   end Decode;

   function Is_Finished
     (D : Decoder)
      return Boolean
     with SPARK_Mode => On
   is
   begin
      return D.Wrapper = Done;
   end Is_Finished;

   function Is_Failed
     (D : Decoder)
      return Boolean
     with SPARK_Mode => On
   is
   begin
      return D.Wrapper = Failed or else D.Inflate = Failed;
   end Is_Failed;

   function Last_Status
     (D : Decoder)
      return Zlib.Status_Code
     with SPARK_Mode => On
   is
   begin
      return D.Last_Status;
   end Last_Status;

   function Active_Header
     (D : Decoder)
      return Zlib.Header_Type
     with SPARK_Mode => On
   is
   begin
      return D.Active_Header;
   end Active_Header;

end Zlib.Stream_Inflate;
