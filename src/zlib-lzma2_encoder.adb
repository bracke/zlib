with Ada.Containers.Vectors;
with Zlib.LZMA2_Framing;

function Zlib.LZMA2_Encoder (Plain : Byte_Array) return Byte_Array is
   package Byte_Vectors is new
     Ada.Containers.Vectors (Index_Type => Natural, Element_Type => Byte);

   function To_Byte_Array (Data : Byte_Vectors.Vector) return Byte_Array is
   begin
      if Data.Is_Empty then
         declare
            Empty : constant Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
      end if;

      declare
         Result : Byte_Array (1 .. Natural (Data.Length));
         Out_I  : Natural := Result'First;
      begin
         for B of Data loop
            Result (Out_I) := B;
            Out_I := Out_I + 1;
         end loop;
         return Result;
      end;
   end To_Byte_Array;

   Output : Byte_Vectors.Vector;
   Pos    : Natural := Plain'First;
begin
   while Pos <= Plain'Last loop
      declare
         Remaining   : constant Natural := Plain'Last - Pos + 1;
         Chunk_Len   : constant Natural :=
           Natural'Min (Remaining, Zlib.LZMA2_Framing.Max_Chunk);
         Chunk       : constant Byte_Array := Plain (Pos .. Pos + Chunk_Len - 1);
         Chunk_Props : Byte := Zlib.LZMA2_Framing.Default_Props;
         Coded       : constant Byte_Array := Encode_Selected (Chunk, Chunk_Props);
      begin
         if Coded'Length + 6 < Chunk'Length + 3 then
            declare
               Framed : constant Byte_Array :=
                 Zlib.LZMA2_Framing.Compressed_Chunk
                   (Chunk, Coded, Chunk_Props);
            begin
               for B of Framed loop
                  Output.Append (B);
               end loop;
            end;
         else
            declare
               Framed : constant Byte_Array :=
                 Zlib.LZMA2_Framing.Uncompressed_Chunk
                   (Chunk, Pos = Plain'First);
            begin
               for B of Framed loop
                  Output.Append (B);
               end loop;
            end;
         end if;
         Pos := Pos + Chunk_Len;
      end;
   end loop;

   Output.Append (0);
   return To_Byte_Array (Output);
end Zlib.LZMA2_Encoder;
