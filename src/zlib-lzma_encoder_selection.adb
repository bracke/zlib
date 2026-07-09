with Ada.Containers.Vectors;
with Zlib.LZMA_Core;
with Zlib.LZMA_Properties;

function Zlib.LZMA_Encoder_Selection
  (Plain : Byte_Array;
   Props : out Byte) return Byte_Array
is
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

   Best     : Byte_Vectors.Vector;
   Best_Len : Natural := Natural'Last;
begin
   Props := Zlib.LZMA_Core.Default_Props;

   for Candidate of Zlib.LZMA_Core.Encode_Candidates loop
      declare
         Coded : constant Byte_Array :=
           Encode_Bounded
             (Plain, Candidate.LC, Candidate.LP, Candidate.PB);
      begin
         if Coded'Length < Best_Len then
            Best.Clear;
            for B of Coded loop
               Best.Append (B);
            end loop;
            Best_Len := Coded'Length;
            Props := Zlib.LZMA_Properties.Props_Byte
              (Candidate.LC, Candidate.LP, Candidate.PB);
         end if;
      end;
   end loop;

   return To_Byte_Array (Best);
end Zlib.LZMA_Encoder_Selection;
