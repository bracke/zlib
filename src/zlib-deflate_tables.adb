package body Zlib.Deflate_Tables is

   procedure Build_Fixed_Tables
     (Lit_Len_Table : out Zlib.Huffman.Decode_Table;
      Dist_Table    : out Zlib.Huffman.Decode_Table;
      Status        : out Zlib.Status_Code)
   is
      Lit_Lengths  : Zlib.Huffman.Code_Length_Array (0 .. 287);
      Dist_Lengths : Zlib.Huffman.Code_Length_Array (0 .. 31);
   begin
      for I in Lit_Lengths'Range loop
         if I <= 143 then
            Lit_Lengths (I) := 8;
         elsif I <= 255 then
            Lit_Lengths (I) := 9;
         elsif I <= 279 then
            Lit_Lengths (I) := 7;
         else
            Lit_Lengths (I) := 8;
         end if;
      end loop;

      for I in Dist_Lengths'Range loop
         Dist_Lengths (I) := 5;
      end loop;

      Zlib.Huffman.Build (Lit_Lengths, Lit_Len_Table, Status);
      if Status /= Zlib.Ok then
         return;
      end if;

      Zlib.Huffman.Build (Dist_Lengths, Dist_Table, Status);
   end Build_Fixed_Tables;

end Zlib.Deflate_Tables;
