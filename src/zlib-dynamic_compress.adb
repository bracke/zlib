with Ada.Streams;
with Interfaces;
with CryptoLib.Checksums;
with Zlib.Bit_Writer;
with Zlib.Huffman_Builder;
with Zlib.Deflate_Tables;
with Zlib.LZ77_Matcher;

package body Zlib.Dynamic_Compress is
   use type Interfaces.Unsigned_32;

   Code_Length_Order : constant array (Natural range 0 .. 18) of Natural :=
     [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

   subtype Litlen_Symbol is Natural range 0 .. 285;
   subtype Distance_Symbol is Natural range 0 .. 29;
   subtype Code_Length_Symbol is Natural range 0 .. 18;

   function Reverse_Bits (Value : Natural; Count : Natural) return Natural is
      Work   : Natural := Value;
      Result : Natural := 0;
   begin
      for I in 1 .. Count loop
         Result := Result * 2 + (Work mod 2);
         Work := Work / 2;
      end loop;

      return Result;
   end Reverse_Bits;

   function U32_To_Byte
     (Value : Interfaces.Unsigned_32; Shift : Natural) return Zlib.Byte
     with SPARK_Mode => On
   is
   begin
      return Zlib.Byte (Interfaces.Shift_Right (Value, Shift) and 16#FF#);
   end U32_To_Byte;

   function Compute_Adler32
     (Input : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      State : CryptoLib.Checksums.Adler32_State;
   begin
      CryptoLib.Checksums.Adler32_Reset (State);
      for B of Input loop
         CryptoLib.Checksums.Adler32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.Adler32_Value (State);
   end Compute_Adler32;

   procedure Build_Canonical
     (Lengths : Zlib.Huffman_Builder.Length_Array;
      Codes   : out Zlib.Huffman_Builder.Frequency_Array)
   is
      Bl_Count  : array (Natural range 0 .. 15) of Natural := [others => 0];
      Next_Code : array (Natural range 0 .. 15) of Natural := [others => 0];
      Code      : Natural := 0;
   begin
      pragma
        Assert
          (Lengths'First = Codes'First and then Lengths'Last = Codes'Last,
           "Build_Canonical requires matching length/code ranges");

      Codes := [others => 0];

      for Symbol in Lengths'Range loop
         if Lengths (Symbol) /= 0 then
            Bl_Count (Lengths (Symbol)) := Bl_Count (Lengths (Symbol)) + 1;
         end if;
      end loop;

      for Bits in 1 .. 15 loop
         Code := (Code + Bl_Count (Bits - 1)) * 2;
         Next_Code (Bits) := Code;
      end loop;

      for Symbol in Lengths'Range loop
         if Lengths (Symbol) /= 0 then
            Codes (Symbol) :=
              Reverse_Bits (Next_Code (Lengths (Symbol)), Lengths (Symbol));
            Next_Code (Lengths (Symbol)) := Next_Code (Lengths (Symbol)) + 1;
         end if;
      end loop;
   end Build_Canonical;

   procedure Write_Code
     (W       : in out Zlib.Bit_Writer.Writer;
      Codes   : Zlib.Huffman_Builder.Frequency_Array;
      Lengths : Zlib.Huffman_Builder.Length_Array;
      Symbol  : Natural) is
   begin
      pragma
        Assert
          (Lengths'First = Codes'First and then Lengths'Last = Codes'Last,
           "Write_Code requires matching length/code ranges");
      pragma
        Assert
          (Lengths (Symbol) /= 0, "attempt to write absent Huffman symbol");
      Zlib.Bit_Writer.Write_Bits (W, Codes (Symbol), Lengths (Symbol));
   end Write_Code;

   function Last_Nonzero_Litlen
     (Lengths : Zlib.Huffman_Builder.Length_Array) return Natural
     with SPARK_Mode => On
   is
      Last : Natural := 256;
   begin
      for Symbol in Lengths'Range loop
         if Lengths (Symbol) /= 0 then
            Last := Symbol;
         end if;
      end loop;

      return Natural'Max (Last, 256);
   end Last_Nonzero_Litlen;

   function Last_Nonzero_Distance
     (Lengths : Zlib.Huffman_Builder.Length_Array) return Natural
     with SPARK_Mode => On
   is
      Last : Natural := 0;
   begin
      for Symbol in Lengths'Range loop
         if Lengths (Symbol) /= 0 then
            Last := Symbol;
         end if;
      end loop;

      return Last;
   end Last_Nonzero_Distance;

   function Last_Nonzero_Code_Length_Order
     (Lengths : Zlib.Huffman_Builder.Length_Array) return Natural
     with
       SPARK_Mode => On,
       Pre        => Lengths'First <= 0 and then Lengths'Last >= 18
   is
      Last : Natural := 3;
   begin
      for Order_Index in Code_Length_Order'Range loop
         if Lengths (Code_Length_Order (Order_Index)) /= 0 then
            Last := Order_Index;
         end if;
      end loop;

      return Natural'Max (Last, 3);
   end Last_Nonzero_Code_Length_Order;

   function Length_Symbol_For (Length : Natural) return Natural
     with SPARK_Mode => On
   is
   begin
      if Length = Zlib.LZ77_Matcher.Max_Match_Length then
         return 285;
      end if;

      for Symbol in Zlib.Deflate_Tables.Length_Symbol loop
         if Length >= Zlib.Deflate_Tables.Length_Base (Symbol)
           and then
             Length
             < Zlib.Deflate_Tables.Length_Base (Symbol)
               + 2 ** Zlib.Deflate_Tables.Length_Extra (Symbol)
         then
            return Symbol;
         end if;
      end loop;

      return 285;
   end Length_Symbol_For;

   function Distance_Symbol_For (Distance : Natural) return Natural
     with SPARK_Mode => On
   is
   begin
      for Symbol in Zlib.Deflate_Tables.Distance_Symbol loop
         if Distance >= Zlib.Deflate_Tables.Distance_Base (Symbol)
           and then
             Distance
             < Zlib.Deflate_Tables.Distance_Base (Symbol)
               + 2 ** Zlib.Deflate_Tables.Distance_Extra (Symbol)
         then
            return Symbol;
         end if;
      end loop;

      return 29;
   end Distance_Symbol_For;

   function Deflate_Dynamic
     (Input : Zlib.Byte_Array; Status : out Zlib.Status_Code)
      return Zlib.Byte_Array
   is
      Lit_Freq  : Zlib.Huffman_Builder.Frequency_Array (Litlen_Symbol) :=
        [others => 0];
      Dist_Freq : Zlib.Huffman_Builder.Frequency_Array (Distance_Symbol) :=
        [others => 0];
      CL_Freq   : Zlib.Huffman_Builder.Frequency_Array (Code_Length_Symbol) :=
        [others => 0];

      Lit_Len  : Zlib.Huffman_Builder.Length_Array (Litlen_Symbol) :=
        [others => 0];
      Dist_Len : Zlib.Huffman_Builder.Length_Array (Distance_Symbol) :=
        [others => 0];
      CL_Len   : Zlib.Huffman_Builder.Length_Array (Code_Length_Symbol) :=
        [others => 0];

      Lit_Code  : Zlib.Huffman_Builder.Frequency_Array (Litlen_Symbol) :=
        [others => 0];
      Dist_Code : Zlib.Huffman_Builder.Frequency_Array (Distance_Symbol) :=
        [others => 0];
      CL_Code   : Zlib.Huffman_Builder.Frequency_Array (Code_Length_Symbol) :=
        [others => 0];

      W       : Zlib.Bit_Writer.Writer;
      Adler   : constant Interfaces.Unsigned_32 :=
        Compute_Adler32 (Input);
      Tokens  : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize_For_Level (Input, Zlib.Default_Level);
      LL_Last : Natural;
      D_Last  : Natural;
      CL_Last : Natural;
   begin
      Status := Zlib.Ok;

      for T of Tokens loop
         case T.Kind is
            when Zlib.LZ77_Matcher.Literal =>
               Lit_Freq (Natural (T.Value)) :=
                 Lit_Freq (Natural (T.Value)) + 1;

            when Zlib.LZ77_Matcher.Match   =>
               Lit_Freq (Length_Symbol_For (T.Length)) :=
                 Lit_Freq (Length_Symbol_For (T.Length)) + 1;
               Dist_Freq (Distance_Symbol_For (T.Distance)) :=
                 Dist_Freq (Distance_Symbol_For (T.Distance)) + 1;
         end case;
      end loop;
      Lit_Freq (256) := Lit_Freq (256) + 1;

      declare
         Has_Distance : Boolean := False;
      begin
         for F of Dist_Freq loop
            if F /= 0 then
               Has_Distance := True;
            end if;
         end loop;

         if not Has_Distance then
            Dist_Freq (0) := 1;
         end if;
      end;

      Zlib.Huffman_Builder.Build_Lengths (Lit_Freq, Lit_Len, 256);
      Zlib.Huffman_Builder.Build_Lengths (Dist_Freq, Dist_Len, 0);

      LL_Last := Last_Nonzero_Litlen (Lit_Len);
      D_Last := Last_Nonzero_Distance (Dist_Len);

      for Symbol in 0 .. LL_Last loop
         CL_Freq (Lit_Len (Symbol)) := CL_Freq (Lit_Len (Symbol)) + 1;
      end loop;
      for Symbol in 0 .. D_Last loop
         CL_Freq (Dist_Len (Symbol)) := CL_Freq (Dist_Len (Symbol)) + 1;
      end loop;

      Zlib.Huffman_Builder.Build_Lengths (CL_Freq, CL_Len, 0);
      CL_Last := Last_Nonzero_Code_Length_Order (CL_Len);

      Build_Canonical (Lit_Len, Lit_Code);
      Build_Canonical (Dist_Len, Dist_Code);
      Build_Canonical (CL_Len, CL_Code);

      Zlib.Bit_Writer.Reset (W);
      Zlib.Bit_Writer.Write_Byte_Aligned (W, 16#78#);
      Zlib.Bit_Writer.Write_Byte_Aligned (W, 16#01#);

      --  Single final dynamic-Huffman Deflate block: BFINAL=1, BTYPE=10.
      Zlib.Bit_Writer.Write_Bits (W, 1, 1);
      Zlib.Bit_Writer.Write_Bits (W, 2, 2);

      Zlib.Bit_Writer.Write_Bits (W, LL_Last - 256, 5);
      Zlib.Bit_Writer.Write_Bits (W, D_Last, 5);
      Zlib.Bit_Writer.Write_Bits (W, CL_Last - 3, 4);

      for Order_Index in 0 .. CL_Last loop
         Zlib.Bit_Writer.Write_Bits
           (W, CL_Len (Code_Length_Order (Order_Index)), 3);
      end loop;

      for Symbol in 0 .. LL_Last loop
         Write_Code (W, CL_Code, CL_Len, Lit_Len (Symbol));
      end loop;
      for Symbol in 0 .. D_Last loop
         Write_Code (W, CL_Code, CL_Len, Dist_Len (Symbol));
      end loop;

      for T of Tokens loop
         case T.Kind is
            when Zlib.LZ77_Matcher.Literal =>
               Write_Code (W, Lit_Code, Lit_Len, Natural (T.Value));

            when Zlib.LZ77_Matcher.Match   =>
               declare
                  L_Sym : constant Natural := Length_Symbol_For (T.Length);
                  D_Sym : constant Natural := Distance_Symbol_For (T.Distance);
               begin
                  Write_Code (W, Lit_Code, Lit_Len, L_Sym);
                  Zlib.Bit_Writer.Write_Bits
                    (W,
                     T.Length - Zlib.Deflate_Tables.Length_Base (L_Sym),
                     Zlib.Deflate_Tables.Length_Extra (L_Sym));
                  Write_Code (W, Dist_Code, Dist_Len, D_Sym);
                  Zlib.Bit_Writer.Write_Bits
                    (W,
                     T.Distance - Zlib.Deflate_Tables.Distance_Base (D_Sym),
                     Zlib.Deflate_Tables.Distance_Extra (D_Sym));
               end;
         end case;
      end loop;
      Write_Code (W, Lit_Code, Lit_Len, 256);

      Zlib.Bit_Writer.Flush_Byte (W);
      Zlib.Bit_Writer.Write_Byte_Aligned (W, U32_To_Byte (Adler, 24));
      Zlib.Bit_Writer.Write_Byte_Aligned (W, U32_To_Byte (Adler, 16));
      Zlib.Bit_Writer.Write_Byte_Aligned (W, U32_To_Byte (Adler, 8));
      Zlib.Bit_Writer.Write_Byte_Aligned (W, U32_To_Byte (Adler, 0));

      return Zlib.Bit_Writer.To_Array (W);

   exception
      when others =>
         Status := Zlib.Output_File_Error;
         declare
            Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
   end Deflate_Dynamic;

end Zlib.Dynamic_Compress;
