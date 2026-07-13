package body Zlib.BZip2_CRC is

   use type Interfaces.Unsigned_32;

   Polynomial : constant Interfaces.Unsigned_32 := 16#04C1_1DB7#;

   type Table_Array is array (Byte) of Interfaces.Unsigned_32;

   function Build_Table return Table_Array;
   --  Build the byte-indexed table by shifting left and folding on the top bit,
   --  the mirror image of the reflected table's shift-right-and-fold-on-bit-0.

   function Build_Table return Table_Array is
      Result : Table_Array := [others => 0];
      Value  : Interfaces.Unsigned_32;
   begin
      for Index in Byte loop
         Value := Interfaces.Shift_Left (Interfaces.Unsigned_32 (Index), 24);
         for Unused_Bit in 1 .. 8 loop
            if (Value and 16#8000_0000#) /= 0 then
               Value := Interfaces.Shift_Left (Value, 1) xor Polynomial;
            else
               Value := Interfaces.Shift_Left (Value, 1);
            end if;
         end loop;
         Result (Index) := Value;
      end loop;
      return Result;
   end Build_Table;

   Table : constant Table_Array := Build_Table;

   function Update (Current : Checksum; Data : Byte_Array) return Checksum is
      Value : Interfaces.Unsigned_32 := Current;
      Index : Byte;
   begin
      for Item of Data loop
         Index := Byte (Interfaces.Shift_Right (Value, 24) and 16#FF#) xor Item;
         Value := Interfaces.Shift_Left (Value, 8) xor Table (Index);
      end loop;
      return Value;
   end Update;

   function Finish (Current : Checksum) return Checksum is
   begin
      return not Current;
   end Finish;

   function Compute (Data : Byte_Array) return Checksum is
   begin
      return Finish (Update (Initial, Data));
   end Compute;

   function Combine (Running : Checksum; Block : Checksum) return Checksum is
   begin
      return
        (Interfaces.Shift_Left (Running, 1)
         or Interfaces.Shift_Right (Running, 31)) xor Block;
   end Combine;

end Zlib.BZip2_CRC;
