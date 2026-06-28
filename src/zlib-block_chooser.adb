with Zlib.Deflate_Tables;
with Zlib.Fixed_Compress;
with Zlib.Huffman_Builder;

package body Zlib.Block_Chooser is

   subtype Litlen_Symbol is Natural range 0 .. 285;
   subtype Distance_Symbol is Natural range 0 .. 29;
   subtype Code_Length_Symbol is Natural range 0 .. 18;

   function Pad_To_Byte
     (Bits               : Natural;
      Starting_Bit_Index : Natural)
      return Natural
   is
      Used : constant Natural := (Starting_Bit_Index + Bits) mod 8;
   begin
      return (if Used = 0 then 0 else 8 - Used);
   end Pad_To_Byte;

   function Padded
     (Bits               : Natural;
      Starting_Bit_Index : Natural)
      return Natural
   is
   begin
      return Bits + Pad_To_Byte (Bits, Starting_Bit_Index);
   end Padded;

   function Length_Symbol_For
     (Length : Natural)
      return Natural
   is
   begin
      if Length = Zlib.LZ77_Matcher.Max_Match_Length then
         return 285;
      end if;

      for Symbol in Zlib.Deflate_Tables.Length_Symbol loop
         if Length >= Zlib.Deflate_Tables.Length_Base (Symbol)
           and then Length < Zlib.Deflate_Tables.Length_Base (Symbol)
                           + 2 ** Zlib.Deflate_Tables.Length_Extra (Symbol)
         then
            return Symbol;
         end if;
      end loop;

      return 285;
   end Length_Symbol_For;

   function Distance_Symbol_For
     (Distance : Natural)
      return Natural
   is
   begin
      for Symbol in Zlib.Deflate_Tables.Distance_Symbol loop
         if Distance >= Zlib.Deflate_Tables.Distance_Base (Symbol)
           and then Distance < Zlib.Deflate_Tables.Distance_Base (Symbol)
                             + 2 ** Zlib.Deflate_Tables.Distance_Extra (Symbol)
         then
            return Symbol;
         end if;
      end loop;

      return 29;
   end Distance_Symbol_For;

   function Stored_Bit_Size
     (Payload_Length     : Natural;
      Starting_Bit_Index : Natural := 0)
      return Natural
   is
      Remaining : Natural := Payload_Length;
      Started   : Boolean := False;
      Bits      : Natural := 0;
      Bit_Pos   : Natural := Starting_Bit_Index mod 8;
      This_Len  : Natural;
      Header    : Natural;
   begin
      loop
         This_Len := Natural'Min (Remaining, Max_Compress_Block_Size);
         Header := 3;
         Header := Header + Pad_To_Byte (Header, Bit_Pos);
         Bits := Bits + Header + 32 + 8 * This_Len;
         Bit_Pos := 0;
         Started := True;

         exit when Remaining <= This_Len;
         Remaining := Remaining - This_Len;
      end loop;

      pragma Assert (Started, "stored bit scorer must score at least one block");
      return Bits;
   end Stored_Bit_Size;

   function Fixed_Bit_Size
     (Tokens             : Zlib.LZ77_Matcher.Token_Array;
      Starting_Bit_Index : Natural := 0)
      return Candidate_Score
   is
      Bits : Natural := 3;
   begin
      for T of Tokens loop
         case T.Kind is
            when Zlib.LZ77_Matcher.Literal =>
               declare
                  Code   : Natural;
                  Length : Natural;
               begin
                  Zlib.Fixed_Compress.Fixed_Code (Natural (T.Value), Code, Length);
                  Bits := Bits + Length;
               end;

            when Zlib.LZ77_Matcher.Match =>
               declare
                  L_Sym : constant Natural := Length_Symbol_For (T.Length);
                  D_Sym : constant Natural := Distance_Symbol_For (T.Distance);
                  Code  : Natural;
                  Len   : Natural;
               begin
                  Zlib.Fixed_Compress.Fixed_Code (L_Sym, Code, Len);
                  Bits := Bits + Len;
                  Bits := Bits + Zlib.Deflate_Tables.Length_Extra (L_Sym);
                  Bits := Bits + 5;
                  Bits := Bits + Zlib.Deflate_Tables.Distance_Extra (D_Sym);
               end;
         end case;
      end loop;

      declare
         Code   : Natural;
         Length : Natural;
      begin
         Zlib.Fixed_Compress.Fixed_Code (256, Code, Length);
         Bits := Bits + Length;
      end;

      return
        (Kind  => Fixed_Block,
         Valid => True,
         Bits  => Padded (Bits, Starting_Bit_Index));
   exception
      when others =>
         return (Kind => Fixed_Block, Valid => False, Bits => 0);
   end Fixed_Bit_Size;

   function Dynamic_Bit_Size
     (Tokens             : Zlib.LZ77_Matcher.Token_Array;
      Starting_Bit_Index : Natural := 0)
      return Candidate_Score
   is
      Lit_Freq  : Zlib.Huffman_Builder.Frequency_Array (Litlen_Symbol) := [others => 0];
      Dist_Freq : Zlib.Huffman_Builder.Frequency_Array (Distance_Symbol) := [others => 0];
      CL_Freq   : Zlib.Huffman_Builder.Frequency_Array (Code_Length_Symbol) := [others => 0];

      Lit_Len  : Zlib.Huffman_Builder.Length_Array (Litlen_Symbol) := [others => 0];
      Dist_Len : Zlib.Huffman_Builder.Length_Array (Distance_Symbol) := [others => 0];
      CL_Len   : Zlib.Huffman_Builder.Length_Array (Code_Length_Symbol) := [others => 0];

      LL_Last      : Natural := 256;
      D_Last       : Natural := 0;
      CL_Last      : Natural := 3;
      Has_Distance : Boolean := False;
      Bits         : Natural := 3;
   begin
      for T of Tokens loop
         case T.Kind is
            when Zlib.LZ77_Matcher.Literal =>
               Lit_Freq (Natural (T.Value)) := Lit_Freq (Natural (T.Value)) + 1;
            when Zlib.LZ77_Matcher.Match =>
               Lit_Freq (Length_Symbol_For (T.Length)) :=
                 Lit_Freq (Length_Symbol_For (T.Length)) + 1;
               Dist_Freq (Distance_Symbol_For (T.Distance)) :=
                 Dist_Freq (Distance_Symbol_For (T.Distance)) + 1;
               Has_Distance := True;
         end case;
      end loop;

      Lit_Freq (256) := Lit_Freq (256) + 1;
      if not Has_Distance then
         Dist_Freq (0) := 1;
      end if;

      Zlib.Huffman_Builder.Build_Lengths (Lit_Freq, Lit_Len, 256);
      Zlib.Huffman_Builder.Build_Lengths (Dist_Freq, Dist_Len, 0);

      for Symbol in Lit_Len'Range loop
         if Lit_Len (Symbol) /= 0 then
            LL_Last := Symbol;
         end if;
      end loop;
      LL_Last := Natural'Max (LL_Last, 256);

      for Symbol in Dist_Len'Range loop
         if Dist_Len (Symbol) /= 0 then
            D_Last := Symbol;
         end if;
      end loop;

      for Symbol in 0 .. LL_Last loop
         CL_Freq (Lit_Len (Symbol)) := CL_Freq (Lit_Len (Symbol)) + 1;
      end loop;
      for Symbol in 0 .. D_Last loop
         CL_Freq (Dist_Len (Symbol)) := CL_Freq (Dist_Len (Symbol)) + 1;
      end loop;

      Zlib.Huffman_Builder.Build_Lengths (CL_Freq, CL_Len, 0);

      for Order_Index in Zlib.Deflate_Tables.Code_Length_Order'Range loop
         if CL_Len (Zlib.Deflate_Tables.Code_Length_Order (Order_Index)) /= 0 then
            CL_Last := Order_Index;
         end if;
      end loop;
      CL_Last := Natural'Max (CL_Last, 3);

      --  HLIT, HDIST, HCLEN, followed by code-length-code lengths.
      Bits := Bits + 5 + 5 + 4;
      Bits := Bits + 3 * (CL_Last + 1);

      for Symbol in 0 .. LL_Last loop
         Bits := Bits + CL_Len (Lit_Len (Symbol));
      end loop;
      for Symbol in 0 .. D_Last loop
         Bits := Bits + CL_Len (Dist_Len (Symbol));
      end loop;

      for T of Tokens loop
         case T.Kind is
            when Zlib.LZ77_Matcher.Literal =>
               Bits := Bits + Lit_Len (Natural (T.Value));

            when Zlib.LZ77_Matcher.Match =>
               declare
                  L_Sym : constant Natural := Length_Symbol_For (T.Length);
                  D_Sym : constant Natural := Distance_Symbol_For (T.Distance);
               begin
                  Bits := Bits + Lit_Len (L_Sym);
                  Bits := Bits + Zlib.Deflate_Tables.Length_Extra (L_Sym);
                  Bits := Bits + Dist_Len (D_Sym);
                  Bits := Bits + Zlib.Deflate_Tables.Distance_Extra (D_Sym);
               end;
         end case;
      end loop;

      Bits := Bits + Lit_Len (256);

      return
        (Kind  => Dynamic_Block,
         Valid => True,
         Bits  => Padded (Bits, Starting_Bit_Index));
   exception
      when others =>
         return (Kind => Dynamic_Block, Valid => False, Bits => 0);
   end Dynamic_Bit_Size;

   function Prefer
     (Candidate : Candidate_Score;
      Current   : Candidate_Score)
      return Boolean
   is
   begin
      if not Candidate.Valid then
         return False;
      elsif not Current.Valid then
         return True;
      else
         return Candidate.Bits < Current.Bits
           or else (Candidate.Bits = Current.Bits
                    and then Block_Kind'Pos (Candidate.Kind) < Block_Kind'Pos (Current.Kind));
      end if;
   end Prefer;

   function Choose_From_Scores
     (Stored_Candidate  : Candidate_Score;
      Fixed_Candidate   : Candidate_Score;
      Dynamic_Candidate : Candidate_Score)
      return Candidate_Score
   is
      Best : Candidate_Score := Stored_Candidate;
   begin
      if Prefer (Fixed_Candidate, Best) then
         Best := Fixed_Candidate;
      end if;

      if Prefer (Dynamic_Candidate, Best) then
         Best := Dynamic_Candidate;
      end if;

      return Best;
   end Choose_From_Scores;

   function Choose
     (Input              : Byte_Array;
      Level              : Compression_Level := Default_Level;
      Allow_Dynamic      : Boolean := True;
      Allow_Stored       : Boolean := True;
      Starting_Bit_Index : Natural := 0)
      return Candidate_Score
   is
      Stored_Candidate : constant Candidate_Score :=
        (Kind  => Stored_Block,
         Valid => Allow_Stored,
         Bits  =>
           (if Allow_Stored then
               Stored_Bit_Size (Input'Length, Starting_Bit_Index)
            else
               0));

      Fixed_Tokens : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize
          (Input, Zlib.LZ77_Matcher.Chain_Limit_For_Level (1));
      Fixed_Candidate : constant Candidate_Score :=
        Fixed_Bit_Size (Fixed_Tokens, Starting_Bit_Index);

   begin
      if Allow_Dynamic then
         declare
            Dynamic_Tokens : constant Zlib.LZ77_Matcher.Token_Array :=
              Zlib.LZ77_Matcher.Tokenize_For_Level
                (Input, Level);
            Dynamic_Candidate : constant Candidate_Score :=
              Dynamic_Bit_Size (Dynamic_Tokens, Starting_Bit_Index);
         begin
            return Choose_From_Scores
              (Stored_Candidate, Fixed_Candidate, Dynamic_Candidate);
         end;
      else
         return Choose_From_Scores
           (Stored_Candidate,
            Fixed_Candidate,
            (Kind => Dynamic_Block, Valid => False, Bits => 0));
      end if;
   end Choose;

   function To_Mode (Kind : Block_Kind) return Compression_Mode is
   begin
      case Kind is
         when Stored_Block =>
            return Stored;
         when Fixed_Block =>
            return Fixed;
         when Dynamic_Block =>
            return Dynamic;
      end case;
   end To_Mode;

end Zlib.Block_Chooser;
