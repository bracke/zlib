with Interfaces;
with Zlib.Bit_Writer;
with Zlib.Checksums;
with Zlib.Deflate_Tables;
with Zlib.LZ77_Matcher;

package body Zlib.Fixed_Compress is
   use type Interfaces.Unsigned_32;

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

   procedure Fixed_Code
     (Symbol : Natural; Code : out Natural; Length : out Natural)
   is
      Canonical : Natural;
   begin
      if Symbol <= 143 then
         Length := 8;
         Canonical := 16#30# + Symbol;
      elsif Symbol <= 255 then
         Length := 9;
         Canonical := 16#190# + (Symbol - 144);
      elsif Symbol <= 279 then
         Length := 7;
         Canonical := Symbol - 256;
      elsif Symbol <= 287 then
         Length := 8;
         Canonical := 16#C0# + (Symbol - 280);
      else
         raise Constraint_Error with "fixed-Huffman symbol out of range";
      end if;

      Code := Reverse_Bits (Canonical, Length);
   end Fixed_Code;

   procedure Write_Fixed_Symbol
     (W : in out Zlib.Bit_Writer.Writer; Symbol : Natural)
   is
      Code   : Natural;
      Length : Natural;
   begin
      Fixed_Code (Symbol, Code, Length);
      Zlib.Bit_Writer.Write_Bits (W, Code, Length);
   end Write_Fixed_Symbol;

   function U32_To_Byte
     (Value : Interfaces.Unsigned_32; Shift : Natural) return Zlib.Byte is
   begin
      return Zlib.Byte (Interfaces.Shift_Right (Value, Shift) and 16#FF#);
   end U32_To_Byte;

   function Length_Symbol_For (Length : Natural) return Natural is
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

   function Distance_Symbol_For (Distance : Natural) return Natural is
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

   procedure Write_Distance_Symbol
     (W : in out Zlib.Bit_Writer.Writer; Symbol : Natural)
   is
      Code : constant Natural := Reverse_Bits (Symbol, 5);
   begin
      Zlib.Bit_Writer.Write_Bits (W, Code, 5);
   end Write_Distance_Symbol;

   procedure Write_Fixed_Token
     (W : in out Zlib.Bit_Writer.Writer; T : Zlib.LZ77_Matcher.Token) is
   begin
      case T.Kind is
         when Zlib.LZ77_Matcher.Literal =>
            Write_Fixed_Symbol (W, Natural (T.Value));

         when Zlib.LZ77_Matcher.Match   =>
            declare
               L_Sym : constant Natural := Length_Symbol_For (T.Length);
               D_Sym : constant Natural := Distance_Symbol_For (T.Distance);
            begin
               Write_Fixed_Symbol (W, L_Sym);
               Zlib.Bit_Writer.Write_Bits
                 (W,
                  T.Length - Zlib.Deflate_Tables.Length_Base (L_Sym),
                  Zlib.Deflate_Tables.Length_Extra (L_Sym));
               Write_Distance_Symbol (W, D_Sym);
               Zlib.Bit_Writer.Write_Bits
                 (W,
                  T.Distance - Zlib.Deflate_Tables.Distance_Base (D_Sym),
                  Zlib.Deflate_Tables.Distance_Extra (D_Sym));
            end;
      end case;
   end Write_Fixed_Token;

   function Deflate_Fixed
     (Input : Zlib.Byte_Array; Status : out Zlib.Status_Code)
      return Zlib.Byte_Array
   is
      W      : Zlib.Bit_Writer.Writer;
      Adler  : constant Interfaces.Unsigned_32 :=
        Zlib.Checksums.Adler32 (Input);
      Tokens : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize
          (Input, Zlib.LZ77_Matcher.Chain_Limit_For_Level (1));
   begin
      Status := Zlib.Ok;
      Zlib.Bit_Writer.Reset (W);

      --  zlib header: CMF=0x78, FLG=0x01. This is the same conservative
      --  wrapper used by Deflate_Stored and has a valid FCHECK value.
      Zlib.Bit_Writer.Write_Byte_Aligned (W, 16#78#);
      Zlib.Bit_Writer.Write_Byte_Aligned (W, 16#01#);

      --  Single final fixed-Huffman Deflate block: BFINAL=1, BTYPE=01.
      Zlib.Bit_Writer.Write_Bits (W, 1, 1);
      Zlib.Bit_Writer.Write_Bits (W, 1, 2);

      for T of Tokens loop
         Write_Fixed_Token (W, T);
      end loop;

      Write_Fixed_Symbol (W, 256);
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
   end Deflate_Fixed;

   function Deflate_Fixed_Raw
     (Input : Zlib.Byte_Array; Status : out Zlib.Status_Code)
      return Zlib.Byte_Array
   is
      W      : Zlib.Bit_Writer.Writer;
      Tokens : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize
          (Input, Zlib.LZ77_Matcher.Chain_Limit_For_Level (1));
   begin
      Status := Zlib.Ok;
      Zlib.Bit_Writer.Reset (W);

      --  Single final fixed-Huffman Deflate block: BFINAL=1, BTYPE=01.
      Zlib.Bit_Writer.Write_Bits (W, 1, 1);
      Zlib.Bit_Writer.Write_Bits (W, 1, 2);

      for T of Tokens loop
         Write_Fixed_Token (W, T);
      end loop;

      Write_Fixed_Symbol (W, 256);
      Zlib.Bit_Writer.Flush_Byte (W);

      return Zlib.Bit_Writer.To_Array (W);

   exception
      when others =>
         Status := Zlib.Output_File_Error;
         declare
            Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
   end Deflate_Fixed_Raw;

end Zlib.Fixed_Compress;
