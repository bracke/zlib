package body Zlib.BZip2_Bit_Writer is

   use type Interfaces.Unsigned_32;

   procedure Reset (W : out Writer) is
   begin
      W.Data.Clear;
      W.Current := 0;
      W.Bit_Index := 0;
   end Reset;

   procedure Write_Bit (W : in out Writer; Bit : Boolean) is
   begin
      if Bit then
         W.Current := W.Current or Byte (2 ** (7 - W.Bit_Index));
      end if;

      if W.Bit_Index = 7 then
         W.Data.Append (W.Current);
         W.Current := 0;
         W.Bit_Index := 0;
      else
         W.Bit_Index := W.Bit_Index + 1;
      end if;
   end Write_Bit;

   procedure Write_Bits
     (W     : in out Writer;
      Value : Interfaces.Unsigned_32;
      Count : Natural) is
   begin
      for Index in reverse 0 .. Count - 1 loop
         Write_Bit
           (W, (Interfaces.Shift_Right (Value, Index) and 1) /= 0);
      end loop;
   end Write_Bits;

   procedure Flush (W : in out Writer) is
   begin
      if W.Bit_Index /= 0 then
         W.Data.Append (W.Current);
         W.Current := 0;
         W.Bit_Index := 0;
      end if;
   end Flush;

   function To_Array (W : Writer) return Byte_Array is
      Result : Byte_Array (1 .. Natural (W.Data.Length));
   begin
      for Index in Result'Range loop
         Result (Index) := W.Data (Index - 1);
      end loop;
      return Result;
   end To_Array;

end Zlib.BZip2_Bit_Writer;
