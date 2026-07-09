with Ada.Containers.Vectors;
with Zlib.Bits;
with Zlib.Huffman;
with Zlib.Deflate_Tables;

package body Zlib.Raw_Inflate is

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Zlib.Byte);

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

   function To_Array
     (Output : Byte_Vectors.Vector)
      return Zlib.Byte_Array
   is
      Length : constant Natural := Natural (Output.Length);
   begin
      if Length = 0 then
         declare
            Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
      end if;

      declare
         Result : Zlib.Byte_Array (1 .. Length);
      begin
         for I in 1 .. Length loop
            Result (I) := Output.Element (I - 1);
         end loop;

         return Result;
      end;
   end To_Array;

   function Read_U16_Little_Endian
     (R      : in out Zlib.Bits.Bit_Reader;
      Status : out Zlib.Status_Code)
      return Natural
   is
      Lo : Zlib.Byte;
      Hi : Zlib.Byte;
   begin
      Lo := Zlib.Bits.Read_Byte_Aligned (R, Status);
      if Status /= Zlib.Ok then
         return 0;
      end if;

      Hi := Zlib.Bits.Read_Byte_Aligned (R, Status);
      if Status /= Zlib.Ok then
         return 0;
      end if;

      return Natural (Lo) + Natural (Hi) * 256;
   end Read_U16_Little_Endian;

   procedure Decode_Stored_Block
     (R      : in out Zlib.Bits.Bit_Reader;
      Output : in out Byte_Vectors.Vector;
      Status : out Zlib.Status_Code)
   is
      Len  : Natural;
      NLen : Natural;
      B    : Zlib.Byte;
   begin
      Zlib.Bits.Align_To_Byte (R);

      Len := Read_U16_Little_Endian (R, Status);
      if Status /= Zlib.Ok then
         return;
      end if;

      NLen := Read_U16_Little_Endian (R, Status);
      if Status /= Zlib.Ok then
         return;
      end if;

      if Len + NLen /= 16#FFFF# then
         Status := Zlib.Invalid_Stored_Block;
         return;
      end if;

      for I in 1 .. Len loop
         B := Zlib.Bits.Read_Byte_Aligned (R, Status);
         if Status /= Zlib.Ok then
            return;
         end if;

         Output.Append (B);
      end loop;

      Status := Zlib.Ok;
   end Decode_Stored_Block;

   procedure Copy_From_Distance
     (Output   : in out Byte_Vectors.Vector;
      Length   : Natural;
      Distance : Natural;
      Status   : out Zlib.Status_Code)
   is
      Source_Index : Natural;
      B            : Zlib.Byte;
   begin
      pragma Assert (Length > 0, "LZ77 length must be > 0");
      pragma Assert (Distance > 0, "LZ77 distance must be > 0");
      pragma Assert
        (Distance <= Natural (Output.Length),
         "LZ77 distance exceeds output size");

      if Distance = 0 or else Distance > Natural (Output.Length) then
         Status := Zlib.Invalid_Distance;
         return;
      end if;

      for I in 1 .. Length loop
         Source_Index := Natural (Output.Length) - Distance;
         B := Output.Element (Source_Index);
         Output.Append (B);
      end loop;

      Status := Zlib.Ok;
   end Copy_From_Distance;

   procedure Decode_Compressed_Block
     (R             : in out Zlib.Bits.Bit_Reader;
      Lit_Len_Table : Zlib.Huffman.Decode_Table;
      Dist_Table    : Zlib.Huffman.Decode_Table;
      Output        : in out Byte_Vectors.Vector;
      Status        : out Zlib.Status_Code)
   is
      Symbol      : Zlib.Huffman.Symbol_Value;
      Dist_Symbol : Zlib.Huffman.Symbol_Value;
      Length      : Natural;
      Distance    : Natural;
      Extra       : Natural;
   begin
      loop
         Symbol := Zlib.Huffman.Decode (R, Lit_Len_Table, Status);

         if Status /= Zlib.Ok then
            return;
         end if;

         if Symbol <= 255 then
            Output.Append (Zlib.Byte (Symbol));

         elsif Symbol = 256 then
            Status := Zlib.Ok;
            return;

         elsif Symbol in 257 .. 285 then
            Length := Zlib.Deflate_Tables.Length_Base (Symbol);

            if Zlib.Deflate_Tables.Length_Extra (Symbol) /= 0 then
               Extra := Zlib.Bits.Read_Bits (R, Zlib.Deflate_Tables.Length_Extra (Symbol), Status);

               if Status /= Zlib.Ok then
                  return;
               end if;

               Length := Length + Extra;
            end if;

            pragma Assert
              (Length >= 3 and then Length <= 258,
               "decoded LZ77 length out of spec range");

            Dist_Symbol := Zlib.Huffman.Decode (R, Dist_Table, Status);

            if Status /= Zlib.Ok then
               return;
            end if;

            if Dist_Symbol > 29 then
               Status := Zlib.Invalid_Distance;
               return;
            end if;

            Distance := Zlib.Deflate_Tables.Distance_Base (Dist_Symbol);

            if Zlib.Deflate_Tables.Distance_Extra (Dist_Symbol) /= 0 then
               Extra := Zlib.Bits.Read_Bits (R, Zlib.Deflate_Tables.Distance_Extra (Dist_Symbol), Status);

               if Status /= Zlib.Ok then
                  return;
               end if;

               Distance := Distance + Extra;
            end if;

            pragma Assert
              (Distance >= 1 and then Distance <= 32768,
               "decoded LZ77 distance out of spec range");

            Copy_From_Distance (Output, Length, Distance, Status);

            if Status /= Zlib.Ok then
               return;
            end if;

         else
            Status := Zlib.Invalid_Huffman_Code;
            return;
         end if;
      end loop;
   end Decode_Compressed_Block;

   procedure Read_Dynamic_Code_Lengths
     (R           : in out Zlib.Bits.Bit_Reader;
      Total       : Natural;
      CL_Table    : Zlib.Huffman.Decode_Table;
      All_Lengths : out Zlib.Huffman.Code_Length_Array;
      Status      : out Zlib.Status_Code)
   is
      Index    : Natural := All_Lengths'First;
      Last_Len : Zlib.Huffman.Code_Length := 0;
      Symbol   : Zlib.Huffman.Symbol_Value;
      Repeat   : Natural;
      Extra    : Natural;
   begin
      for I in All_Lengths'Range loop
         All_Lengths (I) := 0;
      end loop;

      while Index < All_Lengths'First + Total loop
         Symbol := Zlib.Huffman.Decode (R, CL_Table, Status);

         if Status /= Zlib.Ok then
            return;
         end if;

         if Symbol <= 15 then
            All_Lengths (Index) := Zlib.Huffman.Code_Length (Symbol);
            Last_Len := Zlib.Huffman.Code_Length (Symbol);
            Index := Index + 1;

         elsif Symbol = 16 then
            if Index = All_Lengths'First then
               Status := Zlib.Invalid_Huffman_Code;
               return;
            end if;

            Extra := Zlib.Bits.Read_Bits (R, 2, Status);
            if Status /= Zlib.Ok then
               return;
            end if;

            Repeat := 3 + Extra;

            if Index + Repeat > All_Lengths'First + Total then
               Status := Zlib.Invalid_Huffman_Code;
               return;
            end if;

            for J in 1 .. Repeat loop
               All_Lengths (Index) := Last_Len;
               Index := Index + 1;
            end loop;

         elsif Symbol = 17 then
            Extra := Zlib.Bits.Read_Bits (R, 3, Status);
            if Status /= Zlib.Ok then
               return;
            end if;

            Repeat := 3 + Extra;

            if Index + Repeat > All_Lengths'First + Total then
               Status := Zlib.Invalid_Huffman_Code;
               return;
            end if;

            for J in 1 .. Repeat loop
               All_Lengths (Index) := 0;
               Index := Index + 1;
            end loop;

            Last_Len := 0;

         elsif Symbol = 18 then
            Extra := Zlib.Bits.Read_Bits (R, 7, Status);
            if Status /= Zlib.Ok then
               return;
            end if;

            Repeat := 11 + Extra;

            if Index + Repeat > All_Lengths'First + Total then
               Status := Zlib.Invalid_Huffman_Code;
               return;
            end if;

            for J in 1 .. Repeat loop
               All_Lengths (Index) := 0;
               Index := Index + 1;
            end loop;

            Last_Len := 0;

         else
            Status := Zlib.Invalid_Huffman_Code;
            return;
         end if;
      end loop;

      Status := Zlib.Ok;
   end Read_Dynamic_Code_Lengths;

   procedure Build_Dynamic_Tables
     (R             : in out Zlib.Bits.Bit_Reader;
      Lit_Len_Table : out Zlib.Huffman.Decode_Table;
      Dist_Table    : out Zlib.Huffman.Decode_Table;
      Status        : out Zlib.Status_Code)
   is
      HLIT  : Natural;
      HDIST : Natural;
      HCLEN : Natural;

      CL_Lengths  : Zlib.Huffman.Code_Length_Array (0 .. 18);
      All_Lengths : Zlib.Huffman.Code_Length_Array (0 .. 317);

      Lit_Lengths  : Zlib.Huffman.Code_Length_Array (0 .. 285);
      Dist_Lengths : Zlib.Huffman.Code_Length_Array (0 .. 31);

      CL_Table : Zlib.Huffman.Decode_Table;
      Total    : Natural;
   begin
      HLIT := Zlib.Bits.Read_Bits (R, 5, Status);
      if Status /= Zlib.Ok then
         return;
      end if;

      HDIST := Zlib.Bits.Read_Bits (R, 5, Status);
      if Status /= Zlib.Ok then
         return;
      end if;

      HCLEN := Zlib.Bits.Read_Bits (R, 4, Status);
      if Status /= Zlib.Ok then
         return;
      end if;

      HLIT  := HLIT + 257;
      HDIST := HDIST + 1;
      HCLEN := HCLEN + 4;

      if HLIT > 286 or else HDIST > 32 then
         Status := Zlib.Invalid_Huffman_Code;
         return;
      end if;

      for I in CL_Lengths'Range loop
         CL_Lengths (I) := 0;
      end loop;

      for I in 0 .. HCLEN - 1 loop
         CL_Lengths (Zlib.Deflate_Tables.Code_Length_Order (I)) :=
           Zlib.Huffman.Code_Length
             (Zlib.Bits.Read_Bits (R, 3, Status));

         if Status /= Zlib.Ok then
            return;
         end if;
      end loop;

      Zlib.Huffman.Build (CL_Lengths, CL_Table, Status);
      if Status /= Zlib.Ok then
         return;
      end if;

      Total := HLIT + HDIST;

      Read_Dynamic_Code_Lengths
        (R,
         Total,
         CL_Table,
         All_Lengths,
         Status);

      if Status /= Zlib.Ok then
         return;
      end if;

      for I in Lit_Lengths'Range loop
         Lit_Lengths (I) := 0;
      end loop;

      for I in Dist_Lengths'Range loop
         Dist_Lengths (I) := 0;
      end loop;

      for I in 0 .. HLIT - 1 loop
         Lit_Lengths (I) := All_Lengths (I);
      end loop;

      for I in 0 .. HDIST - 1 loop
         Dist_Lengths (I) := All_Lengths (HLIT + I);
      end loop;

      if Lit_Lengths (256) = 0 then
         Status := Zlib.Invalid_Huffman_Code;
         return;
      end if;

      Zlib.Huffman.Build (Lit_Lengths, Lit_Len_Table, Status);
      if Status /= Zlib.Ok then
         return;
      end if;

      if Has_Non_Zero_Length (Dist_Lengths) then
         Zlib.Huffman.Build (Dist_Lengths, Dist_Table, Status);
      else
         Zlib.Huffman.Clear (Dist_Table);
         Status := Zlib.Ok;
      end if;
   end Build_Dynamic_Tables;

   function Decode
     (Input  : Zlib.Byte_Array;
      Status : out Zlib.Status_Code)
      return Zlib.Byte_Array
   is
      R             : Zlib.Bits.Bit_Reader;
      Output        : Byte_Vectors.Vector;
      Final         : Boolean;
      BType         : Natural;
      Lit_Len_Table : Zlib.Huffman.Decode_Table;
      Dist_Table    : Zlib.Huffman.Decode_Table;
   begin
      Zlib.Bits.Init (R, Input);

      loop
         Final := Zlib.Bits.Read_Bit (R, Status);
         if Status /= Zlib.Ok then
            return To_Array (Output);
         end if;

         BType := Zlib.Bits.Read_Bits (R, 2, Status);
         if Status /= Zlib.Ok then
            return To_Array (Output);
         end if;

         case BType is
            when 0 =>
               Decode_Stored_Block (R, Output, Status);

            when 1 =>
               Zlib.Deflate_Tables.Build_Fixed_Tables (Lit_Len_Table, Dist_Table, Status);

               if Status = Zlib.Ok then
                  Decode_Compressed_Block
                    (R,
                     Lit_Len_Table,
                     Dist_Table,
                     Output,
                     Status);
               end if;

            when 2 =>
               Build_Dynamic_Tables (R, Lit_Len_Table, Dist_Table, Status);

               if Status = Zlib.Ok then
                  Decode_Compressed_Block
                    (R,
                     Lit_Len_Table,
                     Dist_Table,
                     Output,
                     Status);
               end if;

            when others =>
               Status := Zlib.Invalid_Block_Type;
               return To_Array (Output);
         end case;

         if Status /= Zlib.Ok then
            return To_Array (Output);
         end if;

         exit when Final;
      end loop;

      Status := Zlib.Ok;
      return To_Array (Output);
   end Decode;

end Zlib.Raw_Inflate;
